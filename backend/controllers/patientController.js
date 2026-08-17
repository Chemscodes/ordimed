'use strict';

const mongoose = require('mongoose');

const { Patient, Form, Versement, Waiting, RendezVous } = require('../models');
const { scope, resoudreProfil } = require('../middleware/auth');
const { diffuser } = require('../realtime');
const c = require('../lib/coerce');

/**
 * Les dossiers patients.
 *
 * Firestore écrivait chaque patient **deux fois** : sous le profil du
 * médecin et sous celui de l'assistant, parce qu'il ne sait pas joindre.
 * Ici un seul document, avec `doctorId` et `assistantId` indexés — la même
 * liste se retrouve par requête, sans que deux copies puissent diverger.
 */

/** Normalise ce que l'app envoie. Voir lib/coerce.js pour le pourquoi. */
function corpsVersDocument(body) {
  const motifs = Array.isArray(body.motifs)
    ? body.motifs.map(c.asText).filter(Boolean)
    : undefined;

  return c.sansIndefinis({
    nom: body.nom !== undefined ? c.asText(body.nom).trim() : undefined,
    prenom: body.prenom !== undefined ? c.asText(body.prenom).trim() : undefined,
    // Chaîne sur les dossiers antérieurs, entier depuis peu.
    age: body.age !== undefined ? c.asIntOrNull(body.age) : undefined,
    tel: body.tel !== undefined ? c.asText(body.tel) : undefined,
    email: body.email !== undefined ? c.asText(body.email) : undefined,
    origine: body.origine !== undefined ? c.asText(body.origine) : undefined,

    motifs,
    // L'app écrit les deux : plusieurs vues ne lisent que `motif`.
    motif:
      body.motif !== undefined
        ? c.asText(body.motif)
        : motifs
          ? motifs.join(', ')
          : undefined,

    assistantName:
      body.assistantName !== undefined ? c.asText(body.assistantName) : undefined,
    assignedMedecinName:
      body.assignedMedecinName !== undefined
        ? c.asText(body.assignedMedecinName)
        : undefined,
    createdByAssistantProfileId:
      body.createdByAssistantProfileId !== undefined
        ? c.asText(body.createdByAssistantProfileId)
        : undefined,

    poids_actuel:
      body.poids_actuel !== undefined ? c.asNumberOrNull(body.poids_actuel) : undefined,
    taille: body.taille !== undefined ? c.asNumberOrNull(body.taille) : undefined,
    // Chaîne : l'app l'affiche formaté à la virgule.
    imc: body.imc !== undefined ? c.asText(body.imc) : undefined,
    derniereConsultation:
      body.derniereConsultation !== undefined
        ? c.asDateOrNull(body.derniereConsultation)
        : undefined,

    nombreSeances:
      body.nombreSeances !== undefined ? c.asIntOrNull(body.nombreSeances) : undefined,
    seancesEffectuees:
      body.seancesEffectuees !== undefined ? c.asInt(body.seancesEffectuees) : undefined,

    prix: body.prix !== undefined ? c.asNumberOrNull(body.prix) : undefined,
    // Le tarif de seance : le medecin comme l'assistant le fixent.
    prixSeance:
      body.prixSeance !== undefined
        ? c.asNumberOrNull(body.prixSeance)
        : undefined,
  });
}

/**
 * Liste des patients d'un profil.
 *
 * `profileId` reproduit ce que voyait chaque profil dans Firestore : le
 * médecin voit ses patients, l'assistant les siens, le principal tout le
 * cabinet.
 */
exports.lister = async (req, res) => {
  const filtre = scope(req);

  if (req.query.profileId) {
    const profil = await resoudreProfil(req.parentUid, req.query.profileId);
    if (!profil) return res.status(404).json({ error: 'Profil introuvable' });

    if (profil.role !== 'medecin_principal') {
      filtre.$or = [{ doctorId: profil._id }, { assistantId: profil._id }];
    }
  }

  /**
   * La suppression douce se filtre **explicitement**, jamais par index
   * partiel : les dossiers antérieurs à son introduction n'ont pas du tout
   * le champ, et `{deletedAt: null}` seul les exclurait tous.
   */
  if (req.query.inclureSupprimes !== '1') {
    filtre.deletedAt = null;
  }

  const patients = await Patient.find(filtre)
    .sort({ createdAt: -1 })
    .limit(Math.min(Number(req.query.limit) || 500, 2000));

  return res.json(patients.map((p) => p.toJSON()));
};

exports.lire = async (req, res) => {
  const patient = await Patient.findOne(scope(req, { _id: req.params.id }));
  if (!patient) return res.status(404).json({ error: 'Patient introuvable' });
  return res.json(patient.toJSON());
};

/**
 * Création d'un dossier.
 *
 * Reprend `add_patient_form.dart` : le dossier, le formulaire initial et
 * l'entrée en salle d'attente partaient ensemble. Un échec partiel laissait
 * le patient visible d'un côté et absent de l'autre — d'où la transaction.
 */
exports.creer = async (req, res) => {
  const doctor = await resoudreProfil(req.parentUid, req.body.doctorId);
  if (!doctor) return res.status(400).json({ error: 'Médecin introuvable' });

  const assistant = req.body.assistantId
    ? await resoudreProfil(req.parentUid, req.body.assistantId)
    : null;

  const donnees = {
    ...corpsVersDocument(req.body),
    parentUid: req.parentUid,
    doctorId: doctor._id,
    assistantId: assistant ? assistant._id : null,
    createdAt: new Date(),
  };

  if (!donnees.nom) return res.status(400).json({ error: 'Le nom est obligatoire' });

  const session = await mongoose.startSession();
  let patient;
  try {
    await session.withTransaction(async () => {
      [patient] = await Patient.create([donnees], { session });

      // Le formulaire initial, visible du médecin comme de l'assistant.
      await Form.create(
        [
          {
            parentUid: req.parentUid,
            patientId: patient._id,
            auteurProfileId: assistant ? assistant._id : doctor._id,
            type: 'Dossier initial',
            contenu:
              c.asText(req.body.formulaireInitial).trim() ||
              "Dossier initial créé par l'assistant",
            createdAt: new Date(),
          },
        ],
        { session }
      );

      if (req.body.ajouterEnSalle !== false) {
        await Waiting.create(
          [
            {
              parentUid: req.parentUid,
              patientId: patient._id,
              doctorId: doctor._id,
              assistantId: assistant ? assistant._id : null,
              patientNom: patient.nom,
              patientPrenom: patient.prenom,
              doctorName: patient.assignedMedecinName,
              assistantName: patient.assistantName,
              motif: patient.motif,
              etape: 'arrive',
              status: 'waiting',
              createdAt: new Date(),
            },
          ],
          { session }
        );
      }
    });
  } finally {
    await session.endSession();
  }

  diffuser(req.parentUid, 'patients', 'creation', { id: String(patient._id) });
  if (req.body.ajouterEnSalle !== false) {
    diffuser(req.parentUid, 'salle_attente', 'creation', {
      patientId: String(patient._id),
    });
  }

  return res.status(201).json(patient.toJSON());
};

exports.modifier = async (req, res) => {
  const maj = corpsVersDocument(req.body);

  // Réaffectation éventuelle.
  if (req.body.doctorId) {
    const d = await resoudreProfil(req.parentUid, req.body.doctorId);
    if (!d) return res.status(400).json({ error: 'Médecin introuvable' });
    maj.doctorId = d._id;
    if (d.name) maj.assignedMedecinName = d.name;
  }

  const patient = await Patient.findOneAndUpdate(
    scope(req, { _id: req.params.id }),
    { $set: maj },
    { new: true, runValidators: true }
  );
  if (!patient) return res.status(404).json({ error: 'Patient introuvable' });

  diffuser(req.parentUid, 'patients', 'maj', { id: String(patient._id) });
  return res.json(patient.toJSON());
};

/**
 * Suppression douce.
 *
 * Le dossier n'est pas effacé : ses versements et son historique restent
 * intacts et restaurables. C'est la reprise de `services/soft_delete.dart`.
 */
exports.supprimer = async (req, res) => {
  const session = await mongoose.startSession();
  let patient;

  try {
    await session.withTransaction(async () => {
      patient = await Patient.findOneAndUpdate(
        scope(req, { _id: req.params.id }),
        { $set: { deletedAt: new Date() } },
        { new: true, session }
      );
      if (!patient) return;

      /**
       * Le retrait des elements operationnels.
       *
       * L'app le faisait apres coup, en tache de fond, et sans transaction :
       * un patient supprime pouvait rester dans la file d'attente du
       * medecin, qui l'appelait pour rien. C'est le meme geste, il part
       * avec la suppression.
       *
       * Les rendez-vous a venir sont annules ; ceux deja passes gardent
       * leur etape, ils font partie de l'historique.
       */
      await Waiting.updateMany(
        { parentUid: req.parentUid, patientId: patient._id, closedAt: null },
        {
          $set: {
            etape: 'annule',
            status: 'cancelled',
            closedAt: new Date(),
          },
        },
        { session }
      );

      await RendezVous.updateMany(
        {
          parentUid: req.parentUid,
          patientId: patient._id,
          datetime: { $gte: new Date() },
          etape: { $nin: ['honore', 'absent', 'annule'] },
        },
        {
          $set: {
            etape: 'annule',
            motifAnnulation: 'Dossier supprime',
            'etapesAt.annule': new Date(),
          },
        },
        { session }
      );
    });
  } finally {
    await session.endSession();
  }

  if (!patient) return res.status(404).json({ error: 'Patient introuvable' });

  diffuser(req.parentUid, 'patients', 'suppression', { id: String(patient._id) });
  diffuser(req.parentUid, 'salle_attente', 'maj', {});
  diffuser(req.parentUid, 'rendezvous', 'maj', {});
  return res.json(patient.toJSON());
};

/**
 * Annule une suppression.
 *
 * Les entrees de salle d'attente restent closes : un patient restaure n'a
 * pas a reapparaitre dans la file d'une journee deja passee. Ses rendez-vous
 * a venir, eux, redeviennent planifies.
 */
exports.restaurer = async (req, res) => {
  const patient = await Patient.findOneAndUpdate(
    scope(req, { _id: req.params.id }),
    { $set: { deletedAt: null } },
    { new: true }
  );
  if (!patient) return res.status(404).json({ error: 'Patient introuvable' });

  await RendezVous.updateMany(
    {
      parentUid: req.parentUid,
      patientId: patient._id,
      motifAnnulation: 'Dossier supprime',
      datetime: { $gte: new Date() },
    },
    { $set: { etape: 'planifie', motifAnnulation: '' } }
  );

  diffuser(req.parentUid, 'patients', 'maj', { id: String(patient._id) });
  diffuser(req.parentUid, 'rendezvous', 'maj', {});
  return res.json(patient.toJSON());
};

/**
 * Tout ce qui pend sous un dossier, en une requête.
 *
 * Le dossier patient affichait documents et versements côte à côte : les
 * demander séparément multiplierait les allers-retours sur une page déjà
 * lourde.
 */
exports.detail = async (req, res) => {
  const filtre = scope(req, { _id: req.params.id });
  const patient = await Patient.findOne(filtre);
  if (!patient) return res.status(404).json({ error: 'Patient introuvable' });

  const [forms, versements] = await Promise.all([
    Form.find({ parentUid: req.parentUid, patientId: patient._id }).sort({
      createdAt: -1,
    }),
    Versement.find({ parentUid: req.parentUid, patientId: patient._id }).sort({
      createdAt: -1,
    }),
  ]);

  return res.json({
    patient: patient.toJSON(),
    forms: forms.map((f) => f.toJSON()),
    versements: versements.map((v) => v.toJSON()),
  });
};
