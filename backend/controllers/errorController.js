'use strict';

const { ErrorLog } = require('../models');
const c = require('../lib/coerce');

/**
 * Journal d'erreurs.
 *
 * Était à la racine de Firestore, hors cabinet : une erreur peut survenir
 * avant toute connexion. La route reste donc accessible sans jeton, mais
 * rattache le cabinet quand il y en a un.
 */
exports.signaler = async (req, res) => {
  await ErrorLog.create({
    parentUid: req.parentUid || null,
    // Tronqué : une trace de pile peut faire des dizaines de kilo-octets,
    // et un plantage en boucle remplirait la base plus vite qu'on ne la
    // lirait.
    message: c.asText(req.body.message).slice(0, 2000),
    stack: c.asText(req.body.stack).slice(0, 8000),
    context: c.asText(req.body.context),
    origin: c.asText(req.body.origin),
    platform: c.asText(req.body.platform),
    osVersion: c.asText(req.body.osVersion),
    appVersion: c.asText(req.body.appVersion),
    createdAt: new Date(),
  });

  // 204 : l'app ne doit jamais attendre ni échouer à cause du journal.
  return res.status(204).end();
};

exports.lister = async (req, res) => {
  const logs = await ErrorLog.find({ parentUid: req.parentUid })
    .sort({ createdAt: -1 })
    .limit(200);
  return res.json(logs.map((l) => l.toJSON()));
};
