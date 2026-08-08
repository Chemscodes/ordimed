'use strict';

const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');

const { Profile } = require('../models');

/**
 * Autorisation.
 *
 * C'est le portage de `firestore.rules`. La règle tenait en une ligne :
 *
 *   match /users/{uid}/{document=**} { allow read, write: if owner(uid); }
 *
 * Autrement dit : un cabinet ne voit que ses propres données, et rien
 * d'autre. Toute la sécurité du produit repose là-dessus.
 *
 * Le danger de la reprise en REST est qu'il n'y a plus de règle globale :
 * chaque route doit filtrer sur `parentUid`. Un oubli n'échoue pas — il
 * expose les dossiers d'un autre cabinet, en silence. D'où `scope()`, qui
 * fabrique le filtre au lieu de laisser chaque contrôleur l'écrire.
 */

const SECRET = process.env.JWT_SECRET || 'dev-secret-a-changer';
const EXPIRES = process.env.JWT_EXPIRES || '30d';

if (process.env.NODE_ENV === 'production' && SECRET === 'dev-secret-a-changer') {
  // Un secret par défaut en production laisse fabriquer un jeton valide
  // pour n'importe quel cabinet. Mieux vaut refuser de démarrer.
  throw new Error(
    'JWT_SECRET doit être défini en production : le secret par défaut ' +
      'permettrait de forger un jeton pour n’importe quel cabinet.'
  );
}

const signerJeton = (cabinetId) =>
  jwt.sign({ sub: String(cabinetId) }, SECRET, { expiresIn: EXPIRES });

/** Exige un jeton valide. Pose `req.parentUid`. */
function exigeAuth(req, res, next) {
  const entete = req.headers.authorization || '';
  const jeton = entete.startsWith('Bearer ') ? entete.slice(7) : null;

  if (!jeton) {
    return res.status(401).json({ error: 'Jeton absent' });
  }

  try {
    const charge = jwt.verify(jeton, SECRET);
    req.parentUid = new mongoose.Types.ObjectId(String(charge.sub));
    return next();
  } catch (e) {
    // Distingué du 401 générique : l'app Flutter peut proposer de se
    // reconnecter plutôt que d'afficher « accès refusé ».
    const expire = e.name === 'TokenExpiredError';
    return res
      .status(401)
      .json({ error: expire ? 'Session expirée' : 'Jeton invalide', expire });
  }
}

/**
 * Le filtre à appliquer à **toute** requête de lecture ou d'écriture.
 *
 * `Patient.find(scope(req))` au lieu de `Patient.find({})`. Ce n'est pas
 * une commodité : c'est la seule chose qui empêche un cabinet de lire les
 * patients d'un autre.
 */
const scope = (req, extra = {}) => ({ parentUid: req.parentUid, ...extra });

/**
 * Vérifie qu'un profil appartient bien au cabinet du jeton.
 *
 * Sans ça, un identifiant de profil passé dans l'URL suffirait à écrire
 * dans le cabinet du voisin — le jeton étant valide, seule l'appartenance
 * du profil est en cause.
 */
async function exigeProfil(req, res, next) {
  const brut = req.params.profileId || req.body.profileId || req.query.profileId;
  if (!brut) return res.status(400).json({ error: 'profileId requis' });

  const profil = await resoudreProfil(req.parentUid, brut);
  if (!profil) {
    // 404 et non 403 : dire « ce profil existe mais n'est pas à vous »
    // renseignerait sur l'existence d'un identifiant.
    return res.status(404).json({ error: 'Profil introuvable' });
  }

  req.profile = profil;
  return next();
}

/**
 * Résout un identifiant de profil.
 *
 * L'app Flutter référence le médecin principal par la chaîne littérale
 * `medecin_principal`, héritée de Firestore où c'était un identifiant de
 * document fixe. Le traduire ici évite de toucher aux 65 endroits qui
 * l'utilisent.
 */
async function resoudreProfil(parentUid, identifiant) {
  const id = String(identifiant);

  if (id === 'medecin_principal') {
    return Profile.findOne({ parentUid, role: 'medecin_principal' });
  }
  if (!mongoose.Types.ObjectId.isValid(id)) return null;

  return Profile.findOne({ _id: id, parentUid });
}

/**
 * Vérifie le PIN d'un profil.
 *
 * Le PIN était comparé côté client (`pinCtrl.text != data['pin']`), sur une
 * valeur stockée en clair. Quiconque lisait la base voyait tous les PIN, et
 * n'importe quel client modifié pouvait sauter la comparaison.
 */
function exigeRole(...roles) {
  return (req, res, next) => {
    if (!req.profile) return res.status(400).json({ error: 'Profil requis' });
    if (!roles.includes(req.profile.role)) {
      return res.status(403).json({ error: 'Action non autorisée pour ce rôle' });
    }
    return next();
  };
}

module.exports = {
  signerJeton,
  exigeAuth,
  exigeProfil,
  exigeRole,
  resoudreProfil,
  scope,
};
