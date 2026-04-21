# Scripts de Migration Firebase

Ce dossier contient des scripts permettant de cloner l'intégralité d'un projet Firebase (Authentification, Base de données Firestore, et Fichiers Storage) vers un autre projet Firebase.

C'est particulièrement utile pour migrer des données d'un environnement "Preview" vers un environnement de "Production", ou lors d'un changement de nom de projet.

## Prérequis

Ces scripts utilisent le SDK `firebase-admin` de Node.js. Ils ont besoin de **clés de compte de service** pour contourner les règles de sécurité et avoir un accès total aux données.

1. **Obtenir la clé Source (Le projet à copier)**
   - Allez sur la console Firebase du projet source.
   - Paramètres du projet (Engrenage) > Onglet **Comptes de service**.
   - Cliquez sur **Générer une nouvelle clé privée**.
   - Enregistrez le fichier JSON obtenu dans ce dossier (`scripts/migration/`) et renommez-le très exactement **`source-key.json`**.

2. **Obtenir la clé Destination (Le projet qui va recevoir les données)**
   - Faites la même chose sur la console Firebase du projet destination.
   - Enregistrez le fichier obtenu dans ce dossier et renommez-le très exactement **`dest-key.json`**.

> [!WARNING]
> Ces clés donnent les droits d'administrateur total sur vos bases de données. **Ne les commitez jamais sur Git.**
> Le fichier `.gitignore` a été configuré (ou doit l'être) pour ignorer les fichiers `*-key.json`. Les scripts les suppriment automatiquement à la fin de leur exécution.

3. **Installer les dépendances**
   Si ce n'est pas déjà fait, ouvrez un terminal dans ce dossier et lancez :
   ```bash
   npm install
   ```

## Ordre d'exécution recommandé

Pour que les relations entre utilisateurs et documents soient conservées, il faut d'abord migrer les utilisateurs, puis la donnée.

### 1. Migrer l'Authentification (Comptes Utilisateurs)

Ce script copie tous les comptes Google/Email vers le nouveau projet, en conservant exactement les mêmes `uid` (identifiants uniques). C'est crucial pour que les utilisateurs gardent accès à leurs données.

```bash
node migrate_auth.js
```
*(Le script supprime les clés JSON à la fin pour votre sécurité).*

### 2. Migrer les Données (Firestore & Storage)

**Important :** Si le script précédent a supprimé les clés, vous devez les re-télécharger et les replacer dans ce dossier sous les noms `source-key.json` et `dest-key.json` avant de lancer ce deuxième script.

Ce script parcourt toutes les collections de la base Firestore source et les copie dans la destination. Ensuite, il copie tous les fichiers (images) du Storage source vers le Storage destination.

```bash
node migrate.js
```

## Dépannage
- **Erreur Storage "The specified bucket does not exist"** : Le script essaie de déduire le nom du bucket (souvent `project-id.appspot.com` ou `project-id.firebasestorage.app`). Si vous avez un nom de bucket personnalisé, vous devrez peut-être modifier manuellement les URL de `storageBucket` dans le fichier `migrate.js`.
