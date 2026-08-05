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

Application Flutter compilée en natif pour Windows, branchée directement sur Firebase
(authentification + base temps réel). Pas de serveur intermédiaire à administrer : le
cabinet installe l'application et les postes se synchronisent entre eux.

Toutes les listes sont des flux temps réel — quand l'assistant inscrit un patient, la
salle d'attente du médecin se met à jour sans rafraîchissement.

### Modèle de données (Cloud Firestore)

```
users/{cabinet}
 ├── comptes/{profil}            rôle, code d'accès, en-tête d'ordonnance
 │    ├── patients/{patient}     identité, forfait, versements, séances
 │    │    └── forms/{document}  bilans, ordonnances, formulaires
 │    ├── salle_attente/{ligne}  en attente · en consultation · reçu
 │    ├── rendezvous/{rdv}       date, motif, rappel envoyé
 │    └── purchases/{achat}      dépenses du cabinet
 └── daily_stats/{jour}          recettes, achats, net, détail par médecin
```

Firestore ne fait pas de jointures : les documents partagés (patient, ligne de salle
d'attente, rendez-vous) sont écrits en une copie par profil concerné, via des écritures
groupées atomiques. Chaque poste lit ainsi uniquement sa propre branche.

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
│   ├── auth_service.dart        authentification Firebase
│   ├── firestore_service.dart   flux patients, rendez-vous, documents
│   ├── waiting_service.dart     salle d'attente partagée
│   ├── rendezvous_repository.dart  planification des rendez-vous
│   └── stats_service.dart       agrégats financiers journaliers
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
- Un projet [Firebase](https://console.firebase.google.com) avec Authentication (e-mail/mot de passe) et Cloud Firestore activés

### Mise en route

```bash
git clone <url-du-depot>
cd ordimed
flutter pub get
```

Configurer Firebase pour le projet :

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Déployer les index Firestore (nécessaire au bon fonctionnement des écrans financiers) :

```bash
firebase deploy --only firestore:indexes
```

Lancer :

```bash
flutter run -d windows
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
