'use strict';

/**
 * Exporte un cabinet MongoDB au format de sauvegarde Ordimed.
 *
 *   node scripts/export-json.js cabinet@test.dz ./import/retour.json
 *
 * C'est le chemin inverse de `import-backup.js`, et il ferme la boucle :
 * l'app Firebase — au tag `firebase-final` — sait déjà **restaurer** ce
 * format dans Firestore (`BackupService.restaurer`). Revenir en arrière
 * devient donc deux commandes, pas un chantier.
 *
 * Sans ce script, tout ce qui aurait été écrit dans MongoDB après la
 * bascule n'existerait nulle part ailleurs, et le retour à Firebase
 * signifierait perdre ce travail.
 *
 * Le fichier produit sert aussi de sauvegarde tout court : il ne dépend
 * d'aucun serveur pour être relu.
 */

const fs = require('fs');
const path = require('path');

const mongoose = require('mongoose');

const {
  Cabinet,
  Profile,
  Patient,
  Form,
  Versement,
  RendezVous,
  Waiting,
  Purchase,
  DailyStat,
} = require('../models');

const MONGO_URL =
  process.env.MONGO_URL ||
  'mongodb://127.0.0.1:27017/ordimed?replicaSet=rs0&w=majority&journal=true';

/** Version du format, alignée sur `BackupService.versionFormat`. */
const VERSION_FORMAT = 1;

/**
 * Encode une valeur au format de la sauvegarde Flutter.
 *
 * Les dates portent une étiquette `{__type:'timestamp'}` : sans elle, une
 * date relue redeviendrait une chaîne, et l'app Firebase écrirait du texte
 * là où elle attend un `Timestamp`. Les tris et les filtres cesseraient de
 * fonctionner sans que rien ne le signale.
 */
function encoder(valeur) {
  if (valeur === null || valeur === undefined) return null;
  if (valeur instanceof Date) {
    return { __type: 'timestamp', value: valeur.toISOString() };
  }
  // `_bsontype` plutot que `instanceof` : deux copies de la bibliotheque
  // mongodb dans l'arbre des dependances donnent deux classes ObjectId
  // distinctes, et le test d'instance echoue silencieusement.
  if (valeur && valeur._bsontype === 'ObjectId') return String(valeur);
  if (Buffer.isBuffer(valeur)) return valeur.toString('base64');

  if (Array.isArray(valeur)) return valeur.map(encoder);

  if (typeof valeur === 'object') {
    const sortie = {};
    for (const [k, v] of Object.entries(valeur)) {
      // Les sous-documents Mongoose portent une reference vers leur parent
      // (`$parent`, `$__`) : suivre ces cles fait tourner l'encodeur en
      // rond jusqu'a epuiser la pile.
      if (k.startsWith('$') || k === '_id' || k === '__v') continue;
      sortie[k] = encoder(v);
    }
    return sortie;
  }
  return valeur;
}

/**
 * Champs qui pointent vers un autre document.
 *
 * L'export les indexe par leur identifiant Firestore d'origine ; ils
 * doivent donc etre traduits, sinon l'import les cherche en vain et ecarte
 * le document **en silence** — un rendez-vous disparu sans message.
 */
const REFS_PROFIL = ['doctorId', 'assistantId', 'auteurProfileId', 'profileId'];
const REFS_PATIENT = ['patientId'];

/** Un document Mongoose, débarrassé de ce qui n'a pas de sens ailleurs. */
function donneesDe(doc, exclure = [], cles = null) {
  const brut = doc.toObject
    ? doc.toObject({ depopulate: true, virtuals: false, flattenMaps: true })
    : { ...doc };
  const aRetirer = [
    '_id',
    '__v',
    'id',
    'parentUid',
    'passwordHash',
    'pinHash',
    'firestoreId',
    'firebaseUid',
    ...exclure,
  ];
  for (const k of aRetirer) delete brut[k];

  if (cles) {
    for (const champ of REFS_PROFIL) {
      if (brut[champ]) brut[champ] = cles.profils.get(String(brut[champ])) || null;
    }
    for (const champ of REFS_PATIENT) {
      if (brut[champ]) brut[champ] = cles.patients.get(String(brut[champ])) || null;
    }
  }

  return encoder(brut);
}

/**
 * L'identifiant sous lequel Firestore connaissait ce document.
 *
 * Le réutiliser fait que la restauration **réécrit** le document existant
 * au lieu d'en créer un second. Sans lui, un retour vers Firebase
 * doublerait chaque dossier.
 */
const cleDe = (doc) =>
  doc.firestoreId && doc.firestoreId.length > 0
    ? doc.firestoreId
    : String(doc._id);

async function exporter(email, { silencieux = false } = {}) {
  const dire = silencieux ? () => {} : console.log;

  const cabinet = await Cabinet.findOne({ email: String(email).toLowerCase() });
  if (!cabinet) throw new Error(`Cabinet introuvable : ${email}`);

  const profils = await Profile.find({ parentUid: cabinet._id }).sort({
    createdAt: 1,
  });

  // Correspondance ObjectId -> cle d'export, etablie avant tout encodage :
  // un patient reference son medecin, un rendez-vous son patient.
  const cles = { profils: new Map(), patients: new Map() };
  for (const p of profils) {
    cles.profils.set(
      String(p._id),
      p.role === 'medecin_principal' ? 'medecin_principal' : cleDe(p)
    );
  }
  for (const p of await Patient.find({ parentUid: cabinet._id })) {
    cles.patients.set(String(p._id), cleDe(p));
  }

  let documents = 1 + profils.length;
  const comptes = {};

  for (const profil of profils) {
    dire(`Profil ${profil.name || profil.role}…`);

    /**
     * Le médecin principal reprend son identifiant fixe.
     *
     * 65 endroits de l'app Firebase référencent la chaîne littérale
     * `medecin_principal` comme identifiant de document. Exporter un
     * ObjectId à sa place rendrait le cabinet inutilisable au retour.
     */
    const cleProfil =
      profil.role === 'medecin_principal' ? 'medecin_principal' : cleDe(profil);

    const collections = {};

    // ---- Patients, avec leurs documents et versements ----
    const patients = await Patient.find({
      parentUid: cabinet._id,
      $or: [{ doctorId: profil._id }, { assistantId: profil._id }],
    });

    if (patients.length) {
      const items = {};
      for (const patient of patients) {
        documents++;
        const sous = {};

        const forms = await Form.find({ patientId: patient._id });
        if (forms.length) {
          documents += forms.length;
          sous.forms = Object.fromEntries(
            forms.map((f) => [cleDe(f), donneesDe(f, ['patientId'], cles)])
          );
        }

        const versements = await Versement.find({ patientId: patient._id });
        if (versements.length) {
          documents += versements.length;
          sous.versements = Object.fromEntries(
            versements.map((v) => [cleDe(v), donneesDe(v, ['patientId'], cles)])
          );
        }

        const item = { donnees: donneesDe(patient, [], cles) };
        if (Object.keys(sous).length) item.collections = sous;
        items[cleDe(patient)] = item;
      }
      collections.patients = items;
    }

    // ---- Rendez-vous, file, achats, statistiques ----
    const rdvs = await RendezVous.find({
      parentUid: cabinet._id,
      $or: [{ doctorId: profil._id }, { assistantId: profil._id }],
    });
    if (rdvs.length) {
      documents += rdvs.length;
      collections.rendezvous = Object.fromEntries(
        rdvs.map((r) => [cleDe(r), { donnees: donneesDe(r, [], cles) }])
      );
    }

    const file = await Waiting.find({
      parentUid: cabinet._id,
      $or: [{ doctorId: profil._id }, { assistantId: profil._id }],
    });
    if (file.length) {
      documents += file.length;
      collections.salle_attente = Object.fromEntries(
        file.map((w) => [cleDe(w), { donnees: donneesDe(w, [], cles) }])
      );
    }

    const achats = await Purchase.find({
      parentUid: cabinet._id,
      profileId: profil._id,
    });
    if (achats.length) {
      documents += achats.length;
      collections.purchases = Object.fromEntries(
        achats.map((a) => [cleDe(a), { donnees: donneesDe(a, [], cles) }])
      );
    }

    comptes[cleProfil] = { donnees: donneesDe(profil, [], cles), collections };
  }

  /**
   * Les statistiques ne dépendent d'aucun profil.
   *
   * Firestore les rangeait sous le cabinet ; le format de sauvegarde les
   * attend sous un profil. On les pose sous le médecin principal, qui est
   * celui qui les consulte.
   */
  const stats = await DailyStat.find({ parentUid: cabinet._id });
  if (stats.length) {
    documents += stats.length;
    const cible =
      comptes.medecin_principal ||
      comptes[Object.keys(comptes)[0]];
    if (cible) {
      cible.collections.daily_stats = Object.fromEntries(
        stats.map((s) => [s.dayKey, { donnees: donneesDe(s) }])
      );
    }
  }

  return {
    version: VERSION_FORMAT,
    genereLe: new Date().toISOString(),
    // L'uid Firebase d'origine, sans lequel l'app refuserait le fichier :
    // « cette sauvegarde appartient à un autre cabinet ».
    parentUid: cabinet.firebaseUid || String(cabinet._id),
    documents,
    racine: {
      email: cabinet.email,
      createdAt: encoder(cabinet.createdAt),
      horaires: encoder(cabinet.horaires),
      motifsPredefinis: cabinet.motifsPredefinis,
    },
    comptes,
  };
}

function nomFichier(maintenant = new Date()) {
  const p = (v) => String(v).padStart(2, '0');
  return (
    `ordimed-${maintenant.getFullYear()}-${p(maintenant.getMonth() + 1)}-` +
    `${p(maintenant.getDate())}-${p(maintenant.getHours())}` +
    `${p(maintenant.getMinutes())}.json`
  );
}

async function main() {
  const email = process.argv[2];
  const sortie = process.argv[3] || `./import/${nomFichier()}`;

  if (!email) {
    console.error('Usage : node scripts/export-json.js <email> [fichier.json]');
    process.exit(1);
  }

  await mongoose.connect(MONGO_URL, { serverSelectionTimeoutMS: 15000 });
  console.log('MongoDB connecté');

  const contenu = await exporter(email);

  const chemin = path.resolve(sortie);
  fs.mkdirSync(path.dirname(chemin), { recursive: true });
  fs.writeFileSync(chemin, JSON.stringify(contenu, null, 2), 'utf8');

  console.log(`\n${contenu.documents} documents écrits dans ${chemin}`);
  console.log(
    '\nPour revenir à Firebase :\n' +
      '  1. git checkout firebase-final && flutter build windows --debug\n' +
      '  2. copie ce fichier dans Documents\\Ordimed\\sauvegardes\n' +
      '  3. lance l’app → Sauvegardes → Restaurer'
  );

  await mongoose.disconnect();
}

module.exports = { exporter, encoder, nomFichier };

if (require.main === module) {
  main().catch((e) => {
    console.error('Export interrompu :', e.message);
    process.exit(1);
  });
}
