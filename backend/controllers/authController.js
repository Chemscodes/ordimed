'use strict';

const bcrypt = require('bcryptjs');

const { Cabinet, Profile } = require('../models');
const { signerJeton, resoudreProfil } = require('../middleware/auth');

/**
 * Authentification.
 *
 * Firebase Auth ne faisait que quatre choses dans ce projet :
 * `createUserWithEmailAndPassword`, `signInWithEmailAndPassword`,
 * `signOut`, et lire `currentUser.uid`. La surface à reprendre est donc
 * petite — mais elle porte maintenant le mot de passe, ce que Firebase
 * faisait à notre place.
 */

const COUT_HASH = 10;

/**
 * Inscription : crée le cabinet et son médecin principal.
 *
 * Les deux allaient ensemble dans `signup_page.dart` — un cabinet sans
 * profil est inutilisable, on ne peut même pas s'y connecter. Ils sont donc
 * créés dans la même requête, et le profil est supprimé si quelque chose
 * échoue après.
 */
exports.register = async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');

  if (!email || !password) {
    return res.status(400).json({ error: 'Email et mot de passe requis' });
  }
  if (password.length < 6) {
    // Même seuil que Firebase Auth, pour ne pas rejeter un mot de passe
    // qu'il acceptait hier.
    return res.status(400).json({ error: 'Mot de passe trop court (6 minimum)' });
  }

  if (await Cabinet.exists({ email })) {
    return res.status(409).json({ error: 'Cet email est déjà utilisé' });
  }

  const cabinet = await Cabinet.create({
    email,
    passwordHash: await bcrypt.hash(password, COUT_HASH),
  });

  try {
    await Profile.create({
      parentUid: cabinet._id,
      name: 'Médecin Principal',
      role: 'medecin_principal',
      // Le PIN par défaut restait '0000' en clair. Il est haché, mais reste
      // '0000' : changer la valeur empêcherait d'entrer un compte créé
      // selon l'ancienne procédure.
      pinHash: await bcrypt.hash('0000', COUT_HASH),
    });
  } catch (e) {
    // Un cabinet sans profil ne sert à rien et bloquerait une seconde
    // inscription avec le même email.
    await Cabinet.deleteOne({ _id: cabinet._id });
    throw e;
  }

  return res.status(201).json({
    token: signerJeton(cabinet._id),
    cabinet: cabinet.toJSON(),
  });
};

exports.login = async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');

  const cabinet = await Cabinet.findOne({ email });
  // Même message et même délai dans les deux cas : distinguer « email
  // inconnu » de « mot de passe faux » dirait lesquels de vos emails sont
  // enregistrés.
  const ok = cabinet && (await bcrypt.compare(password, cabinet.passwordHash));
  if (!ok) {
    return res.status(401).json({ error: 'Email ou mot de passe incorrect' });
  }

  return res.json({
    token: signerJeton(cabinet._id),
    cabinet: cabinet.toJSON(),
  });
};

/**
 * Le second niveau : le PIN d'un profil.
 *
 * Ce n'était pas de l'authentification Firebase mais une comparaison de
 * chaînes dans l'app (`pinCtrl.text != data['pin']`), sur une valeur
 * stockée en clair. N'importe quel client modifié pouvait la sauter, et
 * quiconque lisait la base voyait tous les PIN du cabinet.
 */
exports.verifierPin = async (req, res) => {
  const profil = await resoudreProfil(req.parentUid, req.body.profileId);
  if (!profil) return res.status(404).json({ error: 'Profil introuvable' });

  const pin = String(req.body.pin || '');
  const ok = profil.pinHash
    ? await bcrypt.compare(pin, profil.pinHash)
    : pin === '0000';

  if (!ok) return res.status(401).json({ error: 'Code PIN incorrect' });
  return res.json({ ok: true, profile: profil.toJSON() });
};

/** `signOut` était purement local : rien à invalider côté serveur. */
exports.logout = (_req, res) => res.json({ ok: true });

exports.moi = async (req, res) => {
  const cabinet = await Cabinet.findById(req.parentUid);
  if (!cabinet) return res.status(404).json({ error: 'Cabinet introuvable' });
  return res.json(cabinet.toJSON());
};

/**
 * Les réglages du cabinet : horaires et motifs prédéfinis.
 *
 * Aucun écran ne permet encore de régler les horaires — ils étaient lus
 * depuis `users/{uid}.horaires` s'il existait, sinon codés en dur. La route
 * existe pour que l'écran de réglages ait où écrire.
 */
exports.majCabinet = async (req, res) => {
  const maj = {};
  if (req.body.horaires !== undefined) maj.horaires = req.body.horaires;
  if (req.body.motifPrototypes !== undefined) {
    maj.motifPrototypes = req.body.motifPrototypes;
  }
  if (Array.isArray(req.body.motifsPredefinis)) {
    maj.motifsPredefinis = req.body.motifsPredefinis
      .map((m) => String(m).trim())
      .filter(Boolean);
  }

  const cabinet = await Cabinet.findByIdAndUpdate(
    req.parentUid,
    { $set: maj },
    { new: true, runValidators: true }
  );
  if (!cabinet) return res.status(404).json({ error: 'Cabinet introuvable' });
  return res.json(cabinet.toJSON());
};
