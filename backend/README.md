# Backend Ordimed — Node.js / Express / MongoDB

Remplace Firebase. Même modèle de données, mêmes règles métier.

## Démarrer

Docker Desktop est requis et **n'est pas installé sur ce poste** — c'est le
préalable. Une fois en place :

```bash
docker compose up --build
```

Mongo démarre en replica set, s'initie tout seul, puis le backend attend
qu'il réponde. L'API écoute sur `http://localhost:4000`.

```bash
curl http://localhost:4000/health
# {"ok":true,"mongo":"connecte"}
```

### Pourquoi un replica set pour une base locale

L'app fait **21 écritures atomiques** : créer un patient pose le dossier, le
formulaire initial et l'entrée en salle d'attente ; clôturer une
consultation décompte la séance, sort le patient de la file et marque le
rendez-vous honoré. MongoDB n'autorise les transactions que sur un replica
set. Un `mongo:7` seul les refuse — et l'échec surviendrait en production,
à moitié écrit.

Le serveur teste la disponibilité des transactions au démarrage et le dit
franchement si elles manquent.

## Récupérer les données Firestore

Pas de connecteur, pas d'export Google : le pont est la sauvegarde JSON que
l'app produit déjà (**Tableau directeur → Sauvegardes → Sauvegarder**).

```bash
cp ~/Documents/Ordimed/sauvegardes/ordimed-2026-08-08-1430.json backend/import/
docker compose exec backend node scripts/import-backup.js \
  ./import/ordimed-2026-08-08-1430.json  mon-mot-de-passe
```

Le mot de passe est demandé parce que **Firebase le gardait de son côté** :
la sauvegarde ne le contient pas, et il n'existe nulle part dans tes
données.

L'import est **idempotent** — relancé deux fois, il met à jour au lieu de
dupliquer. Une migration qu'on ne peut pas rejouer est une migration qu'on
n'ose pas commencer.

Il dédoublonne aussi les copies : Firestore écrivait chaque patient deux
fois et chaque entrée de salle d'attente trois fois. Le compteur `ignores`
en fin d'import compte ces doublons **et** les documents inexploitables
(rendez-vous sans date, patient introuvable).

## Revenir a Firebase

Le chemin inverse existe et il est teste. La boucle se ferme parce que
`BackupService.restaurer`, au tag `firebase-final`, sait deja ecrire ce
format **dans Firestore**.

```bash
docker compose exec backend npm run export -- cabinet@exemple.dz
# -> backend/import/ordimed-AAAA-MM-JJ-HHMM.json

git checkout firebase-final
flutter build windows --debug
# copie le fichier dans Documents\Ordimed\sauvegardes
# lance l'app -> Sauvegardes -> Restaurer
```

Deux details rendent ce retour possible, et ils sont poses a l'import :

- **l'uid Firebase du cabinet** est conserve (`firebaseUid`). Sans lui l'app
  refuse le fichier — « cette sauvegarde appartient a un autre cabinet » ;
- **les identifiants Firestore d'origine** sont conserves (`firestoreId`).
  Sans eux la restauration creerait une seconde serie de dossiers au lieu de
  reecrire les existants.

Les references entre documents — un patient vers son medecin, un rendez-vous
vers son patient — sont traduites vers ces identifiants a l'export. Une
reference laissee en ObjectId ferait ecarter le document **en silence** :
c'est exactement le bug que le test d'aller-retour a attrape.

## Les routes

| Méthode | Route | Remplace |
|---|---|---|
| POST | `/api/auth/register` | `createUserWithEmailAndPassword` |
| POST | `/api/auth/login` | `signInWithEmailAndPassword` |
| POST | `/api/auth/pin` | la comparaison de PIN côté client |
| GET/PUT | `/api/auth/me`, `/api/auth/horaires` | `users/{uid}` |
| GET/POST/PUT/DELETE | `/api/profiles` | `comptes/{id}` |
| GET/POST/PUT/DELETE | `/api/patients` | `patients/{id}` |
| GET | `/api/patients/:id/detail` | dossier + documents + versements |
| POST | `/api/patients/:id/restaurer` | annule la suppression douce |
| GET/POST/DELETE | `/api/forms` | `forms/{id}` |
| GET/POST | `/api/versements` | sous-collection `versements` |
| GET/POST/PUT/DELETE | `/api/rendezvous` | `rendezvous/{id}` |
| POST | `/api/rendezvous/:id/arrive` | « patient arrivé » (RDV → file) |
| POST | `/api/rendezvous/:id/etape` | changement d'étape |
| GET/POST | `/api/waiting` | `salle_attente/{id}` |
| POST | `/api/waiting/:id/demarrer` \| `/cloturer` | consultation |
| GET/POST/DELETE | `/api/purchases` | `purchases/{id}` |
| GET | `/api/stats/daily` | `daily_stats/{dayKey}` |
| POST | `/api/stats/recalculer` | reconstruit les agrégats |
| POST | `/api/errors` | `error_logs` (sans jeton) |

## Le temps réel

Socket.IO, sur le même port. Il remplace les 27 flux `snapshots()` de
Firestore — sans lui, l'écran du médecin ne bougerait plus quand l'assistant
place un patient, et la salle d'attente cesserait d'être partagée.

```js
socket = io('http://localhost:4000', { auth: { token } });
socket.on('changement', ({ entite, action, donnees }) => { … });
```

`entite` reprend le nom de la collection Firestore (`patients`,
`salle_attente`, `rendezvous`, `versements`, `forms`, `purchases`,
`comptes`), pour que Flutter s'abonne avec le vocabulaire qu'il utilisait
déjà.

Chaque cabinet a son salon, déduit du jeton. Le client ne choisit pas le
sien : le laisser demander « abonne-moi au cabinet X » suffirait à écouter
les patients d'un autre.

## Sécurité

`firestore.rules` tenait en une ligne : un cabinet ne voit que ses données.
En REST il n'y a plus de règle globale — **chaque route doit filtrer sur
`parentUid`**, et un oubli n'échoue pas, il expose les dossiers d'un autre
cabinet en silence.

D'où `scope(req)` dans `middleware/auth.js` : le filtre est fabriqué, pas
réécrit à la main dans chaque contrôleur. Toute requête part de là.

Deux choses gagnées au passage :

- **Le PIN est haché** (bcrypt) et vérifié côté serveur. Il était en clair
  en base et comparé dans l'app — n'importe quel client modifié pouvait
  sauter la comparaison.
- **Le conflit de créneau est revérifié côté serveur.** Le contrôle vivait
  dans Flutter, ce qui suffisait tant que le client était le seul chemin
  vers la base. Avec une API, deux postes peuvent poser le même créneau à la
  même seconde.

`JWT_SECRET` doit être défini en production : le serveur **refuse de
démarrer** avec le secret par défaut, qui permettrait de forger un jeton
pour n'importe quel cabinet.

## Ce qui n'a pas d'équivalent

**Le hors-ligne.** `persistenceEnabled: true` faisait tourner le cabinet
quand Internet tombait. En REST, la coupure arrête le travail. Si la
connexion du cabinet est incertaine, il faudra une file d'attente locale
côté Flutter — c'est un chantier à part entière, pas une option de
configuration.

**Firebase Storage.** Le projet n'en a jamais utilisé (voir MIGRATION.md
§1.5). `uploads/` et la route statique existent pour un usage futur ; rien
n'y transite aujourd'hui.
