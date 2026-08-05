# Page de présentation

Site vitrine du projet Ordimed.
En ligne : https://ordimedev.netlify.app/

## Fichiers

| Fichier | Rôle |
|---|---|
| `ordimed.html` | **La source.** C'est ici qu'on modifie la page. |
| `build-standalone.ps1` | Génère `index.html` à partir de la source. |
| `index.html` | Version autonome, hébergeable. **Généré — ne pas éditer.** |
| `cabinet-1/2/3.mp4` | Clips de fond des trois actes. Non versionnés. |

## Modifier la page

```powershell
# 1. éditer ordimed.html
# 2. régénérer la version hébergeable
.\build-standalone.ps1
# 3. redéposer le dossier sur Netlify
```

## Les vidéos

Les trois clips ne sont pas dans le dépôt : ce sont des plans de banque d'images
(~26 Mo au total) qui alourdiraient l'historique pour toujours.

Pour les retrouver, télécharge trois séquences libres pour usage commercial sur
[pexels.com/videos](https://www.pexels.com/videos/) — recherches utiles :
*doctor patient*, *medical consultation*, *clinic reception* — puis nomme-les
`cabinet-1.mp4`, `cabinet-2.mp4` et `cabinet-3.mp4` dans ce dossier.

Format visé : **6 à 10 s, muet, format vertical, 1 à 2 Mo par fichier.**
Prends la version **HD ou SD**, pas UHD : les cadres font quelques centaines de
pixels de large à l'écran, et la 4K ne fait qu'allonger le temps de chargement.

Sans ces fichiers la page reste parfaitement fonctionnelle — chaque acte affiche
un dégradé animé à la place de son clip.
