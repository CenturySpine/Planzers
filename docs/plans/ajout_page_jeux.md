## Ajout page Jeux — Plan d'action

### Objectif produit
- Depuis la page d’aperçu d’un voyage, la tuile `Jeux` ouvre une nouvelle page.
- La page affiche un titre, puis un contrôle d’onglets (TabBar) avec un seul onglet pour l’instant: `Jeux de société`.
- Dans cet onglet, tout membre du voyage peut ajouter un jeu (nom libre + URL optionnelle).
- Chaque ligne affiche: badge utilisateur (créateur) à gauche, miniature d’image de preview à droite.
- Clic sur une ligne: popup d’édition (nom + URL + actions enregistrer/supprimer), sans possibilité de changer le créateur.
- Règle d’accès: créateur + rôles `>= admin` peuvent éditer/supprimer.

### Points d’intégration repérés
- La tuile existe déjà dans l’aperçu, mais son `onTap` est vide dans [`lib/features/trips/presentation/trip_overview_page.dart`](lib/features/trips/presentation/trip_overview_page.dart).
- Pattern TabBar déjà utilisé sur les dépenses dans [`lib/features/expenses/presentation/trip_expenses_page.dart`](lib/features/expenses/presentation/trip_expenses_page.dart).
- Pattern d’affichage des previews déjà prêt via:
  - `LinkPreviewCardFromFirestore` et `LinkPreviewThumbnail` dans [`lib/features/trips/presentation/link_preview_from_firestore.dart`](lib/features/trips/presentation/link_preview_from_firestore.dart).
- Pattern Cloud Functions Gen2 + region déjà en place dans [`functions/index.js`](functions/index.js) avec `setGlobalOptions({ region: 'europe-west9' })` et des triggers Firestore `onDocumentCreated/onDocumentUpdated`.
- Firestore rules: les sous-collections de voyage sont protégées par `isTripMember(tripId)` et des conditions spécifiques dans [`firestore.rules`](firestore.rules).

### Organisation des données (Firestore)
Créer une sous-collection dédiée sous chaque voyage:
- Collection: `trips/{tripId}/boardGames/{gameId}`
- Document `boardGames` (champs minimaux, en anglais):
  - `name` (string) — nom affiché/éditable
  - `linkUrl` (string) — URL saisie, optionnelle
  - `linkPreview` (map) — même shape que le reste de l’app:
    - `status`: `loading|ok|empty|error`
    - `url`, `title`, `description`, `siteName`, `imageUrl`, `error`, `fetchedAt`
  - `createdBy` (string uid)
  - `createdAt` (timestamp server)
  - `updatedAt` (timestamp server)

Index/tri recommandé:
- Lecture: orderBy `createdAt` (desc) pour afficher les derniers ajouts en premier.

### Cloud Function dédiée “board games preview”
#### Principe
- La génération de preview doit continuer même si l’utilisateur ferme la popup: on s’appuie sur un trigger Firestore (comme `generateActivityLinkPreview`), pas sur un appel direct depuis l’UI.

#### Déclencheurs
Dans [`functions/index.js`](functions/index.js), ajouter 2 fonctions (sur le modèle existant activités/repas):
- `exports.generateTripBoardGameLinkPreviewOnCreate = onDocumentCreated({ document: 'trips/{tripId}/boardGames/{gameId}', ... }, ...)`
- `exports.generateTripBoardGameLinkPreview = onDocumentUpdated({ document: 'trips/{tripId}/boardGames/{gameId}', ... }, ...)`

#### Comportement
- Réutiliser la fonction interne existante `generateLinkPreview(docRef, beforeUrl, afterUrl, previewField)` en passant:
  - `before.linkUrl`, `after.linkUrl`, `previewField='linkPreview'`
- Pour garantir l’expérience UI:
  - Quand l’UI écrit/modifie `linkUrl`, elle force `linkPreview.status='loading'` (ou vide `linkPreview`) afin que la liste affiche un loader via `LinkPreviewThumbnail`.
- Règle de remplacement du nom:
  - Après génération réussie, si `linkPreview.status == 'ok'` et que `linkPreview.title` est non vide, alors la function met à jour `name` avec `linkPreview.title`.
  - Cette mise à jour est faite côté serveur (Admin SDK), donc persistée en BDD même si l’utilisateur a quitté la popup.
  - Protéger contre les boucles: n’update `name` que si différent de `linkPreview.title`.

### Sécurité (firestore.rules)
Dans [`firestore.rules`](firestore.rules), ajouter un match dédié:
- `match /trips/{tripId}/boardGames/{gameId}`
  - `allow read: if isTripMember(tripId);`
  - `allow create: if isTripMember(tripId) && request.resource.data.createdBy == request.auth.uid;`
  - `allow update, delete: if isTripMember(tripId) && (resource.data.createdBy == request.auth.uid || tripCallerRoleRank(tripId) >= 2);`
  - (Option) Restreindre les champs modifiables côté client (éviter qu’un client injecte `linkPreview` arbitrairement):
    - autoriser update client uniquement sur `name`, `linkUrl`, `updatedAt`, et laisser `linkPreview` être écrit par les Functions.

### UI / Navigation
#### Route
- Ajouter la route GoRouter: `/trips/:tripId/games` dans [`lib/app/router.dart`](lib/app/router.dart), proche des autres routes “trip pages”.

#### Entrée depuis la tuile
- Remplacer `onTap: () {}` de la tuile Jeux dans [`lib/features/trips/presentation/trip_overview_page.dart`](lib/features/trips/presentation/trip_overview_page.dart) par une navigation vers `/trips/${tripId}/games`.

#### Page `TripGamesPage`
Créer une page dédiée (nouveau feature module):
- [`lib/features/games/presentation/trip_games_page.dart`](lib/features/games/presentation/trip_games_page.dart)

Contenu:
- `Scaffold`
  - `AppBar(title: l10n.tripGamesTitle)`
  - Body:
    - Titre en haut (si vous voulez un titre distinct du AppBar, sinon l’AppBar fait foi)
    - `TabBar` + `TabBarView` (1 onglet): `Jeux de société`
    - Liste `StreamProvider` des `boardGames` du voyage

Ligne de liste:
- `leading`: badge utilisateur (réutiliser la logique déjà vue dans l’overview: récupération `users` + photoUrl)
- `title`: `game.name`
- `trailing`: `LinkPreviewThumbnail(preview: game.linkPreview)`
- `onTap`: ouvre la popup d’édition

CTA ajout:
- `FloatingActionButton` ou bouton dans l’onglet, qui ouvre la popup “ajouter un jeu”.

### Popup ajout/édition (saisie)
Créer un widget/dialog réutilisable:
- 2 champs:
  - Nom (obligatoire)
  - URL (optionnel) avec validation identique à celle utilisée dans [`lib/features/activities/presentation/trip_activity_create_page.dart`](lib/features/activities/presentation/trip_activity_create_page.dart) (schéma `http/https`, `Uri.isAbsolute`).
- Submit “Enregistrer”:
  - Add: crée `boardGames/{newId}` avec `name`, `linkUrl`, `createdBy`, `createdAt`, `updatedAt`, et initialise `linkPreview.status='loading'` si URL non vide.
  - Edit: update `name`, `linkUrl`, `updatedAt` et remet `linkPreview.status='loading'` si l’URL change.
- Suppression (en édition): bouton `Supprimer` (confirm dialog), appliqué uniquement si policy (créateur ou admin+).

### Data layer (Riverpod + repository)
Créer:
- Modèle: [`lib/features/games/data/trip_board_game.dart`](lib/features/games/data/trip_board_game.dart) (fromDoc/toMap, map `linkPreview` conservée en `Map<String, dynamic>` comme ailleurs).
- Repository: [`lib/features/games/data/trip_games_repository.dart`](lib/features/games/data/trip_games_repository.dart)
  - `watchTripBoardGames(tripId)`
  - `addBoardGame(...)`
  - `updateBoardGame(...)`
  - `deleteBoardGame(...)`
- Providers:
  - `tripBoardGamesStreamProvider(tripId)`

### Localisation
Ajouter les clés ARB (FR/EN et variantes) pour:
- Titre page Jeux
- Libellé onglet “Jeux de société”
- Libellés popup (Nom, URL, Enregistrer, Supprimer, erreurs URL)

Fichiers:
- [`lib/l10n/app_fr.arb`](lib/l10n/app_fr.arb)
- [`lib/l10n/app_fr_FR.arb`](lib/l10n/app_fr_FR.arb)
- [`lib/l10n/app_en.arb`](lib/l10n/app_en.arb)
- [`lib/l10n/app_en_US.arb`](lib/l10n/app_en_US.arb)

### Tests (minimum)
- Functions: ajouter/étendre tests node (si vous avez déjà un pattern) pour vérifier:
  - un doc `boardGames` avec `linkUrl` déclenche `generateLinkPreview` et écrit `linkPreview.status`.
  - si `linkPreview.title` est non vide, `name` est remplacé.

### Déploiement (à faire par vous)
- Functions:
  - `firebase deploy --only functions --project <project>`
- Firestore rules:
  - `firebase deploy --only firestore:rules --project <project>`
- IAM (obligatoire après redeploy Functions v2): vérifier Cloud Run invoker si applicable (même si trigger Firestore, conserver votre routine standard).

