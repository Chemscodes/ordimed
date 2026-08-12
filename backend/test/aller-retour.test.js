'use strict';

/**
 * L'aller-retour Firestore -> MongoDB -> Firestore.
 *
 * C'est la garantie de reversibilite. Sans elle, revenir a Firebase
 * signifierait perdre tout ce qui a ete ecrit depuis la bascule — et une
 * migration sans retour possible est une migration qu'on n'ose pas faire.
 *
 * Le fichier exporte doit etre relisable par `BackupService.restaurer`, qui
 * ecrit dans Firestore et vit au tag `firebase-final`. Ce test verifie ce
 * dont cette restauration a besoin : le bon uid de cabinet, les
 * identifiants de documents d'origine, et l'etiquetage des dates.
 */

const assert = require('node:assert/strict');
const { after, before, describe, it } = require('node:test');

process.env.JWT_SECRET = 'secret-de-test';
process.env.NODE_ENV = 'test';

const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');

const { importer } = require('../scripts/import-backup');
const { exporter } = require('../scripts/export-json');
const {
  Cabinet,
  Profile,
  Patient,
  Form,
  Versement,
  RendezVous,
} = require('../models');

let replSet;

before(async () => {
  replSet = await MongoMemoryReplSet.create({ replSet: { count: 1 } });
  await mongoose.connect(replSet.getUri(), { dbName: 'aller_retour' });
});

after(async () => {
  await mongoose.disconnect();
  await replSet.stop();
});

const ts = (iso) => ({ __type: 'timestamp', value: iso });

/** Une sauvegarde Firestore telle que l'app la produit. */
function sauvegardeOrigine() {
  return {
    version: 1,
    parentUid: 'uid-firebase-abc123',
    racine: {
      email: 'cabinet@aller.dz',
      createdAt: ts('2026-01-01T00:00:00.000Z'),
    },
    comptes: {
      medecin_principal: {
        donnees: { name: 'Dr Principal', role: 'medecin_principal', pin: '0000' },
        collections: {},
      },
      'profil-med-xyz': {
        donnees: { name: 'Dr Benali', role: 'medecin', pin: '1234' },
        collections: {
          patients: {
            'patient-doc-789': {
              donnees: {
                nom: 'Benali',
                prenom: 'Amina',
                age: '34',
                prix: '12000',
                doctorId: 'profil-med-xyz',
                createdAt: ts('2026-03-01T09:00:00.000Z'),
              },
              collections: {
                forms: {
                  'form-1': {
                    type: 'Consultation',
                    poids: 72.5,
                    createdAt: ts('2026-03-01T09:30:00.000Z'),
                  },
                },
                versements: {
                  'vers-1': {
                    montant: 2000,
                    createdAt: ts('2026-03-01T10:00:00.000Z'),
                  },
                },
              },
            },
          },
          rendezvous: {
            'rdv-1': {
              donnees: {
                patientId: 'patient-doc-789',
                doctorId: 'profil-med-xyz',
                datetime: ts('2026-05-10T10:00:00.000Z'),
              },
            },
          },
        },
      },
    },
  };
}

describe('Aller-retour', () => {
  let exporte;

  it('importe puis reexporte le cabinet', async () => {
    await importer(sauvegardeOrigine(), {
      motDePasse: 'motdepasse',
      silencieux: true,
    });
    exporte = await exporter('cabinet@aller.dz', { silencieux: true });
    assert.ok(exporte);
  });

  it('rend l uid Firebase d origine, pas l ObjectId', async () => {
    // Sans lui, l'app Firebase refuse le fichier : « cette sauvegarde
    // appartient a un autre cabinet ».
    assert.equal(exporte.parentUid, 'uid-firebase-abc123');
  });

  it('garde « medecin_principal » comme identifiant fixe', () => {
    // 65 endroits de l'app Firebase referencent cette chaine litterale.
    assert.ok(exporte.comptes.medecin_principal);
    assert.equal(exporte.comptes.medecin_principal.donnees.role, 'medecin_principal');
  });

  it('garde les identifiants de documents d origine', () => {
    // Les reutiliser fait que la restauration reecrit les documents
    // existants au lieu d'en creer une seconde serie.
    const profil = exporte.comptes['profil-med-xyz'];
    assert.ok(profil, 'le profil garde son identifiant Firestore');
    assert.ok(profil.collections.patients['patient-doc-789']);
  });

  it('etiquette les dates', () => {
    const p = exporte.comptes['profil-med-xyz'].collections.patients[
      'patient-doc-789'
    ].donnees;
    assert.equal(p.createdAt.__type, 'timestamp');
    assert.equal(p.createdAt.value, '2026-03-01T09:00:00.000Z');
  });

  it('ne laisse fuir ni mot de passe ni PIN', () => {
    // Le fichier part sur une cle USB : il ne doit pas porter les
    // empreintes qui permettent de se connecter.
    const brut = JSON.stringify(exporte);
    assert.ok(!brut.includes('passwordHash'));
    assert.ok(!brut.includes('pinHash'));
  });

  it('emporte les documents et les versements du patient', () => {
    const patient = exporte.comptes['profil-med-xyz'].collections.patients[
      'patient-doc-789'
    ];
    assert.equal(Object.keys(patient.collections.forms).length, 1);
    assert.equal(Object.keys(patient.collections.versements).length, 1);
  });

  it('emporte les rendez-vous', () => {
    const rdvs = exporte.comptes['profil-med-xyz'].collections.rendezvous;
    assert.equal(Object.keys(rdvs).length, 1);
  });

  it('le fichier reexporte est lui-meme reimportable', async () => {
    // La boucle complete : Firestore -> Mongo -> fichier -> Mongo. Si le
    // format derivait d'un tour a l'autre, c'est ici que ca se verrait.
    await mongoose.connection.dropDatabase();

    await importer(exporte, { motDePasse: 'motdepasse', silencieux: true });

    assert.equal(await Cabinet.countDocuments(), 1);
    assert.equal(await Profile.countDocuments(), 2);
    assert.equal(await Patient.countDocuments(), 1);
    assert.equal(await Form.countDocuments(), 1);
    assert.equal(await Versement.countDocuments(), 1);
    assert.equal(await RendezVous.countDocuments(), 1);

    const p = await Patient.findOne();
    // Les types tiennent apres deux conversions.
    assert.equal(p.age, 34);
    assert.equal(p.prix, 12000);
    assert.equal(p.createdAt.toISOString(), '2026-03-01T09:00:00.000Z');
  });

  it('un profil ne d apres la bascule repart avec un PIN utilisable', async () => {
    // L'app Firebase compare `pinCtrl.text != data['pin']` en clair. Un
    // profil arrive sans `pin` serait definitivement inaccessible : la
    // comparaison echoue toujours.
    const { Profile: P } = require('../models');
    const cab = await Cabinet.findOne();
    await P.create({
      parentUid: cab._id,
      name: 'Ne dans Mongo',
      role: 'assistant',
      pinHash: 'un-hachage-irreversible',
    });

    const ex = await exporter('cabinet@aller.dz', { silencieux: true });
    const nouveau = Object.values(ex.comptes).find(
      (c) => c.donnees.name === 'Ne dans Mongo'
    );
    assert.ok(nouveau);
    assert.equal(nouveau.donnees.pin, '0000');
    assert.deepEqual(ex.pinsReinitialises, ['Ne dans Mongo']);

    // Les profils venus de Firestore, eux, n'emportent aucun `pin` : la
    // restauration fusionne et leur valeur d'origine reste en place.
    const ancien = ex.comptes.medecin_principal;
    assert.equal(ancien.donnees.pin, undefined);

    // Et jamais le hachage.
    assert.ok(!JSON.stringify(ex).includes('un-hachage-irreversible'));
  });

  it('le second aller-retour rend le meme uid', async () => {
    const deuxieme = await exporter('cabinet@aller.dz', { silencieux: true });
    assert.equal(deuxieme.parentUid, 'uid-firebase-abc123');
    assert.ok(deuxieme.comptes.medecin_principal);
  });
});
