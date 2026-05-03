# Planerz - App mobile voyage entre amis

Application Flutter multiplateforme (Android, iOS, Web) pour centraliser la gestion d'un voyage entre amis:
- covoiturage
- courses
- planification des repas
- partage des depenses
- suggestion et planification d'activtés
- informations pratiques
- messagerie

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
git clone <url-du-repo> Planerz
cd Planerz
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
- Creer ou choisir le projet (ex: `planerz`)
- **Authentication** -> *Sign-in method* -> activer **Google**
- **Firestore Database** -> creer la base (mode dev/test)
- Creer les apps de plateforme necessaires (Android, iOS, Web)

### 5. Android: SHA-1/SHA-256 + `google-services.json`

Depuis `android/`:

```bash
./gradlew signingReport
```

```powershell
.\gradlew signingReport
```

- Copier la valeur **SHA1** (et idealement **SHA-256**) du variant `debug`.
- Firebase -> *Project settings* -> app Android -> **Add fingerprint**.
- Sur une **nouvelle machine de dev physique**, refaire cette etape: le keystore debug local peut changer, donc il faut ajouter les nouveaux fingerprints.
- Pour extraire les empreintes du **keystore de signature (`.jks`)** (release), utiliser `keytool`:

```powershell
keytool -list -v -keystore ".\planerz-keystore.jks" -alias "planerz"
```

Si tu ne connais pas l'alias du keystore:

```powershell
keytool -list -keystore ".\planerz-keystore.jks"
```

- Telecharger `google-services.json` apres ajout des fingerprints, puis le placer selon le flavor:
  - `android/app/src/preview/google-services.json` pour `--flavor preview`
  - `android/app/src/prod/google-services.json` pour `--flavor prod`

### 6. iOS: `GoogleService-Info.plist`

- Telecharger `GoogleService-Info.plist` depuis l'app iOS Firebase.
- Le placer dans `ios/Runner/GoogleService-Info.plist`.
- Verifier que `ios/Runner/Info.plist` contient `CFBundleURLTypes` avec le `REVERSED_CLIENT_ID`.

### 7. Lier Flutter au projet Firebase (FlutterFire, flavors preview/prod)

Ne pas utiliser une config unique (`lib/firebase_options.dart`) pour ce projet:
on maintient explicitement deux fichiers:
- `lib/firebase_options_preview.dart`
- `lib/firebase_options_prod.dart`

Depuis la racine du projet, lancer **les deux commandes** suivantes:

```powershell
dart pub global run flutterfire_cli:flutterfire configure --project=planerz-preview --out=lib/firebase_options_preview.dart --android-package-name=fr.centuryspine.planerz.preview --ios-bundle-id=fr.centuryspine.planerz.preview --yes
```
```powershell
dart pub global run flutterfire_cli:flutterfire configure --project=planerz --out=lib/firebase_options_prod.dart --android-package-name=fr.centuryspine.planerz --ios-bundle-id=fr.centuryspine.planerz --yes
```

Notes importantes:
- Si FlutterFire propose de reutiliser des apps avec un mauvais package/bundle id, refuser et recreer les bonnes apps.
- Pour le web, il n'y a pas de package name Android/iOS, mais il faut garder une web app dediee par projet (`planerz-preview` vs `planerz`) et regenerer les options pour recuperer les bons `appId/apiKey`.
- Verifier ensuite que les fichiers Android restent bien separes par flavor:
  - `android/app/src/preview/google-services.json`
  - `android/app/src/prod/google-services.json`

### 8. Lancer l'application

```powershell
flutter clean
flutter pub get
flutter run -d windows
```

Flux de test minimal:
- Ecran **Connexion** -> bouton *Continuer avec Google*
- Ecran **Mes voyages**
- Bouton **Nouveau voyage** -> creation visible dans Firestore (`trips`)
- Document utilisateur cree/maj dans Firestore (`users/{uid}`)

## Emulateurs Firebase (developpement local)

Le depot est configure pour parler aux emulateurs **Auth**, **Firestore**, **Cloud Functions** et **Storage** sur ta machine, **uniquement** quand tu compiles la cible **preview** avec le flag Dart `USE_FIREBASE_EMULATOR=true` (voir `lib/core/firebase/firebase_emulator_wiring.dart`). Les ports correspondent a `firebase.json` :

| Service    | Port |
|-----------|------|
| Auth      | 9099 |
| Firestore | 8080 |
| Functions | 5001 |
| Storage   | 9199 |
| Emulator UI | 4000 |

### Demarrer les emulateurs

Depuis la racine du repo, apres `cd functions` + `npm install` :

```powershell
firebase emulators:start
```

Avec **sauvegarde de l’etat** entre deux sessions (dossier local, a ne pas commiter tel quel si tu y mets des donnees sensibles) :

```powershell
firebase emulators:start --import=.\emulator-data --export-on-exit=.\emulator-data
```

- **Sans** `--import` / `--export-on-exit` : au prochain arret des emulateurs, les donnees Firestore / Auth / Storage locales sont en general **perdues** (comportement par defaut en memoire).
- **Avec** ces flags : un snapshot est ecrit dans `emulator-data` a la fermeture et recharge au demarrage suivant (creer le dossier ou faire un premier run avec export si besoin). Le depot ignore `emulator-data/` et `firestore-debug.log` dans `.gitignore` pour eviter des commits accidentels.

L’**Emulator UI** : `http://127.0.0.1:4000/`.

### Lancer l’app contre les emulateurs

Exemple (Web) :

```powershell
flutter run -d chrome -t lib/main_preview.dart --dart-define=USE_FIREBASE_EMULATOR=true
```

- **Android emulateur** : l’app utilise automatiquement l’hote `10.0.2.2` pour joindre la machine (voir `FirebaseEmulatorWiring`).
- **Appareil physique** : definir l’IP de ta machine, par exemple  
  `--dart-define=FIREBASE_EMULATOR_HOST=192.168.1.10`.

### Attention : emulateurs partiels et production

Si tu demarres seulement une partie des services, la CLI peut **avertir** que les appels vers les services **non demarres** (ex. Pub/Sub, Hosting, Realtime Database, etc.) peuvent encore partir vers **la vraie infrastructure** du projet configure dans `firebase.json` / `FIREBASE_CONFIG`. Verifie toujours le bandeau de demarrage et ne melange pas comptes / donnees prod par megarde.

Les **extensions** et le **Pub/Sub** emulateur ne sont pas dans la config courante : certaines fonctions planifiees (ex. cleanup dependant de Pub/Sub) peuvent etre **ignorees** en local tant que l’emulateur correspondant n’est pas lance.

### Logs et fichiers locaux

- `firebase-debug.log` (racine) : log CLI Firebase.
- `firestore-debug.log` : log de l’emulateur Firestore (souvent cree au demarrage Firestore).

### Cloud Functions en local (piege connu de l’emulateur)

Le runtime de l’emulateur Functions remplace `admin.firestore` par une fonction liee avec `.bind()`, ce qui fait **disparaitre** les proprietes statiques comme `FieldValue` sur `admin.firestore`. En consequence, le code des fonctions doit utiliser `FieldValue` via `require('firebase-admin/firestore')` (comme dans `functions/index.js`), sinon certains appels (ex. `arrayUnion`) echouent **uniquement** en emulateur alors que le **deploy preview / prod** fonctionne. Contexte detaille : conversation agent Cursor `e687cf9b-cf83-417b-8ace-c912944da8d8`.

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

```powershell
firebase login
```

- Installer les dependances des fonctions:

```powershell
cd functions
npm install
cd ..
```

### Deploiement

Depuis la racine du repo:

```powershell
firebase deploy --only functions --project planerz
```

Au premier deploy, Firebase peut demander une politique de retention des images de conteneur (Artifact Registry). Recommandation: `30` jours.

### Verification apres deploy

1. Dans l'app, modifier un voyage et renseigner un `linkUrl`.
2. Dans Firestore (`trips/{tripId}`), verifier le champ `linkPreview`:
   - `status: "loading"` puis `status: "ok"` (ou `empty` / `error`)
   - champs attendus: `title`, `description`, `siteName`, `imageUrl`, `fetchedAt`

### Redeployer apres modif de la function

Si tu modifies `functions/index.js`:

```powershell
firebase deploy --only functions --project planerz
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

## Licence

Ce projet est distribue sous licence GNU AGPL v3 (ou version ulterieure).
Voir le fichier `LICENSE`.
