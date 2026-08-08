'use strict';

const mongoose = require('mongoose');

const { Versement, Patient, DailyStat } = require('../models');
const { scope, resoudreProfil } = require('../middleware/auth');
const { diffuser } = require('../realtime');
const c = require('../lib/coerce');

/** Le cache borné du document patient. Voir lib/core/versements.dart. */
const MAX_CACHE = 50;

exports.lister = async (req, res) => {
  const filtre = scope(req);
  if (req.query.patientId) filtre.patientId = req.query.patientId;
  if (req.query.dayKey) filtre.dayKey = req.query.dayKey;

  const liste = await Versement.find(filtre).sort({ createdAt: -1 }).limit(1000);
  return res.json(liste.map((v) => v.toJSON()));
};

/**
 * Encaisse un versement.
 *
 * Trois écritures indissociables : le versement lui-même, le total et le
 * cache sur le dossier, la statistique du jour. Une seule qui échoue et les
 * chiffres du cabinet ne tombent plus juste.
 *
 * Deux améliorations que la bascule permet gratuitement :
 *
 * - Le total passe par `$inc` au lieu d'être lu puis réécrit. Deux postes
 *   qui encaissent en même temps ne s'écrasent plus — c'était une faiblesse
 *   réelle de la version Firestore.
 * - Le cache est borné par `$slice` à l'écriture, donc côté serveur. Le
 *   client ne peut plus le faire grossir sans limite.
 */
exports.creer = async (req, res) => {
  const montant = c.asNumberOrNull(req.body.montant);
  if (montant === null || montant <= 0) {
    return res.status(400).json({ error: 'Montant invalide' });
  }

  const patient = await Patient.findOne(scope(req, { _id: req.body.patientId }));
  if (!patient) return res.status(404).json({ error: 'Patient introuvable' });

  const auteur = req.body.auteurProfileId
    ? await resoudreProfil(req.parentUid, req.body.auteurProfileId)
    : null;

  const maintenant = new Date();
  const dayKey = c.dayKeyOf(maintenant);

  const session = await mongoose.startSession();
  let versement;
  try {
    await session.withTransaction(async () => {
      [versement] = await Versement.create(
        [
          {
            parentUid: req.parentUid,
            patientId: patient._id,
            doctorId: patient.doctorId,
            auteurProfileId: auteur ? auteur._id : null,
            montant,
            dayKey,
            createdAt: maintenant,
          },
        ],
        { session }
      );

      await Patient.updateOne(
        { _id: patient._id },
        {
          $inc: { totalVersements: montant },
          $push: {
            versements: {
              $each: [
                {
                  montant,
                  createdAt: maintenant,
                  dayKey,
                  auteurProfileId: auteur ? String(auteur._id) : '',
                },
              ],
              $position: 0,
              $slice: MAX_CACHE,
            },
          },
        },
        { session }
      );

      await DailyStat.updateOne(
        { parentUid: req.parentUid, dayKey },
        {
          $inc: { versementsTotal: montant, versementsCount: 1 },
          $set: { date: maintenant, updatedAt: maintenant },
        },
        { upsert: true, session }
      );
    });
  } finally {
    await session.endSession();
  }

  diffuser(req.parentUid, 'versements', 'creation', {
    id: String(versement._id),
    patientId: String(patient._id),
  });
  diffuser(req.parentUid, 'patients', 'maj', { id: String(patient._id) });

  return res.status(201).json(versement.toJSON());
};
