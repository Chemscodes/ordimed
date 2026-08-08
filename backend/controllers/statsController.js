'use strict';

const { DailyStat, Versement, Purchase } = require('../models');
const { scope } = require('../middleware/auth');
const c = require('../lib/coerce');

/**
 * Les statistiques.
 *
 * `daily_stats` reste un document agrégé mis à jour par incréments, comme
 * dans Firestore : le graphique lit une poignée de documents au lieu de
 * parcourir tous les versements du cabinet.
 */
exports.journalier = async (req, res) => {
  const filtre = scope(req);

  if (req.query.depuis || req.query.jusqua) {
    // Les clés sont au format `YYYY-MM-DD`, donc comparables comme des
    // chaînes : le tri lexicographique y est le tri chronologique.
    filtre.dayKey = c.sansIndefinis({
      $gte: req.query.depuis || undefined,
      $lte: req.query.jusqua || undefined,
    });
  }

  const stats = await DailyStat.find(filtre).sort({ dayKey: -1 }).limit(400);
  return res.json(stats.map((s) => s.toJSON()));
};

/**
 * Recalcule les agrégats depuis les écritures réelles.
 *
 * Un compteur incrémenté peut dériver : une transaction interrompue, un
 * import de sauvegarde, une suppression manuelle. Sans moyen de le
 * reconstruire, l'écart resterait pour toujours et personne ne saurait
 * lequel des deux chiffres croire.
 */
exports.recalculer = async (req, res) => {
  const [versements, achats] = await Promise.all([
    Versement.aggregate([
      { $match: { parentUid: req.parentUid } },
      {
        $group: {
          _id: '$dayKey',
          total: { $sum: '$montant' },
          count: { $sum: 1 },
        },
      },
    ]),
    Purchase.aggregate([
      { $match: { parentUid: req.parentUid } },
      {
        $group: {
          _id: '$dayKey',
          total: { $sum: '$montant' },
          count: { $sum: 1 },
        },
      },
    ]),
  ]);

  const parJour = new Map();
  for (const v of versements) {
    parJour.set(v._id, { versementsTotal: v.total, versementsCount: v.count });
  }
  for (const a of achats) {
    const e = parJour.get(a._id) || {};
    e.achatsTotal = a.total;
    e.achatsCount = a.count;
    parJour.set(a._id, e);
  }

  const operations = [...parJour.entries()].map(([dayKey, valeurs]) => ({
    updateOne: {
      filter: { parentUid: req.parentUid, dayKey },
      update: {
        $set: {
          // Remis à zéro avant application : un jour dont tous les
          // versements ont été supprimés doit retomber à zéro, pas garder
          // son ancien total.
          versementsTotal: 0,
          versementsCount: 0,
          achatsTotal: 0,
          achatsCount: 0,
          ...valeurs,
          updatedAt: new Date(),
        },
      },
      upsert: true,
    },
  }));

  if (operations.length) await DailyStat.bulkWrite(operations);
  return res.json({ ok: true, jours: operations.length });
};
