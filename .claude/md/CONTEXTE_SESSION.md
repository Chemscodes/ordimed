# Contexte de session — Ordimed

> Généré le 2026-09-14. Résumé des deux sessions Claude Code qui ont refactorisé le projet.

---

## 1. Projet

**Ordimed** — application Flutter/Windows de gestion d'un cabinet médical (Algérie).

| Élément | Valeur |
|---|---|
| Répertoire | `D:\ordimed` |
| Plateforme cible | Windows Desktop (Flutter) |
| Backend principal | Firebase Auth + Cloud Firestore |
| Backend secondaire | Node.js + Express + MongoDB (fallback) |
| Branche git | `main` |
| Version app | `1.0.0+1` |
| Firebase project | `chems21-3dbe3` |

---

## 2. Architecture hybride (nouveau)

L'app peut switcher entre Firebase et le backend Node **sans recompiler**, via un dialogue `ChoixBase` accessible depuis l'écran de connexion.

```
lib/services/
├── backend_config.dart       ← enum Backend + BackendConfig (SharedPreferences)
├── cabinet_backend.dart      ← interface abstraite CabinetBackend (48 méthodes)
├── auth_backend.dart         ← interface abstraite AuthBackend
├── api_service.dart          ← façade : délègue à Firebase ou Mongo
├── auth_service.dart         ← façade : délègue à Firebase ou Mongo
├── firebase/
│   ├── firebase_refs.dart          ← chemins Firestore, versMap(), hacherPin(), dayKey()
│   ├── firebase_auth_backend.dart  ← FirebaseAuth → AuthBackend
│   └── firebase_cabinet_backend.dart ← Firestore → CabinetBackend (48 méthodes)
└── mongo/
    ├── mongo_auth_backend.dart     ← JWT + ApiClient → AuthBackend
    └── mongo_cabinet_backend.dart  ← ApiClient + RealtimeService → CabinetBackend
```

### Sélection du backend

- **Runtime** : `ChoixBase.ouvrir(context)` → écrit dans SharedPreferences → redémarrage requis
- **Compilation** : `flutter run --dart-define=BACKEND=mongo`
- **Défaut** : Firebase

---

## 3. Modèle de données Firestore

Structure plate sous `cabinets/{uid}/` :

| Sous-collection | Contenu |
|---|---|
| `profiles` | Médecins et assistantes |
| `patients` | Dossiers patients |
| `forms` | Documents cliniques par patient |
| `versements` | Paiements |
| `rendezvous` | Rendez-vous |
| `salle_attente` | File d'attente du jour |
| `purchases` | Achats/stocks |
| `daily_stats` | Stats journalières (dayKey: `YYYY-MM-DD`) |

### Règles de sécurité

- `medecin_principal` → accès à tout le cabinet
- Autres rôles → seulement `doctorId == profil OR assistantId == profil`
- Implémenté via `_portee()` et `_porteeFlux()` dans `firebase_cabinet_backend.dart`

---

## 4. Bugs Firebase corrigés (14 au total)

| # | Problème | Correction |
|---|---|---|
| 1 | Filtre profils manquait `assistantId` | `_portee()` avec `Filter.or()` |
| 2 | `creerPatient` n'écrivait que le patient | Batch : patient + form initial + entrée salle |
| 3 | `pinHash` fuité aux clients | `_sansPin()` le retire avant tout retour |
| 4 | `verifierPin` acceptait n'importe quel code si pas de hash | PIN par défaut `'0000'` |
| 5 | Salle d'attente omettait les entrées fermées aujourd'hui | Corrigé dans `_fileDuJour()` |
| 6 | `motif` non dérivé de `motifs` | Helper `_avecMotif()` |
| 7 | Ordre salle d'attente ascendant | Changé en descendant |
| 8 | Doublon en salle ignoré silencieusement | Lance ApiException 409 |
| 9 | `demarrerConsultation` ne remettait pas `closedAt: null` | Corrigé |
| 10 | Aucune validation format PIN | Regex `^\d{4,6}$` |
| 11 | Profil initial sans PIN | Hash de `'0000'` à la création |
| 12 | `supprimerAchat` manquait `dayKey` dans les stats | Corrigé |
| 13 | `statsJournalieres` utilisait `FieldPath.documentId` | Changé en `where('dayKey', ...)` |
| 14 | `hacherPin` dupliqué | Déplacé dans `FirebaseRefs.hacherPin()` |

---

## 5. Fichiers clés modifiés / créés

### Nouveaux
- `lib/services/backend_config.dart`
- `lib/services/cabinet_backend.dart`
- `lib/services/auth_backend.dart`
- `lib/services/firebase/firebase_refs.dart`
- `lib/services/firebase/firebase_auth_backend.dart`
- `lib/services/firebase/firebase_cabinet_backend.dart`
- `lib/services/mongo/mongo_auth_backend.dart`
- `lib/services/mongo/mongo_cabinet_backend.dart`
- `lib/pages/choix_base.dart`
- `firestore.rules` (réécrit)
- `firestore.indexes.json` (vidé — aucun index composite nécessaire)

### Modifiés
- `lib/main.dart` — init Firebase conditionnelle + `BackendConfig.restaurer()`
- `lib/services/api_service.dart` — réduit à une façade
- `lib/services/auth_service.dart` — réduit à une façade
- `lib/pages/login_page.dart` — bouton backend → `ChoixBase`
- `windows/runner/main.cpp` — fix du self-relaunch pour `flutter run`

### Design (D:\ordimed\design\)
- `Main.dc.html` — Poste médecin
- `Assistant.dc.html` — Poste assistant
- `Directeur.dc.html` — Poste direction (graphique stats)
- `Dossier.dc.html` — Dossier patient
- `Consultation.dc.html` — Séance en cours (IMC live)
- `Connexion.dc.html` — PIN numpad
- `Ordonnance.dc.html` — Ordonnance A4 bilingue FR/AR
- `Systeme.dc.html` — Système de design (tokens)
- `canvas.json` — Layout 3 pages
- Artifact publié : https://claude.ai/code/artifact/214dc9f0-404a-4fa7-921b-a16871d397e4

---

## 6. Système de design (tokens à porter dans `lib/ui/app_theme.dart`)

Défini dans `design/Systeme.dc.html`. Résumé des écarts avec le thème actuel :

| Token | Actuel | Cible |
|---|---|---|
| Police | (non spécifiée) | IBM Plex Sans + IBM Plex Mono |
| Fond principal | dégradé turquoise | `#0E0F11` (gris très sombre) |
| Accent primaire | turquoise saturé | `#1B9C88` |
| Accent chaud | halo orange | `#B8760F` |
| Chart teinte 1 | — | `#1FA894` (validé CVD ΔE 14.0 deutéranopie) |
| Chart teinte 2 | — | `#C77F17` |
| Radius | — | 6 px |
| Hauteur contrôles | — | 32 px |

---

## 7. Problème `flutter run -d windows`

### Symptôme
```
Error waiting for a debug connection: The log reader stopped unexpectedly, or never started.
```

### Cause
`windows/runner/main.cpp` se **relance lui-même** avec `--enable-software-rendering` via `CreateProcessW`. Flutter attache son log reader au process original, qui quitte immédiatement → pipe coupé.

### Fix appliqué (en test)
Dans `main.cpp` :
- `bInheritHandles = TRUE` → l'enfant hérite des pipes stdout/stderr de Flutter
- `WaitForSingleObject(process_info.hProcess, INFINITE)` → le parent reste vivant jusqu'à ce que l'enfant se ferme
- Propage le code de sortie de l'enfant

### Contournement fonctionnel
Lancer directement l'exe (sans `flutter run`) :
```powershell
Start-Process -FilePath "D:\ordimed\build\windows\x64\runner\Debug\ordimed.exe" `
              -WorkingDirectory "D:\ordimed\build\windows\x64\runner\Debug"
```

---

## 8. État à la fin de session

| Tâche | Statut |
|---|---|
| Architecture hybride Firebase/Mongo | ✅ Terminé |
| 14 bugs Firebase corrigés | ✅ Terminé |
| Design system — 8 artboards | ✅ Terminé + publié |
| Fix `flutter run` (main.cpp) | 🔄 Build en cours (test 3) |
| Porter tokens dans `app_theme.dart` | ⏳ À faire |
| Déployer `firestore.rules` | ⏳ À faire (`firebase deploy --only firestore:rules`) |
| Créer un compte Firebase pour tester | ⏳ À faire (aucun compte enregistré) |

---

## 9. Commandes utiles

```bash
# Lancer avec Firebase (défaut)
flutter run -d windows

# Lancer avec backend Mongo
flutter run -d windows --dart-define=BACKEND=mongo

# Lancer directement l'exe (contourne le problème flutter run)
# PowerShell :
Start-Process "D:\ordimed\build\windows\x64\runner\Debug\ordimed.exe" -WorkingDirectory "D:\ordimed\build\windows\x64\runner\Debug"

# Déployer les règles Firestore
firebase deploy --only firestore:rules

# Build release
flutter build windows --release
```

---

## 10. Notes importantes

- **Aucun compte Firebase n'est enregistré** — l'app va directement à `LoginPage` au premier lancement (comportement correct, pas un bug).
- Le **code PIN par défaut** du médecin principal est `0000`.
- Les **règles Firestore** doivent être déployées avant de pouvoir lire/écrire depuis l'app.
- La persistance offline Firestore est activée (`cacheSizeBytes: CACHE_SIZE_UNLIMITED`).
- Le module `windows/runner/main.cpp` force `--enable-software-rendering` pour ce matériel — ne pas le supprimer.
