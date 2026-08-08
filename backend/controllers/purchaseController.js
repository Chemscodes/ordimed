'use strict';

const mongoose = require('mongoose');

const { Purchase, DailyStat } = require('../models');
const { scope, resoudreProfil } = require('../middleware/auth');
const { diffuser } = require('../realtime');
const c = require('../lib/coerce');

exports.lister = async (req, res) => {
  const filtre = scope(req);
  if (req.query.dayKey) filtre.dayKey = req.query.dayKey;
  const achats = await Purchase.find(filtre).sort({ createdAt: -1 }).limit(1000);
  return res.json(achats.map((a) => a.toJSON()));
};

exports.creer = async (req, res) => {
  const montant = c.asNumberOrNull(req.body.montant);
  if (montant === null || montant <= 0) {
    return res.status(400).json({ error: 'Montant invalide' });
  }

  const profil = req.body.profileId
    ? await resoudreProfil(req.parentUid, req.body.profileId)
    : null;

  const maintenant = new Date();
  const dayKey = c.dayKeyOf(maintenant);

  const session = await mongoose.startSession();
  let achat;
  try {
    await session.withTransaction(async () => {
      [achat] = await Purchase.create(
        [
          {
            parentUid: req.parentUid,
            profileId: profil ? profil._id : null,
            produit: c.asText(req.body.produit),
            fournisseur: c.asText(req.body.fournisseur),
            montant,
            dayKey,
            createdAt: maintenant,
          },
        ],
        { session }
      );

      await DailyStat.updateOne(
        { parentUid: req.parentUid, dayKey },
        {
          $inc: { achatsTotal: montant, achatsCount: 1 },
          $set: { date: maintenant, updatedAt: maintenant },
        },
        { upsert: true, session }
      );
    });
  } finally {
    await session.endSession();
  }

  diffuser(req.parentUid, 'purchases', 'creation', { id: String(achat._id) });
  return res.status(201).json(achat.toJSON());
};

exports.supprimer = async (req, res) => {
  const achat = await Purchase.findOneAndDelete(scope(req, { _id: req.params.id }));
  if (!achat) return res.status(404).json({ error: 'Achat introuvable' });

  diffuser(req.parentUid, 'purchases', 'suppression', { id: String(achat._id) });
  return res.json({ ok: true });
};
