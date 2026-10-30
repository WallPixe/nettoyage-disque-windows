# Nettoyage Disque pour Windows

Un petit outil gratuit qui trouve **ce qui prend de la place pour rien** sur ton PC Windows et te propose de le supprimer : caches, restes de jeux désinstallés, jeux que tu ne lances plus, vieilles versions d'applications, dossiers de développement oubliés, gros fichiers…

**Il ne supprime rien sans ton accord.** Il commence toujours par une analyse qui ne modifie rien, puis c'est toi qui choisis.

> *English summary: a free Windows disk-cleanup script (French UI). It scans for caches, leftovers of uninstalled Steam/Epic games, unplayed games, old app versions, stale `node_modules`/`.venv`/build folders, abandoned partial downloads and big files, then lets you pick what to remove. Nothing is deleted without confirmation.*

---

## Télécharger et lancer

1. Va dans **[Releases](../../releases/latest)** et télécharge **`NettoyageDisque.zip`**.
   *(ou bouton vert **Code** → **Download ZIP** sur cette page)*
2. Fais un clic droit sur le ZIP → **Extraire tout…**
3. Dans le dossier extrait, double-clique sur **`Lancer-Nettoyage.bat`**.

Windows peut afficher un avertissement, parce que le fichier vient d'Internet :
- « *Windows a protégé votre ordinateur* » → clique sur **Informations complémentaires** puis **Exécuter quand même**.
- « *Avertissement de sécurité* » → clique sur **Exécuter**.

Le script est un simple fichier texte : tu peux l'ouvrir avec le Bloc-notes pour voir exactement ce qu'il fait avant de le lancer.

**Configuration requise :** Windows 10 ou 11. Rien à installer, PowerShell est déjà fourni avec Windows. Pas besoin d'être administrateur.

---

## Comment ça se passe

L'analyse prend de 1 à 10 minutes selon la taille du disque. Ensuite, une liste numérotée s'affiche, par exemple :

```
  Caches
    1.    8,2 Go  Sûr        Cache des shaders NVIDIA
                         Se reconstruit : les jeux chargent un peu plus lentement la première fois.
    2.    1,1 Go  Sûr        Cache du navigateur Chrome
                         Ferme Chrome avant. Tes mots de passe, favoris et historique ne sont pas touchés.

  Restes de jeux désinstallés
    3.   13,3 Go  À vérifier Steam : ARK Survival Ascended
                         Plus installé selon Steam. Peut contenir des sauvegardes, captures ou mods.

  Anciennes versions d'applications
    4.   22,4 Go  Sûr        CapCut : 14 ancienne(s) version(s)
                         La version la plus récente (9.6.0.4097) est conservée.

  Jeux installés mais plus joués
    5.   42,6 Go  À vérifier Steam : Un jeu (pas lancé depuis le 12/03/2026)
                         Désinstallé par Steam (il demande confirmation). Les sauvegardes Steam Cloud sont gardées.

  Sans risque (« Sûr ») : 31,7 Go    Tout compris : 87,6 Go

Que veux-tu nettoyer ?
  - des numéros, par exemple : 1,3,7-9
  - S pour tous les éléments marqués « Sûr »
  - Entrée pour quitter sans rien toucher
```

Tu tapes tes numéros (ou `S`), tu relis le récapitulatif, puis tu tapes **OUI** pour lancer le nettoyage. À la fin, l'outil affiche combien de place a été libérée.

| Étiquette | Signification |
|---|---|
| **Sûr** | Se recrée tout seul ou ne sert plus à rien. Tu peux y aller. |
| **À vérifier** | Peut contenir quelque chose qui compte pour toi (sauvegardes de jeu, mods, photos…). Regarde avant. |

---

## Ce que l'outil cherche

| Catégorie | Exemples | Ce qu'il en fait |
|---|---|---|
| **Caches** | Shaders NVIDIA / AMD / Intel / DirectX, navigateurs (Chrome, Edge, Brave, Firefox), fichiers temporaires, rapports de plantage, caches pip / uv / npm / Yarn / Gradle | Vide le dossier (définitif, se recrée) |
| **Restes de jeux désinstallés** | Dossiers Steam ou Epic Games restés sur le disque, caches de shaders et mods Workshop de jeux désinstallés, téléchargements Steam interrompus | Corbeille |
| **Jeux plus joués** | Jeux Steam pas lancés depuis 30 jours (taille ≥ 1 Go) | Ouvre la désinstallation de Steam |
| **Anciennes versions d'applications** | Applis qui gardent chaque version (CapCut, Discord, WeMod…), anciens NDK Android | Supprime les anciennes, **garde la plus récente** |
| **Dossiers de développement inactifs** | `node_modules`, environnements Python (`.venv`), compilations Android (`build`) et Unreal (`Intermediate`, `DerivedDataCache`) de projets non modifiés depuis 30 jours | Supprime (se régénère) |
| **Fichiers temporaires abandonnés** | `.partial`, `.part`, `.crdownload`, `.tmp` de plus de 100 Mo, vieux d'au moins 7 jours | Supprime |
| **Gros fichiers personnels** | Fichiers de 2 Go et plus dans ton dossier personnel | Corbeille |
| **Téléchargements** | Éléments du dossier Téléchargements de plus de 90 jours | Corbeille |
| **Corbeille** | Taille de la Corbeille | La vide (si tu la choisis) |
| **Démarrage** | Programmes au démarrage qui ne pointent vers aucun fichier | Retire l'entrée, après une sauvegarde `.reg` dans Documents |

Pour info, l'outil affiche aussi les programmes installés les plus lourds. Pour ceux-là, la désinstallation se fait dans **Paramètres → Applications**.

---

## Où vont les fichiers supprimés ?

- **Caches et fichiers régénérables** : supprimés définitivement, puisqu'ils se recréent.
- **Restes de jeux, gros fichiers, téléchargements** : envoyés à la **Corbeille**. Ils ne libèrent la place qu'une fois la Corbeille vidée. Si un élément est trop gros pour la Corbeille, Windows te prévient avant de l'effacer.
- **Jeux Steam** : c'est Steam qui les désinstalle, avec sa propre fenêtre de confirmation.
- **Entrées de démarrage** : une sauvegarde `sauvegarde-demarrage-….reg` est créée dans Documents. Double-clique dessus pour revenir en arrière.

L'outil ne touche jamais à `C:\Windows`, aux programmes installés (sauf les jeux Steam, via Steam) ni aux dossiers cachés (`.git`, `.cache`…). Tes fichiers personnels ne sont proposés que s'ils sont très gros ou très vieux, et ils partent à la Corbeille.

---

## Options

Tu peux les ajouter après le nom du `.bat` (dans un terminal ouvert dans le dossier) :

```bat
Lancer-Nettoyage.bat -SeulementAnalyse
Lancer-Nettoyage.bat -JoursInactif 60 -TailleMinGo 5
```

| Option | Effet | Par défaut |
|---|---|---|
| `-SeulementAnalyse` | Affiche le rapport et s'arrête, sans rien proposer | — |
| `-JoursInactif N` | Un projet ou un jeu est « inutilisé » après N jours | 30 |
| `-TailleMinGo N` | Taille à partir de laquelle un fichier est signalé comme gros | 2 |

---

## Conseils

- **Ferme** les jeux, Steam, ton navigateur et les applis concernées avant de nettoyer : les fichiers ouverts ne peuvent pas être supprimés.
- **En administrateur** (clic droit sur le `.bat` → *Exécuter en tant qu'administrateur*), l'outil peut aussi vider les fichiers temporaires de Windows.
- Commence par les éléments **Sûr**, puis regarde les **À vérifier** un par un.

## Limites

- Windows uniquement.
- Restes de jeux : seuls **Steam** et **Epic Games** sont reconnus (pas encore Riot, EA, Ubisoft, GOG, Xbox).
- L'analyse couvre ton dossier personnel et les dossiers à la racine du disque système. Les autres disques ne sont regardés que pour les bibliothèques Steam et Epic.
- Les fichiers OneDrive « disponibles en ligne uniquement » sont ignorés : ils ne prennent pas de place.

## Licence

[MIT](LICENSE) : libre d'utilisation, de modification et de partage. Fourni tel quel, sans garantie : relis la liste avant de confirmer.
