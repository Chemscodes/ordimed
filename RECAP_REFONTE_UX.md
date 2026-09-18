# Ordimed — Recap session + Plan refonte UX patient

## Ce qui a ete fait dans les sessions precedentes

### 1. Fix "Chargement impossible"
- **Probleme** : L'ecran de selection de profils affichait "Chargement impossible" sans detail.
- **Cause** : `profilsFlux()` dans `firebase_cabinet_backend.dart` ne traduisait pas les erreurs Firestore.
- **Fix** : Ajout de `.handleError((e) => throw FirebaseRefs.traduire(e))` sur le stream, et affichage du vrai message d'erreur dans `profile_selector_page.dart`.

### 2. Fix ecran noir au demarrage
- **Probleme** : L'app se lançait sur un ecran noir.
- **Cause** : `restaurer()` dans `firebase_auth_backend.dart` ne catchait que `FirebaseException` avec code `'unavailable'`. Quand les rules Firestore n'etaient pas deployees, `permission-denied` crashait avant `runApp()`.
- **Fix** : Catch de toutes les `FirebaseException` (pas juste `unavailable`).

### 3. Deploiement des Firestore rules
- Les regles de securite dans `firestore.rules` etaient correctes mais jamais deployees.
- Deploye avec `firebase deploy --only firestore:rules` sur le projet `chems21-3dbe3`.

### 4. Migration des donnees (ancien chemin → nouveau)
- **Probleme** : Les donnees du cabinet `medjekane@gmail.com` n'apparaissaient plus apres le refactor d'architecture.
- **Cause** : L'ancien chemin etait `users/{uid}/comptes/{profileId}/patients/...`, le nouveau est `cabinets/{uid}/patients/...` avec champ `doctorId`.
- **Solution** : Creation de `lib/pages/migration_page.dart` — page accessible depuis le selecteur de profils (bouton sync) qui copie les donnees de l'ancien chemin vers le nouveau sans ecraser l'existant.
- **Statut** : La page est prete, mais la migration n'a pas encore ete lancee pour le compte `medjekane@gmail.com`.

### 5. Architecture mise en place
- Backend hybride Firebase/MongoDB switchable via `BackendConfig`
- `CabinetBackend` : interface abstraite avec 48 methodes
- `FirebaseCabinetBackend` et `MongoCabinetBackend` : implementations
- `ApiService` : facade qui delegue au backend actif
- `main.cpp` : self-relaunch avec `--enable-software-rendering`

---

## Plan de refonte UX patient (approuve, pas encore implemente)

### Principe directeur
**Aucune donnee ni logique metier ne change.** On reorganise l'affichage, on extrait des widgets, on remplace des dialogues par des pages.

### Ordre d'implementation

#### Etape 1 — Extraire l'infra PDF (`lib/services/pdf_service.dart`)
- Extraire de `patient_details_page.dart` : `_buildMedicalPdfBytes`, `_resolvePdfFonts`, `_writePdfTemp`, `_openPdfInBrowser`, `_printOrdonnancePdf`, `_printBilanPdf`, `_PdfFonts`, `_sanitizeFileName`
- Prerequis pour l'etape 2

#### Etape 2 (B) — Ordonnances et bilans en plein ecran
- Convertir `_openOrdonnanceDialog` (~510 lignes) et `_openBilanDialog` (~420 lignes) de `AlertDialog` en pages completes
- Layout cote a cote : formulaire a gauche, preview PDF live a droite
- Nouveaux fichiers : `lib/pages/ordonnance_page.dart`, `lib/pages/bilan_page.dart`
- `Navigator.push` au lieu de `showDialog`

#### Etape 3 (A) — Dossier patient en onglets lateraux
- Remplacer le scroll infini de `PatientDetailsPage` (4400 lignes) par sidebar gauche + contenu a droite
- 6 onglets : Resume, Consultations, Ordonnances, Bilans, Paiements, Infos
- Eclater le fichier en ~7 fichiers sous `lib/pages/dossier/`
- `patient_details_page.dart` reduit de ~4400 a ~200 lignes

#### Etape 4 (C) — Barre de statut patient contextuelle
- Barre coloree en haut du dossier patient selon le statut
- 4 etats : pas en salle (gris), en attente (ambre), en consultation (menthe), terminee (gris)
- Nouveau fichier : `lib/widgets/patient_status_bar.dart`

#### Etape 5 (D) — KPIs en temps reel sur les dashboards
- Rangee de 4 tuiles : Patients du jour, En attente, En consultation, Recettes du jour
- Nouveau fichier : `lib/widgets/kpi_row.dart`
- Integration dans les 3 dashboards (principal, medecin, assistant)

#### Etape 6 (E) — Liste patients avec statut visuel
- Pastille coloree par patient selon le paiement (vert=solde, orange=partiel, rouge=impaye, gris=pas de prix)
- Date relative de derniere visite sous le nom
- Nouveau fichier : `lib/widgets/patient_status_indicator.dart`

#### Etape 7 (F) — Consultation sans popup
- A l'etape "Conclusion" de `ConsultationPage`, naviguer vers les pages plein ecran (etape 2) au lieu d'ouvrir un dialog
- Deja resolu par l'etape 2, juste changer les callbacks

---

## Statut actuel

- **Etape 1** (extraction PDF) : FAIT.
- **Etape 2** (ordonnance/bilan en pages plein ecran) : FAIT (session du 2026-09-14). `_openOrdonnanceDialog` et `_openBilanDialog` (AlertDialog, ~930 lignes cumulees) supprimes de `patient_details_page.dart`, remplaces par `lib/pages/ordonnance_page.dart` et `lib/pages/bilan_page.dart` (StatefulWidget, layout formulaire/preview cote a cote via `LayoutBuilder`, repli vertical sous 900px). `PatientDetailsPage.ouvrirOrdonnance` / `.ouvrirBilan` font desormais `Navigator.push` vers ces pages (signature simplifiee : `parentUid` retire, plus necessaire). `consultation_page.dart` et le bouton "Nouvelle ordonnance/bilan" de l'onglet Documents mis a jour en consequence. Logique metier inchangee (memes appels `ApiService`, mise a jour profil medecin, generation PDF).
- **Etape 3** (dossier patient en onglets lateraux) : FAIT (build corrige, voir `CONTEXTE_SESSION.md` section 8).
- **Etape 4** (barre de statut patient contextuelle) : FAIT (session du 2026-09-14). Nouveau `lib/widgets/patient_status_bar.dart` — lit `ApiService.instance.salleAttenteFlux()` (meme flux que les dashboards), retrouve l'entree du patient du jour et affiche une des 4 teintes : gris "Pas en salle", ambre "En salle d'attente", menthe "En consultation", gris "Visite terminee". Regles de statut identiques a celles deja utilisees dans `dashboard_medecin.dart`/`dashboard_assistant.dart`/`dashboard_principale.dart` (`status == 'in_consultation'`, sinon `closedAt != null` ou `status == 'done'` -> termine, sinon en attente). Integree en haut de `PatientDetailsPage` (au-dessus de la sidebar+contenu).
- **Etape 5** (KPIs temps reel sur les dashboards) : FAIT (session du 2026-09-14). Nouveau `lib/widgets/kpi_row.dart` — rangee de 4 tuiles (Patients du jour, En attente, En consultation, Recettes du jour), responsive (Row sur 4 colonnes >=900px, grille 2x2 entre 500 et 900px, empilee en dessous). Patients/attente/consultation viennent de `ApiService.instance.salleAttenteFlux()` (meme regle `status`/`closedAt` que les dashboards). Recettes du jour reutilise `sommeVersementsDuJour()`, extraite de `DailyVersementsCard` (qui l'utilise aussi desormais) pour eviter de dupliquer ce calcul. Remplace, dans les 3 dashboards, les paires de cartes statiques sans donnees ("Suivi actif"/"Rendez-vous" chez le medecin, "Profils"/"Reporting" chez le principal) et l'ancien `DailyVersementsCard` isole (assistant) : `dashboard_medecin.dart`, `dashboard_principale.dart`, `dashboard_assistant.dart`.
- **Etape 6** (liste patients avec statut visuel) : FAIT (session du 2026-09-14). Nouveau `lib/widgets/patient_status_indicator.dart` — pastille de paiement (vert "Solde" si `totalVersements >= prix`, ambre "Partiel", corail "Impaye", gris "Sans prix" si le patient n'a pas de `prix`) + date relative de derniere visite via `fmt.relativeDay()` (helper deja existant dans `core/format.dart`). Reutilise `Versement.fromMap`/`totalDe` de `core/versements.dart`, memes primitives que le dossier patient. La « derniere visite » est approchee par la date du versement le plus recent (le tableau `versements` du patient est deja trie du plus recent au plus ancien), et par la date de creation du dossier si le patient n'a encore aucun versement — il n'existe pas de champ dedie « derniere visite » dans le modele de donnees actuel. Integre sous le nom dans les 3 listes de patients : `lib/pages/PatientsPage.dart` (principal), et les `_PatientsTab` de `dashboard_medecin.dart` et `dashboard_assistant.dart`.
- **Etape 7** (consultation sans popup) : FAIT — deja resolue par l'etape 2. Verifie le 2026-09-14 : `consultation_page.dart` ne contient plus aucun `showDialog` ; `_rediger()` (etape « Conclusion ») navigue vers `OrdonnancePage`/`BilanPage` via `PatientDetailsPage.ouvrirOrdonnance`/`.ouvrirBilan`. Rien a changer.

## Les 7 etapes sont terminees (session du 2026-09-14).
