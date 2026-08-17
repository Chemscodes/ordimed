'use strict';

/**
 * Tests d'intégration du backend.
 *
 * Contre un **vrai** MongoDB en replica set, lancé en mémoire par
 * mongodb-memory-server. Pas de base simulée : les transactions, les index
 * uniques et les opérateurs `$inc` / `$slice` ne se comportent comme en
 * production que sur un vrai serveur — et ce sont précisément eux qui
 * portent la logique de ce backend.
 *
 *   node --test test/
 */

const assert = require('node:assert/strict');
const { after, before, describe, it } = require('node:test');

process.env.JWT_SECRET = 'secret-de-test';
process.env.NODE_ENV = 'test';

const mongoose = require('mongoose');
const request = require('supertest');
const { MongoMemoryReplSet } = require('mongodb-memory-server');

const { creerApp } = require('../app');
const { Patient, Profile, Waiting } = require('../models');

let replSet;
let app;

/** Jeton et profils du cabinet de test, remplis par le premier bloc. */
const ctx = {};

before(async () => {
  // Un seul nœud suffit : ce qu'on veut du replica set, ce sont les
  // transactions, pas la réplication.
  replSet = await MongoMemoryReplSet.create({ replSet: { count: 1 } });
  await mongoose.connect(replSet.getUri(), { dbName: 'ordimed_test' });
  app = creerApp();
});

after(async () => {
  await mongoose.disconnect();
  await replSet.stop();
});

const auth = (r) => r.set('Authorization', `Bearer ${ctx.token}`);

describe('Transactions', () => {
  it('sont bien disponibles', async () => {
    // Si ce test échoue, tous les suivants qui écrivent en transaction
    // échoueront aussi — et pour cette raison-là, pas pour la leur.
    const session = await mongoose.startSession();
    session.startTransaction();
    await session.abortTransaction();
    await session.endSession();
  });
});

describe('Authentification', () => {
  it("l'inscription crée le cabinet et son médecin principal", async () => {
    // Les deux allaient ensemble : un cabinet sans profil est
    // inutilisable, on ne peut même pas s'y connecter.
    const r = await request(app)
      .post('/api/auth/register')
      .send({ email: 'Cabinet@Test.dz', password: 'motdepasse' });

    assert.equal(r.status, 201);
    assert.ok(r.body.token);
    // L'email est normalisé en minuscules, sinon deux comptes pour la même
    // personne.
    assert.equal(r.body.cabinet.email, 'cabinet@test.dz');

    ctx.token = r.body.token;

    const profils = await auth(request(app).get('/api/profiles'));
    assert.equal(profils.status, 200);
    assert.equal(profils.body.length, 1);
    assert.equal(profils.body[0].role, 'medecin_principal');
  });

  it('ne renvoie jamais le PIN', async () => {
    const r = await auth(request(app).get('/api/profiles'));
    assert.equal(r.body[0].pinHash, undefined);
    assert.equal(r.body[0].pin, undefined);
  });

  it('refuse un email déjà pris', async () => {
    // Le mot de passe doit être valide, sinon c'est la longueur qui est
    // refusée (400) et le contrôle de doublon n'est jamais atteint — ce que
    // la première version de ce test faisait sans le voir.
    const r = await request(app)
      .post('/api/auth/register')
      .send({ email: 'cabinet@test.dz', password: 'assez-long' });
    assert.equal(r.status, 409);
  });

  it('refuse un mot de passe trop court', async () => {
    const r = await request(app)
      .post('/api/auth/register')
      .send({ email: 'x@test.dz', password: '123' });
    assert.equal(r.status, 400);
  });

  it('la connexion rend un jeton', async () => {
    const r = await request(app)
      .post('/api/auth/login')
      .send({ email: 'cabinet@test.dz', password: 'motdepasse' });
    assert.equal(r.status, 200);
    assert.ok(r.body.token);
  });

  it('dit la même chose pour un email inconnu et un mot de passe faux', async () => {
    // Distinguer les deux dirait lesquels de vos emails sont enregistrés.
    const a = await request(app)
      .post('/api/auth/login')
      .send({ email: 'cabinet@test.dz', password: 'faux' });
    const b = await request(app)
      .post('/api/auth/login')
      .send({ email: 'inexistant@test.dz', password: 'faux' });

    assert.equal(a.status, 401);
    assert.equal(b.status, 401);
    assert.equal(a.body.error, b.body.error);
  });

  it('sans jeton, rien ne passe', async () => {
    const r = await request(app).get('/api/patients');
    assert.equal(r.status, 401);
  });

  it('un jeton bricolé ne passe pas', async () => {
    const r = await request(app)
      .get('/api/patients')
      .set('Authorization', 'Bearer nimportequoi');
    assert.equal(r.status, 401);
  });

  it('le PIN est vérifié côté serveur', async () => {
    const profils = await auth(request(app).get('/api/profiles'));
    const principal = profils.body[0];

    const bon = await auth(
      request(app).post('/api/auth/pin')
    ).send({ profileId: principal.id, pin: '0000' });
    assert.equal(bon.status, 200);

    const mauvais = await auth(
      request(app).post('/api/auth/pin')
    ).send({ profileId: principal.id, pin: '9999' });
    assert.equal(mauvais.status, 401);
  });

  it("« medecin_principal » se résout comme dans Firestore", async () => {
    // 65 endroits dans l'app Flutter référencent cette chaîne littérale.
    const r = await auth(
      request(app).post('/api/auth/pin')
    ).send({ profileId: 'medecin_principal', pin: '0000' });
    assert.equal(r.status, 200);
    assert.equal(r.body.profile.role, 'medecin_principal');
  });
});

describe('Profils', () => {
  it('crée un médecin et un assistant', async () => {
    const med = await auth(request(app).post('/api/profiles')).send({
      name: 'Dr Benali',
      role: 'medecin',
      pin: '1234',
    });
    assert.equal(med.status, 201);
    ctx.medecin = med.body;

    const ass = await auth(request(app).post('/api/profiles')).send({
      name: 'Amina',
      role: 'assistant',
      pin: '5678',
    });
    assert.equal(ass.status, 201);
    ctx.assistant = ass.body;
  });

  it('refuse un second médecin principal', async () => {
    // L'index partiel garantit l'unicité : `medecin_principal` doit rester
    // résoluble sans ambiguïté.
    const r = await auth(request(app).post('/api/profiles')).send({
      name: 'Doublon',
      role: 'medecin_principal',
      pin: '1111',
    });
    assert.equal(r.status, 400);
  });

  it('refuse un PIN qui ne fait pas 4 à 6 chiffres', async () => {
    const r = await auth(request(app).post('/api/profiles')).send({
      name: 'X',
      role: 'assistant',
      pin: '12',
    });
    assert.equal(r.status, 400);
  });

  it('protège le médecin principal de la suppression', async () => {
    // Sans lui, plus personne ne peut entrer dans le cabinet.
    const profils = await auth(request(app).get('/api/profiles'));
    const principal = profils.body.find((p) => p.role === 'medecin_principal');
    const r = await auth(request(app).delete(`/api/profiles/${principal.id}`));
    assert.equal(r.status, 400);
  });
});

describe('Patients', () => {
  it('la création pose le dossier, le formulaire initial et la file', async () => {
    // Les trois partaient ensemble dans add_patient_form.dart : un échec
    // partiel laissait le patient visible d'un côté et absent de l'autre.
    const r = await auth(request(app).post('/api/patients')).send({
      nom: 'Benali',
      prenom: 'Amina',
      // Chaîne : c'est ainsi que les anciens dossiers la portent.
      age: '34',
      tel: '0551234567',
      motifs: ['suivi', 'nutrition'],
      doctorId: ctx.medecin.id,
      assistantId: ctx.assistant.id,
      formulaireInitial: 'Premier rendez-vous',
    });

    assert.equal(r.status, 201);
    // Convertie en entier à l'entrée.
    assert.equal(r.body.age, 34);
    // `motif` est écrit en plus de `motifs` : des vues ne lisent que lui.
    assert.equal(r.body.motif, 'suivi, nutrition');
    ctx.patient = r.body;

    const detail = await auth(
      request(app).get(`/api/patients/${ctx.patient.id}/detail`)
    );
    assert.equal(detail.body.forms.length, 1);
    assert.equal(detail.body.forms[0].type, 'Dossier initial');

    const file = await auth(request(app).get('/api/waiting'));
    assert.equal(file.body.length, 1);
    assert.equal(file.body[0].etape, 'arrive');
    // L'ancien vocabulaire reste écrit : les entrées existantes ne portent
    // que `status`, et cesser de l'écrire rendrait la file illisible.
    assert.equal(file.body[0].status, 'waiting');
  });

  it('accepte un prix en chaîne, comme les anciens écrans', async () => {
    const r = await auth(
      request(app).put(`/api/patients/${ctx.patient.id}`)
    ).send({ prix: '12 500,50', nombreSeances: '10' });
    assert.equal(r.body.prix, 12500.5);
    assert.equal(r.body.nombreSeances, 10);
  });

  it("l'IMC reste une chaîne à virgule", async () => {
    const r = await auth(
      request(app).put(`/api/patients/${ctx.patient.id}`)
    ).send({ imc: '23,7' });
    assert.equal(r.body.imc, '23,7');
  });

  it('la suppression est douce et réversible', async () => {
    const p = await auth(request(app).post('/api/patients')).send({
      nom: 'Temporaire',
      doctorId: ctx.medecin.id,
      ajouterEnSalle: false,
    });

    await auth(request(app).delete(`/api/patients/${p.body.id}`));

    const liste = await auth(request(app).get('/api/patients'));
    assert.ok(!liste.body.some((x) => x.id === p.body.id));

    // Le dossier existe toujours : ses versements et son historique aussi.
    const avec = await auth(
      request(app).get('/api/patients').query({ inclureSupprimes: '1' })
    );
    assert.ok(avec.body.some((x) => x.id === p.body.id));

    await auth(request(app).post(`/api/patients/${p.body.id}/restaurer`));
    const apres = await auth(request(app).get('/api/patients'));
    assert.ok(apres.body.some((x) => x.id === p.body.id));
  });

  it('un dossier sans deletedAt reste visible', async () => {
    // Le cas majoritaire : tous les dossiers antérieurs à la suppression
    // douce n'ont pas du tout ce champ. Un filtre `{deletedAt: null}` mal
    // posé les masquerait tous.
    await Patient.collection.insertOne({
      parentUid: new mongoose.Types.ObjectId(ctx.patient.parentUid),
      nom: 'Ancien',
      prenom: 'Dossier',
      createdAt: new Date(),
    });
    const liste = await auth(request(app).get('/api/patients'));
    assert.ok(liste.body.some((x) => x.nom === 'Ancien'));
  });

  it('un cabinet ne voit pas les patients d’un autre', async () => {
    // C'est toute la sécurité du produit. En REST il n'y a plus de règle
    // globale : un oubli de filtre n'échoue pas, il expose.
    const autre = await request(app)
      .post('/api/auth/register')
      .send({ email: 'voisin@test.dz', password: 'motdepasse' });

    const r = await request(app)
      .get('/api/patients')
      .set('Authorization', `Bearer ${autre.body.token}`);

    assert.equal(r.status, 200);
    assert.equal(r.body.length, 0);

    // Et l'accès direct par identifiant ne passe pas davantage.
    const direct = await request(app)
      .get(`/api/patients/${ctx.patient.id}`)
      .set('Authorization', `Bearer ${autre.body.token}`);
    assert.equal(direct.status, 404);
  });
});

describe('Versements', () => {
  it('mettent à jour le total, le cache et les statistiques', async () => {
    const r = await auth(request(app).post('/api/versements')).send({
      patientId: ctx.patient.id,
      montant: 2000,
    });
    assert.equal(r.status, 201);

    const p = await auth(request(app).get(`/api/patients/${ctx.patient.id}`));
    assert.equal(p.body.totalVersements, 2000);
    assert.equal(p.body.versements.length, 1);

    const stats = await auth(request(app).get('/api/stats/daily'));
    assert.equal(stats.body[0].versementsTotal, 2000);
    assert.equal(stats.body[0].versementsCount, 1);
  });

  it('le total s’incrémente au lieu d’être réécrit', async () => {
    // Deux postes qui encaissent en même temps ne s'écrasent plus :
    // c'était une faiblesse réelle de la version Firestore.
    await Promise.all(
      [500, 300, 200].map((montant) =>
        auth(request(app).post('/api/versements')).send({
          patientId: ctx.patient.id,
          montant,
        })
      )
    );
    const p = await auth(request(app).get(`/api/patients/${ctx.patient.id}`));
    assert.equal(p.body.totalVersements, 3000);
  });

  it('le cache du dossier cesse de grossir', async () => {
    // Un document Firestore plafonnait à 1 Mo et l'écriture aurait fini par
    // être rejetée en silence. La borne est appliquée côté serveur : le
    // client ne peut plus la contourner.
    for (let i = 0; i < 55; i++) {
      await auth(request(app).post('/api/versements')).send({
        patientId: ctx.patient.id,
        montant: 10,
      });
    }
    const p = await auth(request(app).get(`/api/patients/${ctx.patient.id}`));
    assert.equal(p.body.versements.length, 50);

    // L'historique complet, lui, est intact.
    const tous = await auth(
      request(app).get('/api/versements').query({ patientId: ctx.patient.id })
    );
    assert.equal(tous.body.length, 59);
  });

  it('refuse un montant nul ou négatif', async () => {
    const r = await auth(request(app).post('/api/versements')).send({
      patientId: ctx.patient.id,
      montant: -100,
    });
    assert.equal(r.status, 400);
  });
});

describe('Rendez-vous et créneaux', () => {
  const jour = new Date('2026-09-15T10:00:00.000Z');

  it('planifie un rendez-vous', async () => {
    const r = await auth(request(app).post('/api/rendezvous')).send({
      patientId: ctx.patient.id,
      doctorId: ctx.medecin.id,
      assistantId: ctx.assistant.id,
      datetime: jour.toISOString(),
      duree: 20,
    });
    assert.equal(r.status, 201);
    assert.equal(r.body.etape, 'planifie');
    ctx.rdv = r.body;
  });

  it('refuse un créneau qui chevauche', async () => {
    // Le contrôle existait côté Flutter, ce qui suffisait tant que le
    // client était le seul chemin vers la base.
    const r = await auth(request(app).post('/api/rendezvous')).send({
      patientId: ctx.patient.id,
      doctorId: ctx.medecin.id,
      datetime: new Date(jour.getTime() + 10 * 60000).toISOString(),
      duree: 20,
    });
    assert.equal(r.status, 409);
    assert.ok(r.body.conflit);
  });

  it('accepte un créneau qui suit exactement', async () => {
    // 10h00-10h20 puis 10h20-10h40 se suivent : les bornes ne comptent pas,
    // sinon aucune journée pleine ne serait possible.
    const r = await auth(request(app).post('/api/rendezvous')).send({
      patientId: ctx.patient.id,
      doctorId: ctx.medecin.id,
      datetime: new Date(jour.getTime() + 20 * 60000).toISOString(),
      duree: 20,
    });
    assert.equal(r.status, 201);
    ctx.rdvSuivant = r.body;
  });

  it('un rendez-vous annulé libère son créneau', async () => {
    // Sinon une annulation laisse un trou inutilisable et l'assistant
    // contourne l'outil pour recaser le patient.
    await auth(
      request(app).post(`/api/rendezvous/${ctx.rdvSuivant.id}/etape`)
    ).send({ etape: 'annule' });

    const r = await auth(request(app).post('/api/rendezvous')).send({
      patientId: ctx.patient.id,
      doctorId: ctx.medecin.id,
      datetime: new Date(jour.getTime() + 20 * 60000).toISOString(),
      duree: 20,
    });
    assert.equal(r.status, 201);
    await auth(request(app).delete(`/api/rendezvous/${r.body.id}`));
  });

  it('un rendez-vous déplacé ne se bloque pas lui-même', async () => {
    const r = await auth(
      request(app).put(`/api/rendezvous/${ctx.rdv.id}`)
    ).send({ datetime: jour.toISOString(), duree: 30 });
    assert.equal(r.status, 200);
    assert.equal(r.body.duree, 30);
  });

  it('ne planifie rien sans date', async () => {
    // Le supposer à minuit fabriquerait un faux conflit.
    const r = await auth(request(app).post('/api/rendezvous')).send({
      patientId: ctx.patient.id,
      doctorId: ctx.medecin.id,
    });
    assert.equal(r.status, 400);
  });
});

describe('Parcours complet du patient', () => {
  it('rendez-vous → salle → consultation → clôture', async () => {
    // Le trou du parcours d'origine : l'assistant devait ressaisir le
    // patient dans la file alors que le rendez-vous portait déjà tout.
    await Waiting.deleteMany({});

    const arrive = await auth(
      request(app).post(`/api/rendezvous/${ctx.rdv.id}/arrive`)
    );
    assert.equal(arrive.status, 201);
    assert.equal(arrive.body.etape, 'arrive');
    // L'entrée garde le lien vers son rendez-vous.
    assert.equal(String(arrive.body.rdvId), String(ctx.rdv.id));

    const waitingId = arrive.body.id;

    const demarre = await auth(
      request(app).post(`/api/waiting/${waitingId}/demarrer`)
    );
    assert.equal(demarre.body.etape, 'en_cours');
    assert.equal(demarre.body.status, 'in_consultation');

    const avant = await auth(
      request(app).get(`/api/patients/${ctx.patient.id}`)
    );

    const cloture = await auth(
      request(app).post(`/api/waiting/${waitingId}/cloturer`)
    );
    assert.equal(cloture.status, 200);

    // Les trois effets de la clôture, ensemble.
    const apres = await auth(
      request(app).get(`/api/patients/${ctx.patient.id}`)
    );
    assert.equal(
      apres.body.seancesEffectuees,
      avant.body.seancesEffectuees + 1
    );

    const file = await auth(request(app).get('/api/waiting'));
    const entree = file.body.find((e) => e.id === waitingId);
    assert.equal(entree.etape, 'honore');
    assert.ok(entree.closedAt);

    // Le rendez-vous ne reste pas « à venir » pour toujours.
    const rdvs = await auth(request(app).get('/api/rendezvous'));
    const rdv = rdvs.body.find((r) => r.id === ctx.rdv.id);
    assert.equal(rdv.etape, 'honore');
  });

  it('refuse de mettre deux fois le même patient dans la file', async () => {
    // Sans ce garde-fou, un double-clic crée deux entrées et le patient
    // apparaît en double chez le médecin.
    await Waiting.deleteMany({});

    const a = await auth(request(app).post('/api/waiting')).send({
      patientId: ctx.patient.id,
    });
    assert.equal(a.status, 201);

    const b = await auth(request(app).post('/api/waiting')).send({
      patientId: ctx.patient.id,
    });
    assert.equal(b.status, 409);
  });
});

describe('Documents', () => {
  it('enregistre une consultation avec ses mesures typées', async () => {
    const r = await auth(request(app).post('/api/forms')).send({
      patientId: ctx.patient.id,
      type: 'Consultation',
      poids: 72.5,
      taille: 175,
      imc: '23,7',
      notes: 'Rien à signaler',
      contenu: 'Poids : 72.5 kg\nRAS',
    });
    assert.equal(r.status, 201);
    assert.equal(r.body.poids, 72.5);
    assert.equal(r.body.imc, '23,7');
  });

  it('refuse un type inconnu', async () => {
    // consultation_page.dart compare ces valeurs littéralement pour savoir
    // ce qui a été rédigé aujourd'hui.
    const r = await auth(request(app).post('/api/forms')).send({
      patientId: ctx.patient.id,
      type: 'Type inventé',
    });
    assert.equal(r.status, 400);
  });

  it('garde les sections du formulaire médecin telles quelles', async () => {
    const sections = { allergies: 'aucune', sommeil: 'correct' };
    const r = await auth(request(app).post('/api/forms')).send({
      patientId: ctx.patient.id,
      type: 'Formulaire medecin',
      sections,
    });
    assert.deepEqual(r.body.sections, sections);
  });
});

describe('Statistiques', () => {
  it('se recalculent depuis les écritures réelles', async () => {
    // Un compteur incrémenté peut dériver. Sans moyen de le reconstruire,
    // l'écart resterait pour toujours.
    const { DailyStat } = require('../models');
    await DailyStat.updateMany({}, { $set: { versementsTotal: 999999 } });

    const r = await auth(request(app).post('/api/stats/recalculer'));
    assert.equal(r.status, 200);

    const stats = await auth(request(app).get('/api/stats/daily'));
    assert.equal(stats.body[0].versementsTotal, 3550);
  });
});

describe('Journal d’erreurs', () => {
  it('accepte un signalement sans jeton', async () => {
    // Une erreur peut survenir avant toute connexion.
    const r = await request(app)
      .post('/api/errors')
      .send({ message: 'plantage', platform: 'windows' });
    assert.equal(r.status, 204);
  });
});

describe('Facturation de la seance', () => {
  let pat;
  let waitingId;

  it('le tarif de seance se fixe sur le dossier', async () => {
    // Le medecin comme l'assistant peuvent le poser : c'est un champ du
    // dossier, pas une prerogative de role.
    const p = await auth(request(app).post('/api/patients')).send({
      nom: 'Tarif',
      doctorId: ctx.medecin.id,
      ajouterEnSalle: false,
    });
    pat = p.body;

    const r = await auth(request(app).put(`/api/patients/${pat.id}`)).send({
      prixSeance: '2 000',
    });
    assert.equal(r.body.prixSeance, 2000);
  });

  it('la cloture ajoute le prix de la seance au total du', async () => {
    const mise = await auth(request(app).post('/api/waiting')).send({
      patientId: pat.id,
    });
    waitingId = mise.body.id;

    const avant = await auth(request(app).get(`/api/patients/${pat.id}`));
    assert.equal(avant.body.prix, null);

    await auth(request(app).post(`/api/waiting/${waitingId}/cloturer`)).send({
      prixSeance: 2000,
    });

    const apres = await auth(request(app).get(`/api/patients/${pat.id}`));
    assert.equal(apres.body.prix, 2000);
    assert.equal(apres.body.seancesEffectuees, 1);
  });

  it('une seconde cloture ne facture pas deux fois', async () => {
    // Le double clic. Sans garde, le patient payait deux fois la meme
    // seance — et voyait sa seance comptee deux fois.
    const r = await auth(
      request(app).post(`/api/waiting/${waitingId}/cloturer`)
    ).send({ prixSeance: 2000 });

    assert.equal(r.status, 200);
    assert.equal(r.body.dejaClose, true);

    const apres = await auth(request(app).get(`/api/patients/${pat.id}`));
    assert.equal(apres.body.prix, 2000);
    assert.equal(apres.body.seancesEffectuees, 1);
  });

  it('les seances s accumulent visite apres visite', async () => {
    const deux = await auth(request(app).post('/api/waiting')).send({
      patientId: pat.id,
    });
    await auth(request(app).post(`/api/waiting/${deux.body.id}/cloturer`)).send({
      // Un controle ne coute pas le prix d une premiere consultation : le
      // montant vient de la requete, pas du tarif enregistre.
      prixSeance: 1200,
    });

    const apres = await auth(request(app).get(`/api/patients/${pat.id}`));
    assert.equal(apres.body.prix, 3200);
    assert.equal(apres.body.seancesEffectuees, 2);
  });

  it('une cloture sans prix ne touche pas au total', async () => {
    // Une seance offerte, ou un forfait deja regle : rien a facturer.
    const trois = await auth(request(app).post('/api/waiting')).send({
      patientId: pat.id,
    });
    await auth(
      request(app).post(`/api/waiting/${trois.body.id}/cloturer`)
    ).send({});

    const apres = await auth(request(app).get(`/api/patients/${pat.id}`));
    assert.equal(apres.body.prix, 3200);
    assert.equal(apres.body.seancesEffectuees, 3);
  });

  it('un montant negatif est ignore', async () => {
    const quatre = await auth(request(app).post('/api/waiting')).send({
      patientId: pat.id,
    });
    await auth(
      request(app).post(`/api/waiting/${quatre.body.id}/cloturer`)
    ).send({ prixSeance: -500 });

    const apres = await auth(request(app).get(`/api/patients/${pat.id}`));
    assert.equal(apres.body.prix, 3200);
  });

  it('le reste a payer suit les versements', async () => {
    // C'est le calcul que le patient entend a la caisse.
    await auth(request(app).post('/api/versements')).send({
      patientId: pat.id,
      montant: 1200,
    });
    const p = await auth(request(app).get(`/api/patients/${pat.id}`));
    assert.equal(p.body.prix - p.body.totalVersements, 2000);
  });
});
