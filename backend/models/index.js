'use strict';

const mongoose = require('mongoose');

const { Schema, Types } = mongoose;

/**
 * Les modèles, portés depuis Firestore.
 *
 * Firestore était hiérarchique : `users/{uid}/comptes/{id}/patients/{id}`.
 * MongoDB est plat. La hiérarchie devient des références indexées, et les
 * requêtes qui exigeaient un `collectionGroup` deviennent des `find`
 * ordinaires.
 *
 * Un document par entité. Firestore écrivait chaque patient deux fois (chez
 * le médecin et chez l'assistant) et chaque entrée de salle d'attente trois
 * fois, parce qu'il ne sait pas joindre. MongoDB sait : `doctorId` et
 * `assistantId` sont indexés, la même liste se retrouve par requête. Garder
 * la duplication n'aurait rien changé à l'écran, sinon la possibilité que
 * les copies divergent en silence.
 */

const options = {
  timestamps: false, // `createdAt` est déjà porté par les données existantes.
  versionKey: false,
  toJSON: {
    virtuals: true,
    // L'app Flutter lit des identifiants sous forme de chaînes (`doc.id`).
    // Renvoyer `_id` en ObjectId brut casserait toutes les comparaisons.
    transform(_doc, ret) {
      ret.id = String(ret._id);
      delete ret._id;
      return ret;
    },
  },
};

// ---------------------------------------------------------------------
//  Le cabinet — anciennement users/{uid}
// ---------------------------------------------------------------------

const HorairesSchema = new Schema(
  {
    // Minutes depuis minuit, comme dans lib/core/creneaux.dart.
    ouverture: { type: Number, default: 8 * 60 },
    fermeture: { type: Number, default: 17 * 60 },
    pauseDebut: { type: Number, default: 12 * 60 },
    pauseFin: { type: Number, default: 13 * 60 },
    duree: { type: Number, default: 20 },
    // Samedi à jeudi : la semaine algérienne, le repos est le vendredi.
    joursOuvres: { type: [Number], default: [6, 7, 1, 2, 3, 4] },
  },
  { _id: false }
);

const CabinetSchema = new Schema(
  {
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    // Firebase Auth gardait le mot de passe. Ici c'est notre responsabilité.
    passwordHash: { type: String, required: true },
    horaires: { type: HorairesSchema, default: () => ({}) },
    createdAt: { type: Date, default: Date.now },
  },
  options
);

// ---------------------------------------------------------------------
//  Les profils — anciennement comptes/{profileId}
// ---------------------------------------------------------------------

const ProfileSchema = new Schema(
  {
    parentUid: { type: Types.ObjectId, ref: 'Cabinet', required: true, index: true },
    name: { type: String, default: '' },
    role: {
      type: String,
      enum: ['medecin_principal', 'medecin', 'assistant'],
      required: true,
    },
    /**
     * Le PIN était stocké en clair et comparé côté client
     * (`pinCtrl.text != data['pin']`). Quiconque lisait la base voyait tous
     * les PIN. Il est haché ici, et la comparaison se fait sur le serveur.
     */
    pinHash: { type: String, default: '' },

    // En-têtes des ordonnances et des reçus.
    wilaya: { type: String, default: '' },
    address: { type: String, default: '' },
    tel: { type: String, default: '' },

    whatsappTemplate: { type: String, default: '' },
    whatsappTemplateUpdatedAt: { type: Date, default: null },

    createdAt: { type: Date, default: Date.now },
  },
  options
);

// Un seul médecin principal par cabinet : du code Flutter le référence par
// un identifiant fixe (`base.doc('medecin_principal')`), il doit être
// résoluble sans ambiguïté.
ProfileSchema.index(
  { parentUid: 1, role: 1 },
  { unique: true, partialFilterExpression: { role: 'medecin_principal' } }
);

// ---------------------------------------------------------------------
//  Les patients
// ---------------------------------------------------------------------

const VersementCacheSchema = new Schema(
  {
    montant: { type: Number, default: 0 },
    createdAt: { type: Date, default: Date.now },
    dayKey: { type: String, default: '' },
    auteurProfileId: { type: String, default: '' },
  },
  { _id: false }
);

const PatientSchema = new Schema(
  {
    parentUid: { type: Types.ObjectId, ref: 'Cabinet', required: true, index: true },
    doctorId: { type: Types.ObjectId, ref: 'Profile', default: null, index: true },
    assistantId: { type: Types.ObjectId, ref: 'Profile', default: null, index: true },

    nom: { type: String, default: '', trim: true },
    prenom: { type: String, default: '', trim: true },
    /**
     * Entier. Les dossiers antérieurs le portaient en chaîne ; la
     * conversion se fait à l'entrée (lib/coerce.js) plutôt que d'accepter
     * un champ de type flottant.
     */
    age: { type: Number, default: null },
    tel: { type: String, default: '' },
    email: { type: String, default: '' },
    origine: { type: String, default: '' },

    // Les deux sont écrits par l'app : `motifs` est la liste, `motif` la
    // même chose jointe par « , ». Plusieurs vues ne lisent que le second.
    motifs: { type: [String], default: [] },
    motif: { type: String, default: '' },

    assistantName: { type: String, default: '' },
    assignedMedecinName: { type: String, default: '' },
    createdByAssistantProfileId: { type: String, default: '' },

    // Clinique.
    poids_actuel: { type: Number, default: null },
    taille: { type: Number, default: null },
    // Chaîne, pas nombre : l'app l'affiche formaté à la virgule (« 23,7 »).
    imc: { type: String, default: '' },
    derniereConsultation: { type: Date, default: null },

    // Forfait.
    nombreSeances: { type: Number, default: null },
    seancesEffectuees: { type: Number, default: 0 },

    // Argent.
    prix: { type: Number, default: null },
    totalVersements: { type: Number, default: 0 },
    /**
     * Cache des 50 versements les plus récents. La collection `Versement`
     * porte l'historique complet — voir le commit b9f7087 : un document
     * Firestore plafonnait à 1 Mo et l'écriture aurait fini par être
     * rejetée en silence. La borne est conservée ici par cohérence, même
     * si MongoDB tient 16 Mo.
     */
    versements: { type: [VersementCacheSchema], default: [] },

    createdAt: { type: Date, default: Date.now },
    /**
     * Suppression douce. Absent, `null` ou une date — les trois existent en
     * base. Le filtre reste explicite dans les requêtes : un index partiel
     * sur `deletedAt: null` exclurait les dossiers où le champ est absent.
     */
    deletedAt: { type: Date, default: null },
  },
  options
);

PatientSchema.index({ parentUid: 1, deletedAt: 1 });
// Recherche par nom dans les listes.
PatientSchema.index({ parentUid: 1, nom: 1, prenom: 1 });

// ---------------------------------------------------------------------
//  Les documents médicaux — anciennement forms
// ---------------------------------------------------------------------

const FormSchema = new Schema(
  {
    parentUid: { type: Types.ObjectId, ref: 'Cabinet', required: true, index: true },
    patientId: { type: Types.ObjectId, ref: 'Patient', required: true, index: true },
    auteurProfileId: { type: Types.ObjectId, ref: 'Profile', default: null },

    type: {
      type: String,
      required: true,
      // Valeurs telles qu'écrites par l'app. `consultation_page.dart` les
      // compare littéralement pour savoir ce qui a été rédigé aujourd'hui.
      enum: [
        'Dossier initial',
        'Consultation',
        'Ordonnance medecin',
        'Demande de bilan',
        'Formulaire medecin',
      ],
    },
    contenu: { type: String, default: '' },

    // Consultation : mesures typées, écrites en plus du texte pour que
    // l'historique les relise sans reparser.
    poids: { type: Number, default: null },
    taille: { type: Number, default: null },
    imc: { type: String, default: '' },
    notes: { type: String, default: '' },

    // Formulaire médecin : bloc de champs libres, forme conservée telle
    // quelle. Les figer en schéma imposerait une migration à chaque
    // question ajoutée au questionnaire.
    sections: { type: Schema.Types.Mixed, default: undefined },

    // Ordonnance et bilan.
    prescriptions: { type: [Schema.Types.Mixed], default: undefined },
    examens: { type: [Schema.Types.Mixed], default: undefined },
    ordonnanceNumero: { type: String, default: '' },

    /**
     * Le numéro de séance existait sous cinq orthographes en base
     * (`seanceNumero`, `seanceNumber`, `numeroSeance`, `seance_numero`,
     * `noteSeance`). L'import les rabat toutes sur ces deux champs-ci.
     */
    seanceNumero: { type: String, default: '' },
    note_de_seance: { type: String, default: '' },

    createdAt: { type: Date, default: Date.now, index: true },
  },
  options
);

FormSchema.index({ patientId: 1, createdAt: -1 });
FormSchema.index({ patientId: 1, type: 1, createdAt: -1 });

// ---------------------------------------------------------------------
//  Versements
// ---------------------------------------------------------------------

const VersementSchema = new Schema(
  {
    parentUid: { type: Types.ObjectId, ref: 'Cabinet', required: true, index: true },
    patientId: { type: Types.ObjectId, ref: 'Patient', required: true, index: true },
    auteurProfileId: { type: Types.ObjectId, ref: 'Profile', default: null },
    doctorId: { type: Types.ObjectId, ref: 'Profile', default: null, index: true },

    montant: { type: Number, required: true },
    dayKey: { type: String, default: '', index: true },
    createdAt: { type: Date, default: Date.now, index: true },
  },
  options
);

// ---------------------------------------------------------------------
//  Le parcours — étapes partagées par les rendez-vous et la file
// ---------------------------------------------------------------------

const ETAPES = [
  'planifie',
  'confirme',
  'arrive',
  'en_cours',
  'honore',
  'absent',
  'annule',
];

const RendezVousSchema = new Schema(
  {
    parentUid: { type: Types.ObjectId, ref: 'Cabinet', required: true, index: true },
    patientId: { type: Types.ObjectId, ref: 'Patient', required: true, index: true },
    doctorId: { type: Types.ObjectId, ref: 'Profile', required: true, index: true },
    assistantId: { type: Types.ObjectId, ref: 'Profile', default: null, index: true },

    // Dénormalisés à dessein : les listes affichent le nom sans charger le
    // dossier, exactement comme le faisait Firestore.
    patientNom: { type: String, default: '' },
    patientPrenom: { type: String, default: '' },
    patientTel: { type: String, default: '' },
    doctorName: { type: String, default: '' },

    motif: { type: String, default: '' },
    datetime: { type: Date, required: true, index: true },
    /**
     * Durée en minutes. Sans elle, une consultation d'une heure laisserait
     * libres des créneaux qu'elle occupe.
     */
    duree: { type: Number, default: 20 },

    etape: { type: String, enum: ETAPES, default: 'planifie', index: true },
    motifAnnulation: { type: String, default: '' },
    // Un horodatage par étape franchie : savoir *quand* un patient est
    // arrivé est ce qui permettra plus tard de mesurer une attente réelle.
    etapesAt: { type: Schema.Types.Mixed, default: () => ({}) },

    reminderTemplate: { type: String, default: '' },
    reminderSentAt: { type: Date, default: null },

    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: null },
  },
  options
);

// La requête du sélecteur de créneaux : la journée d'un médecin.
RendezVousSchema.index({ doctorId: 1, datetime: 1 });

const WaitingSchema = new Schema(
  {
    parentUid: { type: Types.ObjectId, ref: 'Cabinet', required: true, index: true },
    patientId: { type: Types.ObjectId, ref: 'Patient', required: true, index: true },
    doctorId: { type: Types.ObjectId, ref: 'Profile', default: null, index: true },
    assistantId: { type: Types.ObjectId, ref: 'Profile', default: null, index: true },
    rdvId: { type: Types.ObjectId, ref: 'RendezVous', default: null },

    patientNom: { type: String, default: '' },
    patientPrenom: { type: String, default: '' },
    doctorName: { type: String, default: '' },
    assistantName: { type: String, default: '' },
    motif: { type: String, default: '' },

    nombreSeances: { type: Number, default: null },
    seancesEffectuees: { type: Number, default: null },

    etape: {
      type: String,
      enum: ['arrive', 'en_cours', 'honore', 'annule'],
      default: 'arrive',
      index: true,
    },
    /**
     * L'ancien vocabulaire, conservé.
     *
     * Les entrées existantes ne portent que `status`. Cesser de l'écrire
     * rendrait illisible la file en cours au moment de la bascule.
     */
    status: {
      type: String,
      enum: ['waiting', 'in_consultation', 'done', 'cancelled'],
      default: 'waiting',
    },

    createdAt: { type: Date, default: Date.now, index: true },
    inConsultationAt: { type: Date, default: null },
    closedAt: { type: Date, default: null },
  },
  options
);

// « Ce patient a-t-il déjà une entrée ouverte ? » — le garde-fou contre les
// doublons dans la file.
WaitingSchema.index({ parentUid: 1, patientId: 1, closedAt: 1 });

// ---------------------------------------------------------------------
//  Achats et statistiques
// ---------------------------------------------------------------------

const PurchaseSchema = new Schema(
  {
    parentUid: { type: Types.ObjectId, ref: 'Cabinet', required: true, index: true },
    profileId: { type: Types.ObjectId, ref: 'Profile', default: null, index: true },
    produit: { type: String, default: '' },
    fournisseur: { type: String, default: '' },
    montant: { type: Number, default: 0 },
    dayKey: { type: String, default: '', index: true },
    createdAt: { type: Date, default: Date.now },
  },
  options
);

const DailyStatSchema = new Schema(
  {
    parentUid: { type: Types.ObjectId, ref: 'Cabinet', required: true, index: true },
    dayKey: { type: String, required: true },
    date: { type: Date, default: null },

    versementsTotal: { type: Number, default: 0 },
    versementsCount: { type: Number, default: 0 },
    achatsTotal: { type: Number, default: 0 },
    achatsCount: { type: Number, default: 0 },

    // `{ doctorId: { name, total, count } }`, tel quel.
    doctorVersements: { type: Schema.Types.Mixed, default: () => ({}) },

    updatedAt: { type: Date, default: Date.now },
  },
  options
);

DailyStatSchema.index({ parentUid: 1, dayKey: 1 }, { unique: true });

// ---------------------------------------------------------------------
//  Journal d'erreurs — était à la racine, hors cabinet
// ---------------------------------------------------------------------

const ErrorLogSchema = new Schema(
  {
    // Nullable : une erreur peut survenir avant toute connexion.
    parentUid: { type: Types.ObjectId, ref: 'Cabinet', default: null, index: true },
    message: { type: String, default: '' },
    stack: { type: String, default: '' },
    context: { type: String, default: '' },
    origin: { type: String, default: '' },
    platform: { type: String, default: '' },
    osVersion: { type: String, default: '' },
    appVersion: { type: String, default: '' },
    createdAt: { type: Date, default: Date.now, index: true },
  },
  options
);

module.exports = {
  ETAPES,
  Cabinet: mongoose.model('Cabinet', CabinetSchema),
  Profile: mongoose.model('Profile', ProfileSchema),
  Patient: mongoose.model('Patient', PatientSchema),
  Form: mongoose.model('Form', FormSchema),
  Versement: mongoose.model('Versement', VersementSchema),
  RendezVous: mongoose.model('RendezVous', RendezVousSchema),
  Waiting: mongoose.model('Waiting', WaitingSchema),
  Purchase: mongoose.model('Purchase', PurchaseSchema),
  DailyStat: mongoose.model('DailyStat', DailyStatSchema),
  ErrorLog: mongoose.model('ErrorLog', ErrorLogSchema),
};
