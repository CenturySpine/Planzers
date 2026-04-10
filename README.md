# Planzers - App mobile voyage entre amis

Application Flutter multiplateforme (Android, iOS, Web) pour centraliser la gestion d'un voyage entre amis:
- covoiturage
- courses
- planification des repas
- partage des depenses
- informations pratiques

## Vision

Offrir un seul espace collaboratif pour preparer et suivre un voyage de groupe sans jongler entre plusieurs applis.

## Stack technique cible

- **Frontend**: Flutter (Dart)
- **Backend as a Service**: Firebase
  - Authentication
  - Cloud Firestore
  - Cloud Functions (optionnel au debut)
  - Firebase Storage (pieces jointes, photos)
  - Firebase Cloud Messaging (notifications)

## Demarrage rapide (nouvelle machine)

### 1. Prerequis systeme

- Installer **Flutter SDK** (canal stable) et ajouter `<flutter>/bin` au `PATH`.
- Installer **Android Studio** (inclut SDK Android, outils Gradle et JDK `jbr`).
- Sur Windows, activer **Mode developpeur** (plugins Flutter avec symlinks).
- Installer **Node.js LTS** (necessaire pour `npm`), puis la **Firebase CLI**:
  - `npm install -g firebase-tools`
- Installer **Java 17+** (recommande: JDK inclus d'Android Studio: `...\Android Studio\jbr`).
- Configurer les variables d'environnement Windows:
  - `JAVA_HOME` -> chemin du JDK **sans `\bin`** (ex: `C:\Program Files\Android\Android Studio\jbr`)
  - ajouter `%JAVA_HOME%\bin` au `Path`
  - ajouter `C:\Users\<ton-user>\AppData\Local\Pub\Cache\bin` au `Path` (pour `flutterfire`)
- Ouvrir un nouveau terminal et verifier:

```bash
flutter --version
dart --version
java -version
firebase --version
```

Verification complementaire recommandee sous Windows (utile si Gradle ne trouve pas Java):

```powershell
echo $env:JAVA_HOME
where.exe java
java -version
```

Si `where.exe java` ne retourne rien:
- verifier que `JAVA_HOME` pointe bien vers le dossier JDK (pas `...\jbr\bin`)
- verifier que `%JAVA_HOME%\bin` est present dans `Path`
- fermer completement Cursor/terminal puis reouvrir une nouvelle session

### 2. Cloner et installer les dependances

```bash
git clone <url-du-repo> Planzers
cd Planzers
flutter pub get
```

### 3. Auth Firebase / outils CLI

```bash
firebase login
dart pub global activate flutterfire_cli
```

Si `flutterfire` n'est pas reconnu, utiliser:

```bash
dart pub global run flutterfire_cli:flutterfire --version
```

### 4. Configurer Firebase (console)

Dans la console Firebase:
- Creer ou choisir le projet (ex: `planzers`)
- **Authentication** -> *Sign-in method* -> activer **Google**
- **Firestore Database** -> creer la base (mode dev/test)
- Creer les apps de plateforme necessaires (Android, iOS, Web)

### 5. Android: SHA-1/SHA-256 + `google-services.json`

Depuis `android/`:

```bash
./gradlew signingReport
```

Sous Windows PowerShell:

```powershell
.\gradlew signingReport
```

- Copier la valeur **SHA1** (et idealement **SHA-256**) du variant `debug`.
- Firebase -> *Project settings* -> app Android -> **Add fingerprint**.
- Sur une **nouvelle machine de dev physique**, refaire cette etape: le keystore debug local peut changer, donc il faut ajouter les nouveaux fingerprints.
- Telecharger `google-services.json` apres ajout des fingerprints, puis le placer selon le flavor:
  - `android/app/src/preview/google-services.json` pour `--flavor preview`
  - `android/app/src/prod/google-services.json` pour `--flavor prod`

### 6. iOS: `GoogleService-Info.plist`

- Telecharger `GoogleService-Info.plist` depuis l'app iOS Firebase.
- Le placer dans `ios/Runner/GoogleService-Info.plist`.
- Verifier que `ios/Runner/Info.plist` contient `CFBundleURLTypes` avec le `REVERSED_CLIENT_ID`.

### 7. Lier Flutter au projet Firebase (FlutterFire)

Depuis la racine du projet:

```bash
dart pub global run flutterfire_cli:flutterfire configure
```

- Repondre `yes` si la CLI propose de reutiliser `firebase.json`.
- Cocher les plateformes que tu utilises.
- Verifier que `lib/firebase_options.dart` est regenere.

### 8. Lancer l'application

```bash
flutter clean
flutter pub get
flutter run -d windows
```

Flux de test minimal:
- Ecran **Connexion** -> bouton *Continuer avec Google*
- Ecran **Mes voyages**
- Bouton **Nouveau voyage** -> creation visible dans Firestore (`trips`)
- Document utilisateur cree/maj dans Firestore (`users/{uid}`)

## Cloud Functions (preview de lien)

Cette app utilise une Cloud Function pour generer les metadonnees de preview (`linkPreview`) a partir de `trips/{tripId}.linkUrl`.

### Prerequis Firebase

- Projet Firebase en **plan Blaze** (obligatoire pour Cloud Functions gen2 en production).
- APIs Google Cloud activees (normalement proposees automatiquement au premier deploy):
  - Cloud Functions API
  - Cloud Build API
  - Artifact Registry API
  - Cloud Run API
  - Eventarc API

### Prerequis local

- Etre connecte avec la Firebase CLI:

```bash
firebase login
```

- Installer les dependances des fonctions:

```bash
cd functions
npm install
cd ..
```

### Deploiement

Depuis la racine du repo:

```bash
firebase deploy --only functions --project planzers
```

Au premier deploy, Firebase peut demander une politique de retention des images de conteneur (Artifact Registry). Recommandation: `30` jours.

### Verification apres deploy

1. Dans l'app, modifier un voyage et renseigner un `linkUrl`.
2. Dans Firestore (`trips/{tripId}`), verifier le champ `linkPreview`:
   - `status: "loading"` puis `status: "ok"` (ou `empty` / `error`)
   - champs attendus: `title`, `description`, `siteName`, `imageUrl`, `fetchedAt`

### Redeployer apres modif de la function

Si tu modifies `functions/index.js`:

```bash
firebase deploy --only functions --project planzers
```

## Structure recommandee

Voir le dossier `docs/`:
- `docs/product_scope.md`
- `docs/firebase_data_model.md`
- `docs/roadmap.md`

## Modules fonctionnels (MVP)

1. Gestion des participants et invitations
2. Covoiturage (vehicules, places, trajets)
3. Liste de courses collaborative
4. Planning des repas
5. Suivi des depenses et repartition
