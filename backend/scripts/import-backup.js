'use strict';

/**
 * Importe une sauvegarde Ordimed dans MongoDB.
 *
 *   node scripts/import-backup.js ./import/ordimed-2026-08-08-1430.json motdepasse
 *
 * C'est le pont entre les deux mondes. Le fichier vient de l'écran
 * « Sauvegardes » de l'app Flutter — celui qui écrit dans
 * `Documents\Ordimed\sauvegardes`. Il porte déjà tout le cabinet, et ses
 * types sont étiquetés (`{__type:'timestamp'}`), ce qui évite d'avoir à
 * deviner ce qui était une date.
 *
 * L'import est **idempotent** : relancé deux fois, il met à jour au lieu de
 * dupliquer. Une migration qu'on ne peut pas rejouer est une migration
 * qu'on n'ose pas commencer.
 */

const fs = require('fs');
const path = require('path');

const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');

const c = require('../lib/coerce');
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
  process.env.MONGO_URL || 'mongodb://127.0.0.1:27017/ordimed?replicaSet=rs0';

/** Les cinq orthographes du numéro de séance rencontrées en base. */
function numeroSeance(d) {
  return (
    c.asTextOrNull(d.seanceNumero) ||
    c.asTextOrNull(d.seanceNumber) ||
    c.asTextOrNull(d.numeroSeance) ||
    c.asTextOrNull(d.seance_numero) ||
    ''
  );
}

/** Les deux vocabulaires de la salle d'attente. */
function etapeFile(d) {
  const etape = c.asText(d.etape).toLowerCase();
  if (['arrive', 'en_cours', 'honore', 'annule'].includes(etape)) return etape;

  const status = c.asText(d.status).toLowerCase();
  if (status === 'cancelled' || status === 'canceled') return 'annule';
  if (d.closedAt || status === 'done' || status === 'closed') return 'honore';
  if (status === 'in_consultation' || d.inConsultationAt) return 'en_cours';
  return 'arrive';
}

const STATUS_POUR = {
  arrive: 'waiting',
  en_cours: 'in_consultation',
  honore: 'done',
  annule: 'cancelled',
};

/**
 * Importe une sauvegarde déjà décodée.
 *
 * Séparé de la ligne de commande pour être testable : vérifier que les
 * copies Firestore sont bien dédoublonnées et que les versements ne
 * comptent pas double n'a pas à passer par un fichier ni par `process.exit`.
 *
 * `silencieux` coupe la sortie console pendant les tests.
 */
async function importer(brut, { motDePasse, silencieux = false } = {}) {
  const dire = silencieux ? () => {} : console.log;

  if (!brut || typeof brut !== 'object' || !brut.comptes) {
    throw new Error(
      'Ce fichier ne ressemble pas à une sauvegarde Ordimed ' +
        '(clé « comptes » absente).'
    );
  }

  const compteur = {
    profils: 0,
    patients: 0,
    forms: 0,
    versements: 0,
    rendezvous: 0,
    salle_attente: 0,
    purchases: 0,
    daily_stats: 0,
    ignores: 0,
  };

  // ---- Le cabinet ----
  const racine = brut.racine || {};
  const email = c.asText(racine.email).toLowerCase() || 'cabinet@ordimed.local';

  let cabinet = await Cabinet.findOne({ email });
  if (!cabinet) {
    if (!motDePasse) {
      // Une erreur plutôt qu'un `process.exit` : la fonction doit pouvoir
      // être appelée depuis un test sans tuer le processus.
      throw new Error(
        `Le cabinet « ${email} » n'existe pas encore. Donne un mot de passe ` +
          'en second argument : Firebase gardait le mot de passe de son ' +
          'côté, la sauvegarde ne le contient pas.'
      );
    }
    cabinet = await Cabinet.create({
      email,
      passwordHash: await bcrypt.hash(motDePasse, 10),
      createdAt: c.asDateOrNull(racine.createdAt) || new Date(),
      horaires: racine.horaires || undefined,
      // Conserve pour que le chemin inverse reste possible.
      firebaseUid: c.asText(brut.parentUid),
    });
    dire(`Cabinet créé : ${email}`);
  } else {
    // Un cabinet importe une premiere fois avant l'ajout de ce champ n'a pas
    // d'uid : on le rattrape ici plutot que d'exiger un reimport complet.
    if (!cabinet.firebaseUid && brut.parentUid) {
      cabinet.firebaseUid = c.asText(brut.parentUid);
      await cabinet.save();
    }
    dire(`Cabinet existant réutilisé : ${email}`);
  }

  /**
   * Les identifiants Firestore étaient des chaînes ; MongoDB veut des
   * ObjectId. On garde la correspondance pour rebrancher les références —
   * un patient pointe vers un profil, un document vers un patient.
   */
  const idProfil = new Map(); // ancien id Firestore -> ObjectId
  const idPatient = new Map();

  // ---- Passe 1 : les profils ----
  for (const [ancienId, contenu] of Object.entries(brut.comptes)) {
    const d = contenu.donnees || {};
    const role = ['medecin_principal', 'medecin', 'assistant'].includes(d.role)
      ? d.role
      : ancienId === 'medecin_principal'
        ? 'medecin_principal'
        : 'assistant';

    // Le médecin principal est unique par cabinet (index partiel) : on le
    // retrouve par son rôle plutôt que d'en créer un second.
    const existant =
      role === 'medecin_principal'
        ? await Profile.findOne({ parentUid: cabinet._id, role })
        : await Profile.findOne({
            parentUid: cabinet._id,
            name: c.asText(d.name),
            role,
          });

    const donnees = {
      parentUid: cabinet._id,
      name: c.asText(d.name),
      role,
      wilaya: c.asText(d.wilaya),
      address: c.asText(d.address || d.adresse),
      tel: c.asText(d.tel || d.telephone),
      whatsappTemplate: c.asText(d.whatsappTemplate),
      firestoreId: ancienId,
      createdAt: c.asDateOrNull(d.createdAt) || new Date(),
    };

    // Le PIN était en clair dans Firestore. Il est haché ici — c'est le
    // seul moment où on le voit encore.
    const pinClair = c.asText(d.pin).trim() || '0000';

    let profil;
    if (existant) {
      Object.assign(existant, donnees);
      if (!existant.pinHash) existant.pinHash = await bcrypt.hash(pinClair, 10);
      profil = await existant.save();
    } else {
      profil = await Profile.create({
        ...donnees,
        pinHash: await bcrypt.hash(pinClair, 10),
      });
    }

    idProfil.set(ancienId, profil._id);
    compteur.profils++;
  }

  const profilDe = (ancien) => idProfil.get(c.asText(ancien)) || null;

  // ---- Passe 2 : patients ----
  //
  // Firestore écrivait chaque patient deux fois, sous le médecin et sous
  // l'assistant. La sauvegarde contient donc les deux copies. On les
  // dédoublonne sur l'identifiant Firestore : un seul document ici.
  for (const [ancienProfilId, contenu] of Object.entries(brut.comptes)) {
    const patients = contenu.collections?.patients;
    if (!patients) continue;

    for (const [ancienId, item] of Object.entries(patients)) {
      const d = item.donnees || item || {};

      if (idPatient.has(ancienId)) {
        compteur.ignores++;
      } else {
        const doc = await Patient.findOneAndUpdate(
          // Rapprochement sur le nom et la date de création : la
          // sauvegarde ne porte pas d'identifiant réutilisable en Mongo.
          {
            parentUid: cabinet._id,
            nom: c.asText(d.nom),
            prenom: c.asText(d.prenom),
            createdAt: c.asDateOrNull(d.createdAt) || new Date(0),
          },
          {
            $set: {
              parentUid: cabinet._id,
              doctorId: profilDe(d.doctorId),
              assistantId: profilDe(d.assistantId),
              nom: c.asText(d.nom),
              prenom: c.asText(d.prenom),
              // Chaîne sur les anciens dossiers, entier depuis peu.
              age: c.asIntOrNull(d.age),
              tel: c.asText(d.tel),
              email: c.asText(d.email),
              origine: c.asText(d.origine),
              motifs: Array.isArray(d.motifs) ? d.motifs.map(c.asText) : [],
              motif: c.asText(d.motif),
              assistantName: c.asText(d.assistantName),
              assignedMedecinName: c.asText(d.assignedMedecinName),
              poids_actuel: c.asNumberOrNull(d.poids_actuel),
              taille: c.asNumberOrNull(d.taille),
              imc: c.asText(d.imc),
              derniereConsultation: c.asDateOrNull(d.derniereConsultation),
              nombreSeances: c.asIntOrNull(d.nombreSeances),
              seancesEffectuees: c.asInt(d.seancesEffectuees),
              // `number` ou `string` selon l'écran de saisie d'origine.
              prix: c.asNumberOrNull(d.prix),
              totalVersements: c.asNumber(d.totalVersements),
              firestoreId: ancienId,
              createdAt: c.asDateOrNull(d.createdAt) || new Date(),
              deletedAt: c.asDateOrNull(d.deletedAt),
            },
          },
          { upsert: true, new: true, setDefaultsOnInsert: true }
        );
        idPatient.set(ancienId, doc._id);
        compteur.patients++;
      }

      const patientId = idPatient.get(ancienId);

      // Les documents du patient.
      for (const [, f] of Object.entries(item.collections?.forms || {})) {
        const type = c.asText(f.type);
        if (!type) continue;

        const createdAt = c.asDateOrNull(f.createdAt) || new Date();
        const existe = await Form.exists({
          parentUid: cabinet._id,
          patientId,
          type,
          createdAt,
        });
        if (existe) continue;

        await Form.create({
          parentUid: cabinet._id,
          patientId,
          auteurProfileId: profilDe(f.auteurProfileId),
          type,
          contenu: c.asText(f.contenu),
          poids: c.asNumberOrNull(f.poids),
          taille: c.asNumberOrNull(f.taille),
          imc: c.asText(f.imc),
          notes: c.asText(f.notes),
          sections: f.sections || undefined,
          prescriptions: f.prescriptions || undefined,
          examens: f.examens || undefined,
          ordonnanceNumero: c.asText(f.ordonnanceNumero),
          seanceNumero: numeroSeance(f),
          note_de_seance: c.asText(f.note_de_seance || f.noteSeance),
          createdAt,
        });
        compteur.forms++;
      }

      /**
       * Les versements viennent de deux endroits : la sous-collection
       * (historique complet) et le tableau du document (cache des 50 plus
       * récents). Les deux doivent être lus — les versements antérieurs à
       * la sous-collection n'existent que dans le tableau — et
       * dédoublonnés, sinon le total du patient doublerait.
       */
      const vus = new Set();
      const ajouterVersement = async (v) => {
        const montant = c.asNumber(v.montant);
        if (!montant) return;
        const date = c.asDateOrNull(v.createdAt) || null;
        const cle = `${montant}@${date ? date.toISOString() : 'sans-date'}`;
        if (vus.has(cle)) return;
        vus.add(cle);

        const existe = await Versement.exists({
          parentUid: cabinet._id,
          patientId,
          montant,
          createdAt: date,
        });
        if (existe) return;

        await Versement.create({
          parentUid: cabinet._id,
          patientId,
          doctorId: profilDe(d.doctorId),
          auteurProfileId: profilDe(v.auteurProfileId),
          montant,
          dayKey: c.asText(v.dayKey) || (date ? c.dayKeyOf(date) : ''),
          createdAt: date || new Date(),
        });
        compteur.versements++;
      };

      for (const [, v] of Object.entries(item.collections?.versements || {})) {
        await ajouterVersement(v);
      }
      if (Array.isArray(d.versements)) {
        for (const v of d.versements) await ajouterVersement(v);
      }
    }
  }

  const patientDe = (ancien) => idPatient.get(c.asText(ancien)) || null;

  // ---- Passe 3 : rendez-vous, file, achats, stats ----
  //
  // Eux aussi étaient dupliqués (jusqu'à trois copies). Le dédoublonnage se
  // fait sur l'identifiant Firestore du document.
  const rdvVus = new Set();
  const fileVue = new Set();
  const achatVu = new Set();

  for (const [, contenu] of Object.entries(brut.comptes)) {
    const cols = contenu.collections || {};

    for (const [ancienId, item] of Object.entries(cols.rendezvous || {})) {
      if (rdvVus.has(ancienId)) continue;
      rdvVus.add(ancienId);

      const d = item.donnees || item || {};
      const patientId = patientDe(d.patientId);
      const datetime = c.asDateOrNull(d.datetime);
      // Un rendez-vous sans date ou sans patient identifiable ne peut pas
      // être reconstruit : le poser à minuit fabriquerait un faux conflit.
      if (!patientId || !datetime) {
        compteur.ignores++;
        continue;
      }

      const doctorId = profilDe(d.doctorId);
      if (!doctorId) {
        compteur.ignores++;
        continue;
      }

      await RendezVous.findOneAndUpdate(
        { parentUid: cabinet._id, patientId, datetime, doctorId },
        {
          $set: {
            parentUid: cabinet._id,
            patientId,
            doctorId,
            assistantId: profilDe(d.assistantId),
            patientNom: c.asText(d.patientNom),
            patientPrenom: c.asText(d.patientPrenom),
            patientTel: c.asText(d.patientTel),
            doctorName: c.asText(d.doctorName),
            motif: c.asText(d.motif),
            datetime,
            duree: c.asInt(d.duree, 20),
            // Absent des rendez-vous antérieurs : lus comme « planifie ».
            etape: c.asText(d.etape) || 'planifie',
            reminderTemplate: c.asText(d.reminderTemplate),
            reminderSentAt: c.asDateOrNull(d.reminderSentAt),
            createdAt: c.asDateOrNull(d.createdAt) || new Date(),
          },
        },
        { upsert: true, setDefaultsOnInsert: true }
      );
      compteur.rendezvous++;
    }

    for (const [ancienId, item] of Object.entries(cols.salle_attente || {})) {
      if (fileVue.has(ancienId)) continue;
      fileVue.add(ancienId);

      const d = item.donnees || item || {};
      const patientId = patientDe(d.patientId);
      if (!patientId) {
        compteur.ignores++;
        continue;
      }

      const etape = etapeFile(d);
      const createdAt = c.asDateOrNull(d.createdAt) || new Date();

      await Waiting.findOneAndUpdate(
        { parentUid: cabinet._id, patientId, createdAt },
        {
          $set: {
            parentUid: cabinet._id,
            patientId,
            doctorId: profilDe(d.doctorId),
            assistantId: profilDe(d.assistantId),
            patientNom: c.asText(d.patientNom),
            patientPrenom: c.asText(d.patientPrenom),
            doctorName: c.asText(d.doctorName),
            assistantName: c.asText(d.assistantName),
            motif: c.asText(d.motif),
            nombreSeances: c.asIntOrNull(d.nombreSeances),
            seancesEffectuees: c.asIntOrNull(d.seancesEffectuees),
            etape,
            // Les deux vocabulaires restent écrits ensemble.
            status: STATUS_POUR[etape],
            createdAt,
            inConsultationAt: c.asDateOrNull(d.inConsultationAt),
            closedAt: c.asDateOrNull(d.closedAt),
          },
        },
        { upsert: true, setDefaultsOnInsert: true }
      );
      compteur.salle_attente++;
    }

    for (const [ancienId, item] of Object.entries(cols.purchases || {})) {
      if (achatVu.has(ancienId)) continue;
      achatVu.add(ancienId);

      const d = item.donnees || item || {};
      const createdAt = c.asDateOrNull(d.createdAt) || new Date();

      await Purchase.findOneAndUpdate(
        {
          parentUid: cabinet._id,
          produit: c.asText(d.produit),
          montant: c.asNumber(d.montant),
          createdAt,
        },
        {
          $set: {
            parentUid: cabinet._id,
            profileId: profilDe(d.profileId),
            produit: c.asText(d.produit),
            fournisseur: c.asText(d.fournisseur),
            montant: c.asNumber(d.montant),
            dayKey: c.asText(d.dayKey) || c.dayKeyOf(createdAt),
            createdAt,
          },
        },
        { upsert: true, setDefaultsOnInsert: true }
      );
      compteur.purchases++;
    }

    for (const [dayKey, item] of Object.entries(cols.daily_stats || {})) {
      const d = item.donnees || item || {};
      await DailyStat.findOneAndUpdate(
        { parentUid: cabinet._id, dayKey },
        {
          $set: {
            parentUid: cabinet._id,
            dayKey,
            date: c.asDateOrNull(d.date),
            versementsTotal: c.asNumber(d.versementsTotal),
            versementsCount: c.asInt(d.versementsCount),
            achatsTotal: c.asNumber(d.achatsTotal),
            achatsCount: c.asInt(d.achatsCount),
            doctorVersements: d.doctorVersements || {},
            updatedAt: new Date(),
          },
        },
        { upsert: true, setDefaultsOnInsert: true }
      );
      compteur.daily_stats++;
    }
  }

  dire('\nImport terminé');
  for (const [k, v] of Object.entries(compteur)) {
    dire(`  ${k.padEnd(16)} ${v}`);
  }
  dire(
    '\n« ignores » compte les copies dédoublonnées et les documents ' +
      'inexploitables (rendez-vous sans date, patient introuvable).'
  );

  return { cabinet, compteur };
}

/** L'enveloppe ligne de commande. */
async function main() {
  const fichier = process.argv[2];
  const motDePasse = process.argv[3];

  if (!fichier) {
    console.error(
      'Usage : node scripts/import-backup.js <sauvegarde.json> [motDePasse]'
    );
    process.exit(1);
  }

  const chemin = path.resolve(fichier);
  if (!fs.existsSync(chemin)) {
    console.error(`Fichier introuvable : ${chemin}`);
    process.exit(1);
  }

  await mongoose.connect(MONGO_URL, { serverSelectionTimeoutMS: 15000 });
  console.log(`MongoDB connecté — import de ${path.basename(chemin)}`);

  await importer(JSON.parse(fs.readFileSync(chemin, 'utf8')), { motDePasse });
  await mongoose.disconnect();
}

module.exports = { importer };

// Lancé en ligne de commande, pas requis par un test.
if (require.main === module) {
  main().catch((e) => {
    console.error('Import interrompu :', e.message);
    process.exit(1);
  });
}
