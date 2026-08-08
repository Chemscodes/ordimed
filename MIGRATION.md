# Migration Firebase → Node.js / MongoDB

## Étape 1 — Inventaire du modèle Firestore

Relevé sur le code, pas de mémoire. 55 fichiers Dart, 22 651 lignes.

---

### 1.1 Arborescence réelle

Firestore est hiérarchique ; MongoDB est plat. Voici les chemins tels
qu'ils existent :

```
users/{uid}                                     ← le cabinet
  └── comptes/{profileId}                       ← médecin / assistant
        ├── patients/{patientId}
        │     ├── forms/{formId}
        │     └── versements/{versementId}
        ├── rendezvous/{rdvId}
        ├── salle_attente/{waitingId}
        ├── purchases/{achatId}
        └── daily_stats/{dayKey}
error_logs/{logId}                              ← racine, hors cabinet
```

**`tmp` n'est pas une collection.** `collection('tmp').doc().id` sert
uniquement à générer un identifiant côté client, sans jamais rien écrire.
8 occurrences. En MongoDB c'est `new mongoose.Types.ObjectId()` — surtout
ne pas créer de modèle `Tmp`.

---

### 1.2 La duplication en éventail

Un patient n'existe pas une fois : il est écrit **à l'identique** sous le
profil du médecin **et** sous celui de l'assistant. Une entrée de salle
d'attente est écrite **trois fois** (médecin, assistant, médecin principal).
Un rendez-vous aussi.

C'est un contournement : Firestore ne sait pas joindre, et une requête
« tous les patients de ce médecin » depuis le profil de l'assistant serait
impossible autrement.

**MongoDB n'a pas cette limite.** Garder la duplication — comme le demande
la règle 1 — signifie porter 21 écritures par lot (`batch`) qui n'ont plus
de raison d'être. Le coût est réel :

- chaque écriture patient devient 2 documents, chaque salle d'attente 3 ;
- une incohérence entre copies devient possible et invisible ;
- 8 `collectionGroup` existent uniquement pour recoller les morceaux.

La recommandation, à trancher avant l'étape 3 : **un seul document par
entité**, avec `parentUid` + `doctorId` + `assistantId` comme index. Les
mêmes écrans, les mêmes requêtes, un tiers des écritures. Dis-moi si tu
préfères la fidélité littérale ; je suivrai ta règle si tu la maintiens.

---

### 1.3 Les collections, champ par champ

Les types viennent de ce que le code écrit **et** de ce qu'il tolère à la
lecture : plusieurs champs sont hétérogènes en base parce qu'ils ont changé
de type en cours de route.

#### `users/{uid}` — le cabinet

| champ | type | note |
|---|---|---|
| `email` | string | |
| `createdAt` | timestamp | |
| `horaires` | objet | `{ouverture, fermeture, pauseDebut, pauseFin, duree, joursOuvres[]}`, en minutes depuis minuit. Absent sur les cabinets existants. |

#### `comptes/{profileId}` — un profil

| champ | type | note |
|---|---|---|
| `name` | string | |
| `role` | string | `medecin_principal` \| `medecin` \| `assistant` |
| `pin` | string | **en clair**, comparé côté client |
| `createdAt` | timestamp | |
| `wilaya`, `address`/`adresse`, `tel` | string | en-têtes des PDF |
| `whatsappTemplate`, `whatsappTemplateUpdatedAt` | string / timestamp | |

Le profil `medecin_principal` a un identifiant **fixe** : du code le
référence en dur (`base.doc('medecin_principal')`). Les autres ont un id
auto-généré.

#### `patients/{patientId}`

Identité : `nom`, `prenom`, `age`, `tel`, `email`, `origine`
Motif : `motifs[]` (liste) **et** `motif` (string jointe par `, ` — les deux
sont écrits, plusieurs vues ne lisent que le second)
Affectation : `doctorId`, `assistantId`, `assistantName`,
`assignedMedecinName`, `createdByAssistantProfileId`, `profileId`,
`parentUid`
Clinique : `poids_actuel`, `taille`, `imc`, `derniereConsultation`
Forfait : `nombreSeances`, `seancesEffectuees`
Argent : `prix`, `totalVersements`, `versements[]`
Cycle : `createdAt`, `deletedAt`

**Pièges de typage, tous réels en base :**

- `age` : entier depuis peu, **chaîne** sur tous les dossiers antérieurs.
- `prix` : `number` ou `string` selon l'écran qui l'a saisi.
- `imc` : **chaîne** (`"23,7"`, virgule décimale), pas un nombre.
- `deletedAt` : absent, `null`, ou date. Le filtre est **côté client** — un
  `where('deletedAt', null)` masquerait tous les dossiers antérieurs à la
  suppression douce.
- `versements[]` : borné aux 50 plus récents depuis `b9f7087`. La
  sous-collection porte l'historique. **Les deux doivent être migrés.**

#### `forms/{formId}` — documents médicaux

| champ | type | note |
|---|---|---|
| `type` | string | `Dossier initial`, `Consultation`, `Ordonnance medecin`, `Demande de bilan`, `Formulaire medecin` |
| `contenu` | string | texte formaté, avec `\n` |
| `createdAt`, `auteurProfileId`, `parentUid`, `patientId` | | |
| `poids`, `taille`, `imc`, `notes` | | consultations récentes, typés |
| `sections` | **objet imbriqué** | formulaire médecin : `pathologies_chroniques`, `allergies`, `antecedents_digestifs`, `sommeil`, `activite_physique`, `stress_anxiete`, `tabac_alcool_cafeine`, `hydratation`, `repas_par_jour`, `grignotage`, `comportement_alimentaire`, `compulsions`, `gouts_aversions`, `restrictions`, `organisation_repas`, `journee_type`, `evolution_poids`, `poids_souhaite`, `objectifs_court_terme`, `objectifs_long_terme`, `attentes_consultation`, `image_corporelle`, `influence_entourage`, `tour_taille_hanche`, `complement` |
| `prescriptions[]`, `examens[]` | tableaux d'objets | `{name, qte, checked}` |
| `seanceNumero`, `ordonnanceNumero`, `note_de_seance` | | |

Le numéro de séance existe sous **cinq orthographes** en base :
`seanceNumero`, `seanceNumber`, `numeroSeance`, `seance_numero`,
`noteSeance`/`note_de_seance`. Toutes doivent être lues.

#### `rendezvous/{rdvId}`

`rdvId`, `patientId`, `patientNom`, `patientPrenom`, `patientTel`,
`doctorId`, `doctorName`, `assistantId`, `motif`, `datetime`, `duree`,
`createdAt`, `updatedAt`, `parentUid`, `reminderTemplate`,
`reminderSentAt`, `etape`, `motifAnnulation`, et un horodatage par étape
franchie (`confirmeAt`, `arriveAt`, `honoreAt`, `absentAt`…).

`etape` ∈ `planifie` `confirme` `arrive` `en_cours` `honore` `absent`
`annule`. **Absent des rendez-vous antérieurs** → lus comme `planifie`.

#### `salle_attente/{waitingId}`

`waitingId`, `patientId`, `patientNom`, `patientPrenom`, `assistantId`,
`assistantName`, `doctorId`, `doctorName`, `motif`, `rdvId`,
`nombreSeances`, `seancesEffectuees`, `createdAt`, `inConsultationAt`,
`closedAt`, `parentUid`, `status`, `etape`.

**Deux vocabulaires coexistent** : `status` (`waiting`, `in_consultation`,
`done`, `cancelled`/`canceled`) et `etape` (le nouveau). Les deux sont
écrits ; la lecture préfère `etape` et retombe sur `status`. La migration
doit conserver les deux, sinon les entrées existantes deviennent illisibles.

#### `versements/{id}` (sous-collection du patient)

`montant` (number), `createdAt`, `dayKey` (`YYYY-MM-DD`),
`auteurProfileId`, `parentUid`.

#### `purchases/{achatId}`

`produit`, `fournisseur`, `montant`, `dayKey`, `profileId`, `parentUid`,
`createdAt`.

#### `daily_stats/{dayKey}`

`date`, `dayKey`, `versementsTotal`, `versementsCount`, `achatsTotal`,
`achatsCount`, `doctorVersements` (objet `{doctorId: {name, total, count}}`),
`updatedAt`. Document agrégé, mis à jour par incréments.

#### `error_logs/{logId}` — racine

`message`, `stack`, `context`, `origin`, `platform`, `osVersion`,
`appVersion`, `createdAt`.

---

### 1.4 Ce que Firebase Auth fournit réellement

Quatre appels, pas un de plus :

- `createUserWithEmailAndPassword`
- `signInWithEmailAndPassword`
- `signOut`
- `currentUser?.uid`

**Pas de réinitialisation de mot de passe, pas de vérification d'e-mail,
pas de fournisseur tiers.** La surface JWT à écrire est donc petite :
`POST /auth/register`, `POST /auth/login`, un middleware.

Le second niveau — le **PIN de profil** — n'est pas de l'authentification
Firebase : c'est une comparaison de chaînes côté client
(`pinCtrl.text != data['pin']`). Le passer côté serveur est un gain de
sécurité gratuit au passage.

---

### 1.5 Firebase Storage : rien à migrer

`pubspec.yaml` ne déclare que `firebase_core`, `firebase_auth` et
`cloud_firestore`. **Aucun `firebase_storage`, aucun upload.**

Les seuls fichiers produits — PDF d'ordonnance, reçus, sauvegardes, journal
d'erreurs — sont déjà écrits sur le disque local du poste et n'ont jamais
transité par Firebase.

Le volet « Storage → Multer `/uploads` » du cahier des charges **n'a donc
pas d'objet**. Je peux poser l'échafaudage Multer pour un usage futur, mais
rien du projet actuel n'y passera. À toi de dire si tu le veux quand même.

---

### 1.6 Ce qui ne se traduit pas en REST

C'est le vrai travail de cette migration, et il ne se voit pas dans un
schéma Mongoose.

| Firestore | occurrences | équivalent Node |
|---|---|---|
| `.snapshots()` temps réel | **27** | Socket.IO, ou polling |
| `StreamBuilder` | **30** | idem |
| `batch()` atomique | **21** | transactions MongoDB (⚠ replica set requis) |
| `collectionGroup` | **8** | requête simple, la hiérarchie disparaît |
| `FieldValue.serverTimestamp()` | **28** | `new Date()` **côté serveur** |
| `FieldValue.increment()` | **8** | `$inc` |
| persistance hors-ligne | globale | **rien d'équivalent** |

Trois points méritent d'être décidés maintenant :

1. **Le temps réel n'est pas décoratif.** L'assistant met un patient en
   salle, l'écran du médecin change seul. Sans Socket.IO, la salle
   d'attente cesse d'être partagée — c'est une perte de fonctionnalité, pas
   un détail d'implémentation.

2. **Les transactions MongoDB exigent un replica set.** Un `mongo:7` seul
   dans `docker-compose` ne les supporte pas. Il faut lancer avec
   `--replSet` et initier, sinon les 21 écritures atomiques deviennent des
   suites d'écritures pouvant échouer à moitié.

3. **Le hors-ligne disparaît.** Aujourd'hui le cabinet fonctionne quand
   Internet tombe. En REST, la coupure arrête le travail. Si le cabinet est
   sur une connexion incertaine, il faut une file d'attente locale côté
   Flutter — c'est un chantier à part entière.

---

### 1.7 Ce que je propose pour la suite

- **Étape 2** — inventorier les appels Firebase côté Flutter et les
  regrouper en surface d'API (le fichier de correspondance route ↔ écran).
- **Étape 3** — schémas Mongoose.
- **Étape 4** — routes Express + middleware JWT.
- **Étape 5** — `docker-compose` (Mongo en replica set, backend, volume
  `uploads`).
- **Étape 6** — `api_service.dart` côté Flutter.

Avant l'étape 3, deux réponses me sont nécessaires :

1. **Duplication** : fidélité littérale, ou un document par entité ?
2. **Temps réel** : Socket.IO, polling, ou on accepte la perte ?
