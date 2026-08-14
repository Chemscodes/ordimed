'use strict';

const mongoose = require('mongoose');

const { RendezVous, Patient, Waiting, ETAPES } = require('../models');
const { scope, resoudreProfil } = require('../middleware/auth');
const { diffuser } = require('../realtime');
const c = require('../lib/coerce');

/**
 * Les rendez-vous et la détection de conflit.
 *
 * Le contrôle des créneaux vivait côté Flutter (`lib/core/creneaux.dart`) :
 * l'écran n'affichait comme cliquables que les créneaux libres. C'était
 * suffisant tant que le client était le seul chemin vers la base.
 *
 * Avec une API, ça ne l'est plus : deux postes peuvent poser le même
 * créneau à la même seconde, et un client modifié peut poster n'importe
 * quoi. Le contrôle est donc **refait ici**, côté serveur. Celui de Flutter
 * reste — il évite de proposer un créneau qui sera refusé.
 */

/** Les étapes qui n'occupent plus le créneau. */
const LIBERENT = new Set(['absent', 'annule']);

/**
 * Cherche le rendez-vous qui empêche de poser un créneau.
 *
 * Mêmes règles que `conflitPour` côté Flutter, et pour les mêmes raisons :
 * les bornes ne comptent pas (10h00-10h20 et 10h20-10h40 se suivent), un
 * rendez-vous annulé ou manqué libère sa place, et un rendez-vous déplacé
 * ne se détecte pas lui-même.
 */
async function chercherConflit({ parentUid, doctorId, debut, duree, ignorer }) {
  const fin = new Date(debut.getTime() + duree * 60000);

  const candidats = await RendezVous.find({
    parentUid,
    doctorId,
    etape: { $nin: [...LIBERENT] },
    // Fenêtre large : on ne peut pas comparer les fins en base, `duree`
    // variant d'un rendez-vous à l'autre. Une journée de marge suffit et
    // reste peu coûteuse grâce à l'index {doctorId, datetime}.
    datetime: {
      $gt: new Date(debut.getTime() - 24 * 3600 * 1000),
      $lt: fin,
    },
  });

  for (const rdv of candidats) {
    if (ignorer && String(rdv._id) === String(ignorer)) continue;
    const rDebut = rdv.datetime;
    const rFin = new Date(rDebut.getTime() + (rdv.duree || 20) * 60000);
    if (debut < rFin && rDebut < fin) return rdv;
  }
  return null;
}

exports.lister = async (req, res) => {
  const filtre = scope(req);

  if (req.query.profileId) {
    const profil = await resoudreProfil(req.parentUid, req.query.profileId);
    if (!profil) return res.status(404).json({ error: 'Profil introuvable' });
    if (profil.role !== 'medecin_principal') {
      filtre.$or = [{ doctorId: profil._id }, { assistantId: profil._id }];
    }
  }

  // La journée d'un médecin : la requête du sélecteur de créneaux.
  const jour = c.asDateOrNull(req.query.jour);
  if (jour) {
    const debut = new Date(jour);
    debut.setHours(0, 0, 0, 0);
    const fin = new Date(debut.getTime() + 24 * 3600 * 1000);
    filtre.datetime = { $gte: debut, $lt: fin };
  } else if (req.query.depuis) {
    filtre.datetime = { $gte: c.asDateOrNull(req.query.depuis) };
  }

  const rdvs = await RendezVous.find(filtre)
    .sort({ datetime: 1 })
    .limit(Math.min(Number(req.query.limit) || 200, 1000));

  return res.json(rdvs.map((r) => r.toJSON()));
};

exports.creer = async (req, res) => {
  const doctor = await resoudreProfil(req.parentUid, req.body.doctorId);
  if (!doctor) return res.status(400).json({ error: 'Médecin introuvable' });

  const patient = await Patient.findOne(scope(req, { _id: req.body.patientId }));
  if (!patient) return res.status(404).json({ error: 'Patient introuvable' });

  const debut = c.asDateOrNull(req.body.datetime);
  if (!debut) return res.status(400).json({ error: 'Date du rendez-vous requise' });

  const duree = c.asInt(req.body.duree, 20);

  const conflit = await chercherConflit({
    parentUid: req.parentUid,
    doctorId: doctor._id,
    debut,
    duree,
  });
  if (conflit) {
    // 409 et non 400 : le client n'a rien envoyé de mal, la place vient
    // d'être prise. L'app peut proposer de rouvrir le sélecteur.
    return res.status(409).json({
      error: 'Ce créneau vient d’être pris',
      conflit: {
        id: String(conflit._id),
        patient: `${conflit.patientNom} ${conflit.patientPrenom}`.trim(),
        datetime: conflit.datetime,
      },
    });
  }

  const assistant = req.body.assistantId
    ? await resoudreProfil(req.parentUid, req.body.assistantId)
    : null;

  const rdv = await RendezVous.create({
    parentUid: req.parentUid,
    patientId: patient._id,
    doctorId: doctor._id,
    assistantId: assistant ? assistant._id : null,
    patientNom: patient.nom,
    patientPrenom: patient.prenom,
    patientTel: patient.tel,
    doctorName: doctor.name,
    motif: c.asText(req.body.motif) || patient.motif,
    datetime: debut,
    duree,
    etape: 'planifie',
    reminderTemplate: c.asText(req.body.reminderTemplate),
    createdAt: new Date(),
  });

  diffuser(req.parentUid, 'rendezvous', 'creation', { id: String(rdv._id) });
  return res.status(201).json(rdv.toJSON());
};

/** Déplacement : mêmes contrôles, en s'ignorant soi-même. */
exports.modifier = async (req, res) => {
  const rdv = await RendezVous.findOne(scope(req, { _id: req.params.id }));
  if (!rdv) return res.status(404).json({ error: 'Rendez-vous introuvable' });

  const maj = { updatedAt: new Date() };

  if (req.body.datetime !== undefined || req.body.duree !== undefined) {
    const debut = c.asDateOrNull(req.body.datetime) || rdv.datetime;
    const duree = c.asInt(req.body.duree, rdv.duree || 20);

    const conflit = await chercherConflit({
      parentUid: req.parentUid,
      doctorId: rdv.doctorId,
      debut,
      duree,
      ignorer: rdv._id,
    });
    if (conflit) {
      return res.status(409).json({
        error: 'Ce créneau est occupé',
        conflit: {
          id: String(conflit._id),
          patient: `${conflit.patientNom} ${conflit.patientPrenom}`.trim(),
        },
      });
    }
    maj.datetime = debut;
    maj.duree = duree;
  }

  if (req.body.motif !== undefined) maj.motif = c.asText(req.body.motif);
  // Le numero est mis en cache sur le rendez-vous : le rappel WhatsApp
  // partait sinon chercher le dossier a chaque envoi.
  if (req.body.patientTel !== undefined) {
    maj.patientTel = c.asText(req.body.patientTel);
  }
  // `true` demande un horodatage serveur ; une date explicite est acceptee
  // pour rejouer un envoi.
  if (req.body.reminderSentAt !== undefined) {
    maj.reminderSentAt =
      req.body.reminderSentAt === true
        ? new Date()
        : c.asDateOrNull(req.body.reminderSentAt);
  }

  const majDoc = await RendezVous.findByIdAndUpdate(rdv._id, { $set: maj }, { new: true });
  diffuser(req.parentUid, 'rendezvous', 'maj', { id: String(rdv._id) });
  return res.json(majDoc.toJSON());
};

exports.changerEtape = async (req, res) => {
  const etape = c.asText(req.body.etape);
  if (!ETAPES.includes(etape)) {
    return res.status(400).json({ error: 'Étape inconnue' });
  }

  const maj = {
    etape,
    [`etapesAt.${etape}`]: new Date(),
    updatedAt: new Date(),
  };
  if (req.body.motifAnnulation) {
    maj.motifAnnulation = c.asText(req.body.motifAnnulation);
  }

  const rdv = await RendezVous.findOneAndUpdate(
    scope(req, { _id: req.params.id }),
    { $set: maj },
    { new: true }
  );
  if (!rdv) return res.status(404).json({ error: 'Rendez-vous introuvable' });

  diffuser(req.parentUid, 'rendezvous', 'maj', { id: String(rdv._id) });
  return res.json(rdv.toJSON());
};

/**
 * Le patient se présente : le rendez-vous entre en salle d'attente.
 *
 * C'était le trou du parcours côté Flutter — l'assistant devait ressaisir
 * le patient dans la file alors que le rendez-vous portait déjà tout. Les
 * deux écritures sont ici indissociables.
 */
exports.marquerArrive = async (req, res) => {
  const rdv = await RendezVous.findOne(scope(req, { _id: req.params.id }));
  if (!rdv) return res.status(404).json({ error: 'Rendez-vous introuvable' });

  const dejaLa = await Waiting.exists({
    parentUid: req.parentUid,
    patientId: rdv.patientId,
    closedAt: null,
  });
  if (dejaLa) {
    // Le rendez-vous n'est pas marqué : rien ne s'est passé.
    return res.status(409).json({ error: 'Ce patient est déjà dans la file' });
  }

  const patient = await Patient.findOne(
    scope(req, { _id: rdv.patientId })
  );

  const session = await mongoose.startSession();
  let entree;
  try {
    await session.withTransaction(async () => {
      [entree] = await Waiting.create(
        [
          {
            parentUid: req.parentUid,
            patientId: rdv.patientId,
            doctorId: rdv.doctorId,
            assistantId: rdv.assistantId,
            rdvId: rdv._id,
            patientNom: rdv.patientNom,
            patientPrenom: rdv.patientPrenom,
            doctorName: rdv.doctorName,
            motif: rdv.motif,
            nombreSeances: patient ? patient.nombreSeances : null,
            seancesEffectuees: patient ? patient.seancesEffectuees : null,
            etape: 'arrive',
            status: 'waiting',
            createdAt: new Date(),
          },
        ],
        { session }
      );

      await RendezVous.updateOne(
        { _id: rdv._id },
        { $set: { etape: 'arrive', 'etapesAt.arrive': new Date() } },
        { session }
      );
    });
  } finally {
    await session.endSession();
  }

  diffuser(req.parentUid, 'salle_attente', 'creation', { id: String(entree._id) });
  diffuser(req.parentUid, 'rendezvous', 'maj', { id: String(rdv._id) });

  return res.status(201).json(entree.toJSON());
};

exports.supprimer = async (req, res) => {
  const rdv = await RendezVous.findOneAndDelete(scope(req, { _id: req.params.id }));
  if (!rdv) return res.status(404).json({ error: 'Rendez-vous introuvable' });

  diffuser(req.parentUid, 'rendezvous', 'suppression', { id: String(rdv._id) });
  return res.json({ ok: true });
};
