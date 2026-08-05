# Correctif performance / crash — Ordimed

## Le probleme

L'application se figeait puis se fermait toute seule chez les utilisateurs
ayant beaucoup de donnees (« scaling »). Cause : plusieurs ecrans
telechargeaient **toute la base de patients du cabinet** a chaque
rafraichissement, via des requetes `collectionGroup('patients')` sans limite.
Chaque patient contient en plus un tableau `versements` qui grossit sans fin.

Resultat : sur le tableau de bord directeur, des milliers de documents etaient
charges en memoire et parcourus **sur le thread d'interface**, ce qui provoquait
des gels (Windows « ne repond pas ») puis un crash memoire.

## Ce qui a ete change

Les agregats financiers (`daily_stats`) sont **deja maintenus** par
l'application a chaque versement / achat. Les ecrans lisent maintenant
ces agregats (1 a 7 documents) au lieu de scanner toute la base :

| Fichier | Avant | Apres |
|---|---|---|
| `services/stats_service.dart` | — | `addVersement` enregistre aussi le detail par medecin (`doctorVersements`) |
| `pages/dashboard_assistant.dart` | scan complet (net du jour) | lecture `daily_stats` |
| `pages/dashboard_principale.dart` | 3 scans complets | lecture `daily_stats` |
| `pages/stats_page.dart` | scan complet (7 jours) | lecture `daily_stats` |

Petit bug corrige : affichage `$medecin` litteral dans la liste patients
du tableau medecin.

## Action requise cote Firebase

Deployer les index composites (sinon les requetes `purchases` echouent) :

```
firebase deploy --only firestore:indexes
```

(le fichier `firestore.indexes.json` est fourni a la racine du projet)

## Limite connue (sans impact sur la stabilite)

Le detail **par medecin** des versements du jour (`doctorVersements`) ne se
remplit que pour les versements ajoutes **apres** la mise a jour. Les totaux
du cabinet, eux, restent corrects immediatement. Le detail par medecin se
remplit normalement des le lendemain. Aucune donnee n'est perdue.

Pistes d'amelioration futures (non bloquantes) :
- `DailyVersementsCard` et le graphe hebdo du tableau medecin lisent encore
  les patients d'un **seul** profil (volume bien plus faible, pas de crash).
- A terme, stocker les `versements` dans une sous-collection plutot que dans
  un tableau du document patient.
