'use strict';

/**
 * L'import des vraies données.
 *
 * C'est la pièce la plus risquée de la migration : elle touche le cabinet
 * réel, une seule fois, et une erreur silencieuse — un versement compté
 * deux fois, un patient dupliqué — ne se voit qu'après coup.
 *
 * Le fichier d'entrée reproduit exactement ce que produit `BackupService`
 * côté Flutter, pièges compris : dates étiquetées `{__type:'timestamp'}`,
 * patients écrits en double sous deux profils, âge en chaîne, prix en
 * chaîne, versements présents à la fois dans la sous-collection et dans le
 * tableau du document.
 */

const assert = require('node:assert/strict');
const { after, before, describe, it } = require('node:test');

process.env.JWT_SECRET = 'secret-de-test';
process.env.NODE_ENV = 'test';

const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');

const { importer } = require('../scripts/import-backup');
const {
  Cabinet,
  Profile,
  Patient,
  Form,
  Versement,
  RendezVous,
  Waiting,
} = require('../models');

let replSet;

before(async () => {
  replSet = await MongoMemoryReplSet.create({ replSet: { count: 1 } });
  await mongoose.connect(replSet.getUri(), { dbName: 'import_test' });
});

after(async () => {
  await mongoose.disconnect();
  await replSet.stop();
});

/** Une date au format de la sauvegarde Flutter. */
const ts = (iso) => ({ __type: 'timestamp', value: iso });

/**
 * Une sauvegarde réaliste.
 *
 * Le même patient apparaît sous le médecin **et** sous l'assistant : c'est
 * ce que Firestore écrivait. La même entrée de salle d'attente apparaît
 * trois fois.
 */
function sauvegardeExemple() {
  const patientDoctor = {
    donnees: {
      nom: 'Benali',
      prenom: 'Amina',
      // Chaîne : c'est ainsi que les anciens dossiers la portent.
      age: '34',
      tel: '0551234567',
      // Chaîne aussi, selon l'écran de saisie d'origine.
      prix: '12000',
      imc: '23,7',
      totalVersements: 5000,
      doctorId: 'med1',
      assistantId: 'ass1',
      motif: 'suivi',
      motifs: ['suivi'],
      createdAt: ts('2026-03-01T09:00:00.000Z'),
      // Présent dans le tableau du document, et aussi dans la
      // sous-collection ci-dessous : le même versement, deux fois.
      versements: [
        { montant: 2000, createdAt: ts('2026-03-01T10:00:00.000Z') },
        { montant: 3000, createdAt: ts('2026-04-01T10:00:00.000Z') },
      ],
    },
    collections: {
      forms: {
        f1: {
          type: 'Dossier initial',
          contenu: 'Premier rendez-vous',
          createdAt: ts('2026-03-01T09:05:00.000Z'),
        },
        f2: {
          type: 'Consultation',
          poids: 72.5,
          // Cinquième orthographe du numéro de séance rencontrée en base.
          seance_numero: '3',
          createdAt: ts('2026-04-01T09:05:00.000Z'),
        },
      },
      versements: {
        v1: { montant: 2000, createdAt: ts('2026-03-01T10:00:00.000Z') },
      },
    },
  };

  const entreeFile = {
    donnees: {
      patientId: 'pat1',
      patientNom: 'Benali',
      doctorId: 'med1',
      assistantId: 'ass1',
      // Ancien vocabulaire seul : pas de champ `etape`.
      status: 'done',
      createdAt: ts('2026-04-01T08:30:00.000Z'),
      closedAt: ts('2026-04-01T09:30:00.000Z'),
    },
  };

  const rdv = {
    donnees: {
      patientId: 'pat1',
      patientNom: 'Benali',
      doctorId: 'med1',
      assistantId: 'ass1',
      datetime: ts('2026-05-10T10:00:00.000Z'),
      // Pas de champ `etape` : antérieur au parcours unifié.
      createdAt: ts('2026-05-01T10:00:00.000Z'),
    },
  };

  return {
    version: 1,
    parentUid: 'firebase-uid',
    racine: {
      email: 'cabinet@reel.dz',
      createdAt: ts('2026-01-01T00:00:00.000Z'),
    },
    comptes: {
      medecin_principal: {
        donnees: { name: 'Dr Principal', role: 'medecin_principal', pin: '0000' },
        collections: {},
      },
      med1: {
        donnees: { name: 'Dr Benali', role: 'medecin', pin: '1234' },
        collections: {
          patients: { pat1: patientDoctor },
          salle_attente: { w1: entreeFile },
          rendezvous: { r1: rdv },
        },
      },
      ass1: {
        donnees: { name: 'Amina', role: 'assistant', pin: '5678' },
        collections: {
          // La seconde copie du même patient.
          patients: { pat1: patientDoctor },
          salle_attente: { w1: entreeFile },
          rendezvous: { r1: rdv },
          purchases: {
            a1: {
              donnees: {
                produit: 'Gants',
                montant: 1500,
                createdAt: ts('2026-04-01T11:00:00.000Z'),
              },
            },
          },
        },
      },
    },
  };
}

describe('Import de sauvegarde', () => {
  let rapport;

  it('importe un cabinet complet', async () => {
    rapport = await importer(sauvegardeExemple(), {
      motDePasse: 'motdepasse',
      silencieux: true,
    });

    const cabinet = await Cabinet.findOne({ email: 'cabinet@reel.dz' });
    assert.ok(cabinet);
    assert.equal(await Profile.countDocuments({ parentUid: cabinet._id }), 3);
  });

  it('dédoublonne les copies Firestore', async () => {
    // Le patient était écrit deux fois, la file et le rendez-vous aussi.
    assert.equal(await Patient.countDocuments(), 1);
    assert.equal(await Waiting.countDocuments(), 1);
    assert.equal(await RendezVous.countDocuments(), 1);
  });

  it('convertit les types hétérogènes', async () => {
    const p = await Patient.findOne({ nom: 'Benali' });
    // Chaîne en base, entier après import.
    assert.equal(p.age, 34);
    assert.equal(p.prix, 12000);
    // L'IMC reste une chaîne à virgule : l'app l'affiche tel quel.
    assert.equal(p.imc, '23,7');
    assert.ok(p.createdAt instanceof Date);
    assert.equal(p.createdAt.toISOString(), '2026-03-01T09:00:00.000Z');
  });

  it('ne compte pas deux fois un versement présent des deux côtés', async () => {
    // Le piège central : 2000 est à la fois dans la sous-collection et dans
    // le tableau du document. Le compter deux fois gonflerait le total
    // affiché au patient.
    const versements = await Versement.find().sort({ createdAt: 1 });
    assert.equal(versements.length, 2);
    assert.deepEqual(
      versements.map((v) => v.montant),
      [2000, 3000]
    );
  });

  it('récupère les versements qui n’existent que dans le tableau', async () => {
    // Tout l'historique antérieur à la sous-collection vit là.
    const v = await Versement.findOne({ montant: 3000 });
    assert.ok(v);
    assert.equal(v.dayKey, '2026-04-01');
  });

  it('relie les documents à leur patient', async () => {
    const p = await Patient.findOne({ nom: 'Benali' });
    const forms = await Form.find({ patientId: p._id });
    assert.equal(forms.length, 2);
  });

  it('rabat les cinq orthographes du numéro de séance', async () => {
    const f = await Form.findOne({ type: 'Consultation' });
    assert.equal(f.seanceNumero, '3');
    assert.equal(f.poids, 72.5);
  });

  it('traduit l’ancien vocabulaire de la salle d’attente', async () => {
    // L'entrée ne portait que `status: done`.
    const w = await Waiting.findOne();
    assert.equal(w.etape, 'honore');
    assert.equal(w.status, 'done');
    assert.ok(w.closedAt);
  });

  it('lit comme « planifie » un rendez-vous sans étape', async () => {
    const r = await RendezVous.findOne();
    assert.equal(r.etape, 'planifie');
    assert.equal(r.duree, 20);
  });

  it('rebranche les références entre profils et patients', async () => {
    const p = await Patient.findOne({ nom: 'Benali' });
    const medecin = await Profile.findOne({ name: 'Dr Benali' });
    const assistant = await Profile.findOne({ name: 'Amina' });
    assert.equal(String(p.doctorId), String(medecin._id));
    assert.equal(String(p.assistantId), String(assistant._id));
  });

  it('hache le PIN qui était en clair', async () => {
    const medecin = await Profile.findOne({ name: 'Dr Benali' });
    assert.ok(medecin.pinHash);
    assert.notEqual(medecin.pinHash, '1234');
  });

  it('est rejouable sans rien dupliquer', async () => {
    // Une migration qu'on ne peut pas rejouer est une migration qu'on
    // n'ose pas commencer.
    const avant = {
      cabinets: await Cabinet.countDocuments(),
      profils: await Profile.countDocuments(),
      patients: await Patient.countDocuments(),
      forms: await Form.countDocuments(),
      versements: await Versement.countDocuments(),
      rdv: await RendezVous.countDocuments(),
      file: await Waiting.countDocuments(),
    };

    await importer(sauvegardeExemple(), { silencieux: true });

    assert.deepEqual(
      {
        cabinets: await Cabinet.countDocuments(),
        profils: await Profile.countDocuments(),
        patients: await Patient.countDocuments(),
        forms: await Form.countDocuments(),
        versements: await Versement.countDocuments(),
        rdv: await RendezVous.countDocuments(),
        file: await Waiting.countDocuments(),
      },
      avant
    );
  });

  it('compte les copies écartées', async () => {
    assert.ok(rapport.compteur.ignores >= 1);
  });

  it('refuse un fichier qui n’est pas une sauvegarde', async () => {
    await assert.rejects(
      () => importer({ nimporte: 'quoi' }, { silencieux: true }),
      /sauvegarde Ordimed/
    );
  });

  it('exige un mot de passe pour un cabinet inconnu', async () => {
    // Firebase gardait le mot de passe de son côté : la sauvegarde ne le
    // contient pas, et rien ne permet de le deviner.
    const autre = sauvegardeExemple();
    autre.racine.email = 'inconnu@reel.dz';
    await assert.rejects(
      () => importer(autre, { silencieux: true }),
      /mot de passe/
    );
  });
});
