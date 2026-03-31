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
- Sur Windows, activer **Mode developpeur** (necessaire pour les plugins Flutter avec symlinks).
- Installer la **Firebase CLI**:
  - Soit via `npm install -g firebase-tools` (**necessite Node.js**, car `npm` est fourni avec Node)
  - Soit via le binaire standalone `firebase.exe` (voir docs Firebase CLI).
- S'assurer que ces commandes fonctionnent dans un nouveau terminal:

```bash
flutter --version
dart --version
firebase --version
```

### 2. Cloner et installer les dependances

```bash
git clone <url-du-repo> Planzers
cd Planzers
flutter pub get
```

### 3. Configurer le projet Firebase

Dans la console Firebase:
- Creer ou choisir un **projet Firebase** (ex: `planzers`).
- **Authentication** → *Sign-in method* → activer **Anonymous**.
- **Firestore Database** → *Create database* → mode **test** pour le dev.

### 4. Lier Flutter au projet Firebase (FlutterFire)

Installer la CLI FlutterFire puis generer la config:

```bash
dart pub global activate flutterfire_cli
dart pub global run flutterfire_cli:flutterfire configure
```

- Selectionner le projet Firebase cree plus haut.
- Cocher au minimum la plateforme que tu utilises (par ex. **Windows**).
- Verifier que `lib/firebase_options.dart` a ete genere.

### 5. Lancer l'application

```bash
flutter run -d windows
```

Flux de test minimal:
- Ecran **Connexion** → bouton *Continuer* (auth anonyme).
- Ecran **Mes voyages**.
- Bouton **Nouveau voyage** → saisir titre + destination → verifier la creation dans Firestore (`trips`).

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

## Architecture Flutter recommandee

- Pattern: **Feature-first** + **Clean-ish architecture**
- State management: Riverpod
- Navigation: go_router
- Data: repositories (Firestore / Auth / Storage)
- Modeles: immutable + serialisation JSON

Arborescence suggeree:

```text
lib/
  app/
    app.dart
    router.dart
    theme.dart
  core/
    error/
    utils/
    widgets/
  features/
    auth/
    trips/
    carpool/
    groceries/
    meals/
    expenses/
  data/
    repositories/
    services/
```

## Prochaines etapes concretes

1. Installer Flutter et creer le projet de base.
2. Connecter Firebase avec `flutterfire configure`.
3. Implementer Auth + ecran de creation de voyage.
4. Construire les collections Firestore du MVP.
5. Ajouter les regles de securite Firestore.
