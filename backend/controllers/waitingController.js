'use strict';

const mongoose = require('mongoose');

const { Waiting, Patient, RendezVous } = require('../models');
const { scope, resoudreProfil } = require('../middleware/auth');
const { diffuser } = require('../realtime');
const c = require('../lib/coerce');

/**
 * La salle d'attente.
 *
 * C'est l'écran le plus partagé du cabinet : l'assistant y place un
 * patient, le médecin le voit apparaître, le consulte, le clôture, et
 * l'assistant voit la file se vider. Firestore poussait chaque changement
 * tout seul ; ici chaque écriture appelle `diffuser`, sinon les deux écrans
 * cessent de se parler.
 *
 * Firestore écrivait chaque entrée **trois fois** (médecin, assistant,
 * médecin principal). Un seul document ici : le principal voit tout le
 * cabinet par requête, sans troisième copie à maintenir.
 */

/** Correspondance entre les deux vocabulaires, conservée telle quelle. */
const STATUS_POUR = {
  arrive: 'waiting',
  en_cours: 'in_consultation',
  honore: 'done',
  annule: 'cancelled',
};

exports.lister = async (req, res) => {
  const filtre = scope(req);

  if (req.query.profileId) {
    const profil = await resoudreProfil(req.parentUid, req.query.profileId);
    if (!profil) return res.status(404).json({ error: 'Profil introuvable' });
    if (profil.role !== 'medecin_principal') {
      filtre.$or = [{ doctorId: profil._id }, { assistantId: profil._id }];
    }
  }

  // Par défaut la file du jour : les entrées ouvertes, plus celles closes
  // aujourd'hui — le tableau de bord affiche « Historique du jour » à côté
  // de la file en cours.
  if (req.query.toutes !== '1') {
    const debut = new Date();
    debut.setHours(0, 0, 0, 0);
    filtre.$and = [{ $or: [{ closedAt: null }, { closedAt: { $gte: debut } }] }];
  }

  const entrees = await Waiting.find(filtre).sort({ createdAt: -1 }).limit(500);
  return res.json(entrees.map((e) => e.toJSON()));
};

/**
 * Place un patient en salle.
 *
 * Renvoie 409 si le patient y est déjà : c'est le garde-fou d'origine
 * (`_hasOpenEntry`). Sans lui, un double-clic crée deux entrées et le
 * patient apparaît en double dans la file du médecin.
 */
exports.ajouter = async (req, res) => {
  const patient = await Patient.findOne(
    scope(req, { _id: req.body.patientId })
  );
  if (!patient) return res.status(404).json({ error: 'Patient introuvable' });

  const dejaLa = await Waiting.exists({
    parentUid: req.parentUid,
    patientId: patient._id,
    closedAt: null,
  });
  if (dejaLa) {
    return res.status(409).json({ error: "Ce patient est déjà dans la file" });
  }

  const entree = await Waiting.create({
    parentUid: req.parentUid,
    patientId: patient._id,
    doctorId: patient.doctorId,
    assistantId: patient.assistantId,
    rdvId: req.body.rdvId || null,
    patientNom: patient.nom,
    patientPrenom: patient.prenom,
    doctorName: patient.assignedMedecinName,
    assistantName: patient.assistantName,
    motif: c.asText(req.body.motif) || patient.motif,
    nombreSeances: patient.nombreSeances,
    seancesEffectuees: patient.seancesEffectuees,
    etape: 'arrive',
    status: 'waiting',
    createdAt: new Date(),
  });

  diffuser(req.parentUid, 'salle_attente', 'creation', {
    id: String(entree._id),
  });
  return res.status(201).json(entree.toJSON());
};

/** Le médecin démarre la consultation. */
exports.demarrer = async (req, res) => {
  const entree = await Waiting.findOneAndUpdate(
    scope(req, { _id: req.params.id }),
    {
      $set: {
        etape: 'en_cours',
        status: 'in_consultation',
        inConsultationAt: new Date(),
        closedAt: null,
      },
    },
    { new: true }
  );
  if (!entree) return res.status(404).json({ error: 'Entrée introuvable' });

  diffuser(req.parentUid, 'salle_attente', 'maj', { id: String(entree._id) });
  return res.json(entree.toJSON());
};

/**
 * Clôture : décompte la séance, sort le patient, marque le rendez-vous
 * honoré.
 *
 * Les trois allaient ensemble dans `consultation_page.dart`. Une clôture
 * qui décompte la séance sans sortir le patient le laisse dans la file du
 * médecin, séance déjà comptée — d'où la transaction.
 */
exports.cloturer = async (req, res) => {
  const session = await mongoose.startSession();
  let entree;

  try {
    await session.withTransaction(async () => {
      entree = await Waiting.findOne(scope(req, { _id: req.params.id })).session(
        session
      );
      if (!entree) return;

      await Waiting.updateOne(
        { _id: entree._id },
        {
          $set: {
            etape: 'honore',
            status: 'done',
            closedAt: new Date(),
          },
        },
        { session }
      );

      if (req.body.decompterSeance !== false) {
        await Patient.updateOne(
          { _id: entree.patientId, parentUid: req.parentUid },
          { $inc: { seancesEffectuees: 1 } },
          { session }
        );
      }

      // Referme le rendez-vous d'où vient la visite. Sans ce retour, un
      // rendez-vous honoré resterait affiché « à venir » indéfiniment.
      if (entree.rdvId) {
        await RendezVous.updateOne(
          { _id: entree.rdvId, parentUid: req.parentUid },
          {
            $set: {
              etape: 'honore',
              'etapesAt.honore': new Date(),
              updatedAt: new Date(),
            },
          },
          { session }
        );
      }
    });
  } finally {
    await session.endSession();
  }

  if (!entree) return res.status(404).json({ error: 'Entrée introuvable' });

  diffuser(req.parentUid, 'salle_attente', 'maj', { id: String(entree._id) });
  diffuser(req.parentUid, 'patients', 'maj', {
    id: String(entree.patientId),
  });
  if (entree.rdvId) {
    diffuser(req.parentUid, 'rendezvous', 'maj', { id: String(entree.rdvId) });
  }

  return res.json({ ok: true });
};

exports.changerEtape = async (req, res) => {
  const etape = c.asText(req.body.etape);
  if (!STATUS_POUR[etape]) {
    return res.status(400).json({ error: 'Étape inconnue' });
  }

  const entree = await Waiting.findOneAndUpdate(
    scope(req, { _id: req.params.id }),
    {
      $set: {
        etape,
        // Les deux vocabulaires restent écrits ensemble : les entrées
        // existantes ne portent que `status`, et cesser de l'écrire
        // rendrait la file en cours illisible au moment de la bascule.
        status: STATUS_POUR[etape],
        ...(etape === 'honore' || etape === 'annule'
          ? { closedAt: new Date() }
          : {}),
      },
    },
    { new: true }
  );
  if (!entree) return res.status(404).json({ error: 'Entrée introuvable' });

  diffuser(req.parentUid, 'salle_attente', 'maj', { id: String(entree._id) });
  return res.json(entree.toJSON());
};
