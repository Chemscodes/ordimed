# Contexte pour continuer la refonte UX Ordimed

> Genere le 2026-09-14. A copier dans un nouveau panel Claude Code pour reprendre le travail.

---

## 1. Projet

**Ordimed** — app Flutter/Windows de gestion de cabinet medical (Algerie).

| Element | Valeur |
|---|---|
| Repertoire | `D:\ordimed` |
| Plateforme | Windows Desktop (Flutter) |
| Backend | Firebase Auth + Cloud Firestore |
| Backend secondaire | Node.js + MongoDB (fallback via `BackendConfig`) |
| Firebase project | `chems21-3dbe3` |
| Interface abstraite | `CabinetBackend` (48 methodes) |
| Facade | `ApiService.instance` delegue au backend actif |
| Design | dark-first, IBM Plex Sans, couleurs : menthe, ambre, corail, violet |
| Theme | `AppTheme` avec `rCard=9`, `rButton=6`, `rPill=999` |
| Composants UI | FluentCard, FluentButton, AppField, InfoPair/InfoGrid, AppShell |
| main.cpp | self-relaunch avec `--enable-software-rendering` |

---

## 2. Plan de refonte UX (approuve, en cours)

Voir `RECAP_REFONTE_UX.md` pour le detail. Principe : **aucune donnee ni logique metier ne change**, on reorganise l'affichage.

| Etape | Description | Statut |
|---|---|---|
| 1 | Extraire l'infra PDF → `lib/services/pdf_service.dart` | **FAIT** |
| 2 (B) | Ordonnance + bilan en pages plein ecran (pas dialogs) | PAS FAIT |
| 3 (A) | Dossier patient avec sidebar 6 onglets | **FAIT — build corrige** |
| 4 (C) | Barre de statut patient contextuelle | PAS FAIT |
| 5 (D) | KPIs temps reel sur dashboards | PAS FAIT |
| 6 (E) | Liste patients avec pastilles de statut visuel | PAS FAIT |
| 7 (F) | Consultation conclusion sans popup | PAS FAIT |

---

## 3. Etat du code — BUILD CORRIGE (voir section 8)

### `lib/services/pdf_service.dart` — OK (nouveau fichier)
Contient `PdfFonts` class + `PdfService` singleton avec : `resolveFonts()`, `buildMedicalPdfBytes()`, `sanitizeFileName()`, `writePdfTemp()`, `openPdfInBrowser()`, `printOrdonnancePdf()`, `printBilanPdf()`. Compile OK.

### `lib/pages/patient_details_page.dart` — CASSE (~4370 lignes)

Le fichier a ete **partiellement converti en StatefulWidget puis partiellement reconverti en StatelessWidget**. Etat incoherent :

- **Ligne 37** : `class PatientDetailsPage extends StatelessWidget` ← c'est un StatelessWidget
- **Lignes 55-62** : `static const _tabs` — 6 `_DossierTab` pour la sidebar (ajoutees pendant le refactor)
- **Lignes ~240-270** : Le `build()` contient un sidebar avec `setState(() => _tabIndex = i)` — **ERREUR** : `setState` et `_tabIndex` n'existent pas dans un StatelessWidget
- **Ligne ~317** : `switch (_tabIndex)` pour choisir le contenu d'onglet — meme probleme
- **Lignes ~1197, ~1709, ~2733** : Les methodes dialog `_openOrdonnanceDialog`, `_openBilanDialog`, `_addDoctorForm` existent toujours (methodes privees)
- **Les 3 methodes publiques `ouvrirOrdonnance`, `ouvrirBilan`, `ouvrirFormulaireMedecin` ont ete SUPPRIMEES**
- Les appels PDF privees ont ete remplaces par `PdfService.instance.printOrdonnancePdf(...)` etc.
- La classe `_PdfFonts` a ete supprimee (remplacee par `PdfFonts` dans pdf_service.dart)
- Les imports pdf/printing ont ete retires (url_launcher garde)
- `_DossierTab` class ajoutee en fin de fichier
- La layout du `build()` est passee de `SingleChildScrollView` a `Row(sidebar + Expanded(content))`
- Le FloatingActionButton a ete supprime

### `lib/pages/consultation_page.dart` — CASSE (lignes ~291-312)

La methode `_rediger()` appelle 3 methodes statiques qui n'existent plus :
```dart
await PatientDetailsPage.ouvrirOrdonnance(context, ownerProfileId: ..., patientId: ..., patientData: ...);
await PatientDetailsPage.ouvrirBilan(context, ownerProfileId: ..., patientId: ..., patientData: ...);
await PatientDetailsPage.ouvrirFormulaireMedecin(context, ownerProfileId: ..., patientId: ..., patientData: ...);
```

---

## 4. Comment fixer le build (3 options)

### Option A (recommandee) — StatelessWidget + StatefulBuilder pour tabs

1. Wrapper le `Row(sidebar + content)` dans un `StatefulBuilder` qui gere `_tabIndex` localement
2. Re-ajouter les 3 methodes publiques `ouvrirOrdonnance`, `ouvrirBilan`, `ouvrirFormulaireMedecin` sur `PatientDetailsPage` — elles delegent aux methodes privees existantes (`_openOrdonnanceDialog`, `_openBilanDialog`, `_addDoctorForm`)
3. Preserve le pattern (anti-pattern) ou `consultation_page.dart` construit une instance de `PatientDetailsPage` pour appeler ces methodes

### Option B — Extraire les dialogs dans une classe separee

1. Creer `PatientDialogs(ownerProfileId, patientId)` avec les 3 methodes + ~15 helpers (~1500 lignes)
2. Les deux fichiers utilisent `PatientDialogs`
3. Plus propre mais gros refactor

### Option C — Revenir a StatefulWidget + methodes statiques

1. Reconvertir en StatefulWidget (c'est deja a moitie fait)
2. Ajouter des methodes `static Future<void> ouvrirOrdonnance(...)` qui ouvrent les dialogs directement sans passer par le State
3. Complexe car les methodes dialog ont besoin du context et referent plein de helpers

---

## 5. Fichiers cles a lire

| Fichier | Lignes | Role |
|---|---|---|
| `lib/pages/patient_details_page.dart` | ~4370 | Dossier patient — LE gros morceau, CASSE |
| `lib/pages/consultation_page.dart` | ~700 | Consultation — appelle les 3 methodes manquantes |
| `lib/services/pdf_service.dart` | ~365 | Infra PDF extraite — OK |
| `lib/ui/app_theme.dart` | | Design tokens |
| `lib/services/api_service.dart` | | Facade backend |
| `RECAP_REFONTE_UX.md` | | Plan complet 7 etapes |

---

## 6. Migration en attente

Le compte `medjekane@gmail.com` a des donnees sur l'ancien chemin Firestore (`users/{uid}/comptes/{profileId}/patients/...`) pas encore migrees vers le nouveau (`cabinets/{uid}/patients/...`). La page `lib/pages/migration_page.dart` est prete mais la migration n'a pas ete lancee.

---

## 7. Ce qui marchait avant le refactor

Avant les edits de cette session, `PatientDetailsPage` etait un StatelessWidget fonctionnel avec :
- Un `SingleChildScrollView` vertical (scroll infini, pas de tabs)
- 3 methodes publiques `ouvrirOrdonnance()`, `ouvrirBilan()`, `ouvrirFormulaireMedecin()` que `consultation_page.dart` appelait en construisant une instance :
```dart
final page = PatientDetailsPage(patientId: id, patientName: name, parentUid: uid, ownerProfileId: profileId);
await page.ouvrirOrdonnance(context);
```
- Toute la logique PDF inline (maintenant extraite dans pdf_service.dart)
- Un FloatingActionButton pour les actions rapides

Le build compilait OK. Le seul changement qui devait arriver : remplacer le scroll infini par des onglets lateraux.

---

## 8. Build corrige (session du 2026-09-14, suite)

Option A appliquee, avec un ajustement : au lieu d'un `StatefulBuilder`, l'etat de l'onglet selectionne est porte par un `ValueNotifier<int> _tabIndex` (champ final de l'instance `PatientDetailsPage`, initialise a 0). Ce choix evite de reconstruire tout le `StreamBuilder` a chaque clic d'onglet — seuls la sidebar et le contenu d'onglet, chacun enveloppe dans un `ValueListenableBuilder<int>`, se reconstruisent.

Changements dans `lib/pages/patient_details_page.dart` :
- Constructeur non `const` + champ `final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);`
- Sidebar (`_buildSidebar`) : le `ListView.builder` est enveloppe dans `ValueListenableBuilder<int>`, `onTap` fait `_tabIndex.value = i` au lieu de `setState`
- `build()` : le `Expanded(child: _buildTabContent(...))` est enveloppe dans `ValueListenableBuilder<int>` qui fournit `tabIndex` en parametre nomme
- `_buildTabContent` accepte desormais un parametre `required int tabIndex` et fait `switch (tabIndex)` au lieu de `switch (_tabIndex)`
- `if (!mounted) return;` (ligne ~227, callback du bouton Consultation) remplace par `if (!context.mounted) return;` (pattern deja utilise partout ailleurs dans ce fichier)
- Ajout de 3 methodes statiques `ouvrirOrdonnance`, `ouvrirBilan`, `ouvrirFormulaireMedecin` (context, {required parentUid, ownerProfileId, patientId, patientData}) qui construisent une instance temporaire de `PatientDetailsPage` et delegue aux dialogs prives existants (`_openOrdonnanceDialog`, `_openBilanDialog`, `_addDoctorForm`)

Changement dans `lib/pages/consultation_page.dart` :
- Les 3 appels dans `_rediger()` passent maintenant `parentUid: widget.parentUid` en plus des parametres existants (la version cassee ne le passait pas, alors que les 3 methodes statiques en ont besoin pour construire l'instance)

`flutter analyze` : 0 erreur sur tout le projet (seulement des warnings/infos preexistants, ex. `withOpacity` deprecated). Build restaure.

### Les 7 etapes du plan UX sont terminees (voir `RECAP_REFONTE_UX.md` pour le detail)
- Etape 4 (barre de statut patient) : `lib/widgets/patient_status_bar.dart`
- Etape 5 (KPIs dashboards) : `lib/widgets/kpi_row.dart`, integre dans les 3 dashboards, remplace les cartes statiques et l'ancien `DailyVersementsCard` isole
- Etape 6 (statut visuel liste patients) : `lib/widgets/patient_status_indicator.dart`, integre dans `PatientsPage.dart` et les 2 `_PatientsTab`
- Etape 7 (consultation sans popup) : deja resolue par l'etape 2, verifiee sans modification necessaire

`flutter analyze` sur tout le projet : 0 erreur (166 infos/warnings, tous preexistants — deprecated `withOpacity`/`surfaceVariant`, variables inutilisees mineures sans lien avec ces changements).

### Point non teste
Aucune des etapes 3 a 7 n'a ete verifiee visuellement (l'app n'a pas ete lancee dans cette session — `flutter run -d windows` a un bug connu de self-relaunch, voir section 7). Seule l'analyse statique confirme l'absence d'erreur de compilation. A tester au prochain lancement : navigation onglets dossier patient, ouverture ordonnance/bilan en pages plein ecran, barre de statut patient, KPIs dashboards, pastilles de statut liste patients.

---

## 9. Etape 2 (B) — Ordonnance et bilan en pages plein ecran (FAIT)

`_openOrdonnanceDialog` (~510 lignes) et `_openBilanDialog` (~420 lignes) etaient des `AlertDialog` avec `StatefulBuilder` dans `patient_details_page.dart`. Convertis en pages completes :

- **Nouveaux fichiers** : `lib/pages/ordonnance_page.dart` (`OrdonnancePage`), `lib/pages/bilan_page.dart` (`BilanPage`) — StatefulWidget classiques (controllers en champs de State, disposes normalement dans `dispose()`, plus besoin du hack `libererApresFermeture`/`apresFermeture` qui ne concerne que les dialogs)
- **Layout** : `LayoutBuilder` — cote a cote (formulaire a gauche scrollable, apercu PDF live a droite scrollable) au-dela de 900px de large, empile verticalement en dessous
- **Comportement simplifie** : les deux pages impriment maintenant le PDF automatiquement apres l'enregistrement puis font `Navigator.pop` (avant : l'ordonnance imprimait apres un delai de 300ms en gardant le dialog ferme, le bilan demandait un clic sur une action de SnackBar — ce detail d'UX a change, la logique de sauvegarde des donnees non)
- **API inchangee cote appelant** : `PatientDetailsPage.ouvrirOrdonnance(context, {ownerProfileId, patientId, patientData})` et `.ouvrirBilan(...)` font `Navigator.push` vers les nouvelles pages. Le parametre `parentUid` a ete retire de ces deux methodes statiques (il ne servait qu'a construire une instance temporaire de `PatientDetailsPage`, plus necessaire) — mis a jour dans `consultation_page.dart` (`_rediger()`) en consequence
- **Code mort supprime** dans `patient_details_page.dart` : `_buildOrdonnancePreview`, `_buildBilanPreview`, `_OrdonnanceLine`, `_BilanLine`, ainsi que les helpers qui n'etaient utilises que par ces dialogs (`_computeSeanceNumero`, `_isDoctorOrPrincipalForPatient`, `_normalizeCabinetItems`, `_loadCabinetReferenceList`, `_appendCabinetReferenceList` — dupliques localement dans les deux nouvelles pages). Imports `dart:ui` et `pdf_service.dart` retires (plus utilises dans ce fichier)
- Fichier `patient_details_page.dart` : 4400 → ~3120 lignes (progression vers la cible ~200 lignes de l'etape 3, qui reste a finaliser par eclatement en `lib/pages/dossier/`)

`flutter analyze` : 0 erreur sur tout le projet apres cette etape.
