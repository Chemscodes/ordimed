'use strict';

const bcrypt = require('bcryptjs');

const { Profile } = require('../models');
const { scope, resoudreProfil } = require('../middleware/auth');
const { diffuser } = require('../realtime');
const c = require('../lib/coerce');

/**
 * Les profils du cabinet.
 *
 * Le sélecteur de profil les liste tous ; il ne doit jamais recevoir le
 * PIN. `pinHash` n'est pas dans `toJSON` par construction — il est retiré
 * ici explicitement pour que l'oubli d'un `select` ne l'expose pas.
 */
const sansSecret = (p) => {
  const j = p.toJSON();
  delete j.pinHash;
  return j;
};

exports.lister = async (req, res) => {
  const profils = await Profile.find(scope(req)).sort({ createdAt: 1 });
  return res.json(profils.map(sansSecret));
};

exports.creer = async (req, res) => {
  const role = c.asText(req.body.role);
  if (!['medecin', 'assistant'].includes(role)) {
    // Le médecin principal est créé à l'inscription et il n'y en a qu'un.
    return res.status(400).json({ error: 'Rôle invalide' });
  }

  const pin = c.asText(req.body.pin).trim();
  if (!/^\d{4,6}$/.test(pin)) {
    return res.status(400).json({ error: 'Le PIN doit faire 4 à 6 chiffres' });
  }

  const profil = await Profile.create({
    parentUid: req.parentUid,
    name: c.asText(req.body.name).trim(),
    role,
    pinHash: await bcrypt.hash(pin, 10),
    createdAt: new Date(),
  });

  diffuser(req.parentUid, 'comptes', 'creation', { id: String(profil._id) });
  return res.status(201).json(sansSecret(profil));
};

exports.lire = async (req, res) => {
  const profil = await resoudreProfil(req.parentUid, req.params.id);
  if (!profil) return res.status(404).json({ error: 'Profil introuvable' });
  return res.json(sansSecret(profil));
};

exports.modifier = async (req, res) => {
  const profil = await resoudreProfil(req.parentUid, req.params.id);
  if (!profil) return res.status(404).json({ error: 'Profil introuvable' });

  const maj = c.sansIndefinis({
    name: req.body.name !== undefined ? c.asText(req.body.name).trim() : undefined,
    wilaya: req.body.wilaya !== undefined ? c.asText(req.body.wilaya) : undefined,
    address: req.body.address !== undefined ? c.asText(req.body.address) : undefined,
    tel: req.body.tel !== undefined ? c.asText(req.body.tel) : undefined,
    whatsappTemplate:
      req.body.whatsappTemplate !== undefined
        ? c.asText(req.body.whatsappTemplate)
        : undefined,
  });
  if (req.body.whatsappTemplate !== undefined) {
    maj.whatsappTemplateUpdatedAt = new Date();
  }
  // Le PIN ne se modifie que par cette route, jamais par un `set` général.
  if (req.body.pin) {
    const pin = c.asText(req.body.pin).trim();
    if (!/^\d{4,6}$/.test(pin)) {
      return res.status(400).json({ error: 'Le PIN doit faire 4 à 6 chiffres' });
    }
    maj.pinHash = await bcrypt.hash(pin, 10);
  }

  Object.assign(profil, maj);
  await profil.save();

  diffuser(req.parentUid, 'comptes', 'maj', { id: String(profil._id) });
  return res.json(sansSecret(profil));
};

exports.supprimer = async (req, res) => {
  const profil = await resoudreProfil(req.parentUid, req.params.id);
  if (!profil) return res.status(404).json({ error: 'Profil introuvable' });
  if (profil.role === 'medecin_principal') {
    // Sans lui, plus personne ne peut entrer dans le cabinet.
    return res.status(400).json({ error: 'Le médecin principal ne peut pas être supprimé' });
  }

  await Profile.deleteOne({ _id: profil._id });
  diffuser(req.parentUid, 'comptes', 'suppression', { id: String(profil._id) });
  return res.json({ ok: true });
};
