# Ordimed

**Logiciel de gestion de cabinet médical pour Windows.**
De l'accueil du patient à l'ordonnance imprimée, en passant par la salle d'attente,
les séances, les règlements et la caisse du jour.

Conçu et développé par **Zaouali Chems Eddine**.

`Flutter` · `Dart` · `Firebase Auth` · `Cloud Firestore` · `PDF / impression`

**→ [Voir la présentation du projet](https://ordimedev.netlify.app/)**

---

## Le problème

Un cabinet médical fonctionne à trois postes, pas à un seul. L'assistant accueille et
encaisse, le médecin consulte et prescrit, le directeur veut savoir ce que la journée a
rapporté. Les trois travaillent sur le même patient, en même temps, et chacun a besoin
d'une vue différente.

La plupart des cabinets tiennent ça sur un cahier et un tableur : le patient est réinscrit
à chaque passage, les séances se comptent de tête, et personne ne sait le soir combien la
caisse a fait. Ordimed remplace l'ensemble par un poste de travail par rôle, sur une base
de données partagée qui se met à jour en direct.

## Fonctionnalités

### Accès à deux niveaux

Un compte unique par cabinet (e-mail + mot de passe). À l'intérieur, chaque personne a son
profil protégé par un code PIN : on choisit son profil au démarrage, on entre son code, et
l'application s'ouvre sur le poste correspondant.

### Trois postes de travail

| Poste | Ce qu'il fait |
|---|---|
| **Assistant** | Création des dossiers patients, salle d'attente, encaissement des versements, planification et rappels de rendez-vous, achats du cabinet |
| **Médecin** | Ses patients et sa salle d'attente, formulaires médicaux personnalisables, ordonnances et bilans imprimables, suivi des séances |
| **Directeur** | Tous les patients, caisse du jour, achats, résultat net, détail par médecin, courbe hebdomadaire, gestion des profils |

### Le parcours patient

1. **Accueil** — l'assistant ouvre le dossier (identité, motif, médecin attribué) ; il apparaît immédiatement chez le médecin choisi
2. **Salle d'attente** — le patient entre en file, visible en direct par les trois postes ; un même patient ne peut pas y figurer deux fois
3. **Consultation** — le médecin remplit le formulaire, édite l'ordonnance ou le bilan et l'imprime ; la séance est décomptée du forfait
4. **Règlement** — le versement est enregistré, le reste à payer se recalcule, la recette du jour se met à jour dans la seconde
5. **Clôture** — un bouton ferme toute la file ; le directeur lit la caisse et le net sans rien ressaisir

### Documents générés

- **Ordonnances bilingues** — en-tête du praticien en français et en arabe (nom, spécialité, wilaya, adresse, téléphone), numérotation automatique, export PDF et impression directe
- **Bilans et formulaires médicaux** — antécédents, habitudes de vie, mesures, objectifs ; chaque médecin définit ses propres modèles de champs réutilisables
- **Rappels de rendez-vous** — message type paramétrable, envoyé au patient via WhatsApp en un clic

### Suivi financier

Versements encaissés, achats engagés, résultat net du jour, ventilation par médecin et
courbe des sept derniers jours. Montants en dinars algériens.

### Autres

- Thème clair et sombre sur l'ensemble de l'interface
- Motifs de consultation configurables par cabinet
- Files d'attente auto-nettoyées après 24 h
- Mode allégé (`--lite`) pour les postes anciens : désactive les polices distantes et les transitions d'écran

---

## Architecture

Application Flutter compilée en natif pour Windows, capable de fonctionner sur **deux
bases au choix**. Le cabinet décide laquelle à l'installation, depuis l'écran de
connexion ; le reste de l'application ne sait pas laquelle répond.

| | **Firebase** (par défaut) | **Serveur du cabinet** |
|---|---|---|
| À installer | rien | un poste qui fait tourner le backend Node |
| Données | Firestore | MongoDB, chez le cabinet |
| Temps réel | `snapshots()`, poussé | Socket.IO, rechargement sur annonce |
| Hors ligne | cache local, le cabinet continue | serveur joignable ou pas |
| Logique métier | dans l'application | sur le serveur |

Toutes les listes sont des flux temps réel des deux côtés — quand l'assistant inscrit un
patient, la salle d'attente du médecin se met à jour sans rafraîchissement.

### Ce qui rend la bascule possible

Un seul contrat, [`CabinetBackend`](lib/services/cabinet_backend.dart), que les deux
implémentations respectent. `ApiService` choisit l'une ou l'autre selon
[`BackendConfig`](lib/services/backend_config.dart), et les écrans n'importent que la
façade :

```
pages/  ──►  ApiService  ──►  CabinetBackend  ──┬─►  FirebaseCabinetBackend  ──►  Firestore
                                                └─►  MongoCabinetBackend     ──►  API Node
```

La contrainte qui fait tenir l'ensemble : **les deux backends rendent les mêmes clés**.
`id` pour l'identifiant, `createdAt` en ISO 8601, et les champs métier nommés comme les
modèles MongoDB. La conversion côté Firestore est faite au même endroit, dans
[`firebase_refs.dart`](lib/services/firebase/firebase_refs.dart).

### Modèle de données

À plat des deux côtés, avec les mêmes noms de champs.

```
cabinets/{cabinet}              horaires, motifs prédéfinis, listes de référence
 ├── profiles/{profil}          rôle, code d'accès haché, en-tête d'ordonnance
 ├── patients/{patient}         identité, forfait, versements, séances
 ├── forms/{document}           bilans, ordonnances, formulaires
 ├── versements/{versement}     historique complet des règlements
 ├── rendezvous/{rdv}           date, motif, étape, rappel envoyé
 ├── salle_attente/{ligne}      en attente · en consultation · reçu
 ├── purchases/{achat}          dépenses du cabinet
 └── daily_stats/{jour}         recettes, achats, net, détail par médecin
```

La première version Firestore était arborescente — `users/{uid}/comptes/{profil}/patients`
— et, faute de jointures, écrivait chaque patient deux fois et chaque ligne de salle
d'attente trois fois. Les copies finissaient par diverger en silence. `doctorId` et
`assistantId` sont désormais des champs filtrés à la requête : une seule copie, et le
même schéma des deux côtés.

### Ce que le sans-serveur coûte

Sur la branche Firebase, la logique métier redescend dans l'application. Trois choses
sont reconstruites à l'identique, une quatrième ne peut pas l'être :

- **écritures liées** (encaisser, clôturer) — `runTransaction`, réellement atomique ;
- **totaux de caisse** — `FieldValue.increment`, juste même à deux postes simultanés ;
- **code PIN** — haché en SHA-256, jamais stocké en clair. Mais la comparaison a lieu
  dans l'application : qui lit la base ne voit pas les codes, qui modifie le binaire peut
  contourner le contrôle. Côté Node, bcrypt sur le serveur ne laissait pas cette porte ;
- **conflits de créneaux** — détectés par une requête faite juste avant l'écriture, car
  Firestore ne sait pas requêter dans une transaction. Deux postes qui posent la même
  heure à la même seconde peuvent passer tous les deux.

Un cabinet très fréquenté gagne donc à rester sur le serveur local. Un cabinet qui ne
veut rien administrer prend Firebase et accepte ces quatre lignes.

### Organisation du code

```
lib/
├── main.dart                    initialisation Firebase, thèmes clair/sombre
├── app_router.dart              routes nommées
├── pages/
│   ├── login_page.dart          connexion cabinet
│   ├── signup_page.dart         création du cabinet
│   ├── profile_selector_page.dart   choix du profil + code PIN
│   ├── add_profile_page.dart    création d'un profil
│   ├── dashboard_assistant.dart poste d'accueil
│   ├── dashboard_medecin.dart   poste de consultation
│   ├── dashboard_principale.dart poste de direction
│   ├── add_patient_form.dart    création d'un dossier patient
│   ├── patient_details_page.dart dossier, ordonnances, bilans, PDF
│   └── stats_page.dart          statistiques du cabinet
├── services/
│   ├── backend_config.dart      quelle base, et comment en changer
│   ├── cabinet_backend.dart     le contrat que les deux respectent
│   ├── auth_backend.dart        le contrat d'ouverture de session
│   ├── api_service.dart         façade : choisit l'implémentation
│   ├── auth_service.dart        façade : choisit l'authentification
│   ├── firebase/
│   │   ├── firebase_cabinet_backend.dart  tout le métier sur Firestore
│   │   ├── firebase_auth_backend.dart     Firebase Auth
│   │   └── firebase_refs.dart             chemins et conversions
│   └── mongo/
│       ├── mongo_cabinet_backend.dart     appels à l'API Node
│       └── mongo_auth_backend.dart        jeton JWT et sa persistance
├── ui/                          composants et thème (AppShell, cartes, boutons)
└── widgets/                     cartes métier réutilisables
```

### Note d'ingénierie — performance à l'échelle

Chez les cabinets les plus chargés, l'écran de direction se figeait puis se fermait tout
seul. La cause : pour afficher la recette du jour, l'application téléchargeait
l'intégralité des dossiers patients et en additionnait les règlements à chaque
rafraîchissement — des milliers de documents parcourus sur le fil d'affichage.

Le correctif n'a pas consisté à optimiser la boucle mais à la supprimer : les totaux sont
désormais calculés **au moment de l'encaissement** et incrémentés dans un document par
journée (`daily_stats`), que les écrans se contentent de lire. Le coût d'affichage est
devenu constant, quel que soit le volume de la base.

Détail complet dans [`PERFORMANCE_FIX.md`](PERFORMANCE_FIX.md).

---

## Installation

### Prérequis

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.8.1 ou supérieur
- Visual Studio avec la charge de travail « Développement Desktop en C++ » (build Windows)

Selon la base retenue :

- **Firebase** — un projet [Firebase](https://console.firebase.google.com) avec
  Authentication (e-mail/mot de passe) et Cloud Firestore activés
- **Serveur du cabinet** — Node 18+ et MongoDB, sur le poste qui fera serveur

### Mise en route

```bash
git clone <url-du-depot>
cd ordimed
flutter pub get
```

#### Sur Firebase

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Déployer les règles de sécurité — elles sont ce qui empêche un cabinet de lire un autre,
rien ne fonctionne correctement sans elles :

```bash
firebase deploy --only firestore:rules
```

Aucun index composite n'est nécessaire : les requêtes sont mono-champ, servies par les
index automatiques de Firestore.

#### Sur le serveur du cabinet

```bash
cd backend
npm install
npm start
```

Les autres postes indiquent l'adresse de celui-ci depuis l'écran de connexion
(**Serveur → Modifier**).

### Lancer

```bash
flutter run -d windows
```

La base se choisit depuis l'écran de connexion, et le choix est retenu. Pour produire un
binaire destiné à un cabinet qui n'aura jamais à choisir, la figer à la compilation :

```bash
flutter run -d windows --dart-define=BACKEND=mongo
```

Mode allégé pour les postes anciens :

```bash
flutter run -d windows --dart-define=ULTRA_LITE=true
```

Compiler la version de production :

```bash
flutter build windows --release
```

---

## Licence

Projet privé. Tous droits réservés — Zaouali Chems Eddine.
