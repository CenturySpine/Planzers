# Plan de refactoring — Système de membres de voyage

## Contexte et objectif

Remplacer le système de membres actuel, basé sur `memberIds: List<String>` (UIDs + identifiants temporaires `ph_xxx`) et `memberPublicLabels: Map<String, String>` sur le document `Trip`, par une sous-collection `participants` dédiée.

L'objectif est triple :
- Supprimer les identifiants `ph_xxx` et toute la logique de migration associée
- Unifier la représentation d'un participant (nom + userid) en un seul objet
- Simplifier les règles Firestore en les ramenant à leur rôle légitime : authentification + appartenance au voyage

## Périmètre

**Dans le scope :**
- Nouveaux voyages uniquement
- Dart (modèle, providers, UI)
- Cloud Functions
- Règles Firestore

**Hors scope :**
- Migration des voyages existants
- Renommage de `driverUserId` → `driverMemberId` dans le covoiturage
- Modification de la granularité des permissions (`TripGeneralPermissions`, etc.)

---

## Décisions d'architecture

| Sujet | Décision |
|-------|----------|
| Nom de la sous-collection | `participants` (évite la collision avec `members` existant) |
| ID du document `TripMember` | Auto-généré par Firestore (stable, utilisé comme référence dans toutes les sous-collections) |
| Vérification d'appartenance dans les règles | `memberUserIds: List<String>` sur le document `Trip` (UIDs uniquement, géré server-side) |
| Admins | `adminMemberIds: List<String>` reste sur le document `Trip` (UIDs) |
| Nom affiché | `participantName` est la source de vérité partout, y compris après le claim |
| `visibleToMemberIds` dans expenseGroups | Stocke des IDs de documents `TripMember` ; filtrage uniquement côté app, plus dans les règles |
| Références dans les sous-collections | Meals, activities, carpool, expenseGroups → tous utilisent les IDs auto-générés de `TripMember` |
| Départ d'un membre | Le document `TripMember` est supprimé (pas remis à `userId: null`) |
| Règles Firestore | Simplifiées : authentifié + membre du voyage uniquement. La logique métier (`visibleToMemberIds`, permissions granulaires) est exclusivement côté app |

---

## Modèle de données cible

### Document `Trip` (champs modifiés)

```
Supprimé : memberIds: List<String>
Supprimé : memberPublicLabels: Map<String, String>
Ajouté   : memberUserIds: List<String>   ← UIDs uniquement, géré server-side pour les règles
Conservé : adminMemberIds: List<String>  ← UIDs des co-admins
```

### Sous-collection `trips/{tripId}/participants/{autoId}`

```
participantName : String    ← saisi par l'organisateur, nom affiché partout
userId          : String?   ← null jusqu'au claim, UID Firebase après
```

### Références dans les autres sous-collections

| Sous-collection | Champ | Contient maintenant |
|-----------------|-------|---------------------|
| `expenseGroups` | `visibleToMemberIds` | IDs de documents `TripMember` |
| `meals` | `participantIds`, `chefParticipantId` | IDs de documents `TripMember` |
| `activities` | `votes` | IDs de documents `TripMember` |
| `carpool` | `driverUserId`, `participantIds` | IDs de documents `TripMember` |

---

## Phases d'implémentation

### Phase 1 — Modèle de données Dart

**Créer** `lib/features/trips/data/trip_member.dart` :
```dart
class TripMember {
  final String id;             // document ID auto-généré
  final String participantName;
  final String? userId;        // null jusqu'au claim
}
```
Inclure `fromMap`, `toMap`, `copyWith`.

**Modifier** `lib/features/trips/data/trip.dart` :
- Supprimer : `memberIds`, `memberPublicLabels`, `memberPublicLabelsFromFirestore()`
- Ajouter : `memberUserIds: List<String>`
- Mettre à jour `fromMap()`, `toMap()`

**Créer** `lib/features/trips/data/trip_members_repository.dart` :
- `streamParticipants(tripId)` → Stream sur la sous-collection
- `addParticipant(tripId, participantName)` → crée le document
- `removeParticipant(tripId, memberId)` → supprime le document
- `claimParticipant(tripId, memberId, userId)` → set `userId` sur le document existant

**Supprimer** `lib/features/trips/data/trip_placeholder_member.dart`

---

### Phase 2 — Providers Riverpod

Créer `tripMembersProvider(tripId)` qui streame `participants`.

Partout où le code passe `memberIds` + `memberPublicLabels` en paramètres séparés (21+ fichiers), remplacer par `List<TripMember>` issue du provider. Une seule prop au lieu de deux.

Fichiers principaux à mettre à jour :
- `trip_expenses_page.dart` (le plus dense : 20+ usages)
- `trip_meals_page.dart`, `trip_meal_details_page.dart`
- `trip_activities_page.dart`, `trip_activity_detail_page.dart`
- `trip_carpool_page.dart`, `trip_carpool_form_page.dart`
- `trip_rooms_page.dart`
- `trip_participants_page.dart`
- `trip_messaging_page.dart`
- `trip_games_page.dart`
- `expense_group_editor_page.dart`

---

### Phase 3 — Cloud Functions

#### Fonctions à réécrire

| Fonction actuelle | Nouvelle fonction | Changement |
|-------------------|-------------------|------------|
| `addTripPlaceholderMember` | `addTripParticipant` | Crée un doc `participants/{autoId}` avec `participantName` seulement, sans `ph_xxx` |
| `removeTripPlaceholderMember` | `removeTripParticipant` | Supprime le doc `participants/{autoId}` + retire l'UID de `memberUserIds` si réclamé |
| `getInviteJoinContext` | Réécrire | Renvoie la liste des `TripMember` avec `userId == null` (au lieu des `ph_xxx`) |
| `completeJoinTripWithInvite` | Réécrire | Claim = set `userId` sur le doc existant + add UID dans `memberUserIds`; ou créer nouveau doc si pas de slot |
| `joinTripWithInvite` | Adapter | Appelle la nouvelle `completeJoinTripWithInvite` |
| `leaveTrip` | Adapter | Supprime le doc `TripMember` + retire l'UID de `memberUserIds` |
| `backfillNewTripMemberInExpenses` | Adapter | Détecter les ajouts à `memberUserIds` au lieu de `memberIds` |

#### Fonctions à supprimer

- `migrateTripMemberIdReferences` — plus nécessaire (l'ID `TripMember` ne change pas au claim)
- `adminMemberIdsAfterPlaceholderClaim` — plus nécessaire
- Helpers : `isPlaceholderMemberId()`, `newTripPlaceholderMemberId()`, `memberIdsAsSet()` (ou adapter)

#### Flux d'adhésion (join flow) — comportement cible

**Cas 1 — L'utilisateur sélectionne un nom existant :**
1. `getInviteJoinContext` renvoie les `TripMember` non réclamés (`userId == null`)
2. L'utilisateur choisit son nom dans la liste
3. `joinTripWithInvite` → set `userId` sur le doc existant + add UID dans `memberUserIds`

**Cas 2 — L'utilisateur rejoint avec son profil directement :**
1. `joinTripWithInvite` → crée un nouveau doc `participants/{autoId}` avec `userId` + `participantName` par défaut (numéro de téléphone ou partie gauche de l'email)

---

### Phase 4 — Règles Firestore

#### Simplification de `isTripMember()`

```javascript
// AVANT
function isTripMember(tripId) {
  return request.auth.uid in tripDoc(tripId).data.memberIds;
}

// APRÈS
function isTripMember(tripId) {
  return request.auth.uid in tripDoc(tripId).data.memberUserIds;
}
```

#### Règles à supprimer

- Toutes les règles relatives à `memberPublicLabels` (create / edit / delete placeholder, self-label update)
- La vérification `visibleToMemberIds` dans les règles `expenseGroups` (logique métier → côté app)
- Les règles de mise à jour de `memberIds` liées aux opérations placeholder

#### Règles à adapter

- Trip create : remplacer `memberIds` par `memberUserIds` dans la validation
- Trip list query : le `where('memberIds', arrayContains: uid)` dans `account_repository.dart` devient `where('memberUserIds', arrayContains: uid)`

---

### Phase 5 — Audit et consolidation du filtrage client

Pour chaque règle Firestore supprimée, vérifier que le comportement équivalent existe dans le code Flutter.

| Règle supprimée | Vérification côté app |
|----------------|----------------------|
| `visibleToMemberIds` dans expenseGroups | S'assurer que le filtre est appliqué dans le provider ou la requête Firestore avant exposition aux widgets — vérifier l'exhaustivité (page principale, sélecteurs, formulaires) |
| `memberPublicLabels.{uid}` write rule | Confirmer qu'aucun code Flutter n'écrit encore ce champ |

---

### Phase 6 — UI et résolution des noms

**`invite_join_page.dart`** — réécrire le flow :
- Afficher les `TripMember` non réclamés par leur `participantName`
- Cas 1 : sélection d'un nom existant → claim
- Cas 2 : rejoindre sans sélection → nouveau `TripMember` avec nom par défaut

**`trip_participants_page.dart`** — supprimer toute la logique `ph_xxx` :
- `addTripPlaceholderMember()` → `addTripParticipant()`
- `updateTripPlaceholderMemberName()` → update de `participantName` sur le doc `TripMember`
- `removeTripPlaceholderMember()` → `removeParticipant()`

**Résolution du nom d'affichage** :
- Supprimer la logique de fallback `memberPublicLabels` dans `user_display_label.dart`
- Utiliser `TripMember.participantName` directement

**Résolution du badge utilisateur — adaptation de `user_display_label.dart`** :

Le helper actuel résout label + photo à partir de `(memberId, userData, tripMemberPublicLabels)`.
Avec le nouveau modèle, l'entrée devient un `TripMember`.

Stratégie de résolution :

| Cas | Nom affiché | Photo du badge |
|-----|------------|----------------|
| Membre non réclamé (`userId == null`) | `participantName` | Aucune — initiale via `avatarInitialFromDisplayLabel(participantName)` |
| Membre réclamé (`userId` renseigné) | `participantName` | Lookup `users/{userId}` → `tripMemberStoredProfileBadgeUrl(userData)` |

Fonctions à réécrire dans `user_display_label.dart` :

- `resolveTripMemberDisplayLabel` → signature simplifiée, prend un `TripMember`, retourne `member.participantName` directement (plus de `userData` ni de `tripMemberPublicLabels`)
- `resolveTripMemberBadgeUrl(TripMember member, Map<String, Map<String, dynamic>> userDocsById)` → retourne `''` si `userId == null`, sinon `tripMemberStoredProfileBadgeUrl(userDocsById[member.userId])`
- `tripMemberLabelsFromUserDocsById` / `tripMemberLabelsFromUserQuerySnapshot` → remplacer par des helpers prenant `List<TripMember>` ; la map de user docs est désormais indexée par **UID** (pas par memberId)

La requête Firestore pour charger les user docs change en conséquence :
```dart
// AVANT : charger users où documentId in memberIds (UIDs + ph_xxx)
// APRÈS : charger users où documentId in [m.userId for m in participants where m.userId != null]
```

`tripMemberUserDataWithAuthFallback` reste utile pour l'utilisateur courant dans la fenêtre où son user doc n'est pas encore chargé (badge provisoire à l'entrée dans un voyage).

**`account_repository.dart`** :
- Ligne 230 : `where('memberIds', arrayContains: uid)` → `where('memberUserIds', arrayContains: uid)`
- Lignes 241–245 : supprimer les écritures sur `memberPublicLabels`

---

## Fichiers impactés — récapitulatif

### Supprimés
- `lib/features/trips/data/trip_placeholder_member.dart`

### Créés
- `lib/features/trips/data/trip_member.dart`
- `lib/features/trips/data/trip_members_repository.dart`

### Modifiés (Dart — 24 fichiers)
- `lib/features/trips/data/trip.dart`
- `lib/features/trips/data/trips_repository.dart`
- `lib/features/trips/data/trip_permission_helpers.dart`
- `lib/features/trips/data/trip_announcements_repository.dart`
- `lib/features/account/data/account_repository.dart`
- `lib/features/expenses/data/expenses_repository.dart`
- `lib/features/expenses/data/expense_group.dart`
- `lib/features/expenses/presentation/trip_expenses_page.dart`
- `lib/features/expenses/presentation/expense_group_editor_page.dart`
- `lib/features/meals/presentation/trip_meals_page.dart`
- `lib/features/meals/presentation/trip_meal_details_page.dart`
- `lib/features/meals/presentation/trip_meal_card.dart`
- `lib/features/activities/presentation/trip_activities_page.dart`
- `lib/features/activities/presentation/trip_activity_detail_page.dart`
- `lib/features/activities/presentation/trip_activity_searchable_tab_list.dart`
- `lib/features/activities/presentation/trip_category_suggestions_panel.dart`
- `lib/features/carpool/presentation/trip_carpool_page.dart`
- `lib/features/carpool/presentation/trip_carpool_form_page.dart`
- `lib/features/rooms/presentation/trip_rooms_page.dart`
- `lib/features/messaging/presentation/trip_messaging_page.dart`
- `lib/features/games/presentation/trip_games_page.dart`
- `lib/features/trips/presentation/trip_participants_page.dart`
- `lib/features/trips/presentation/invite_join_page.dart`
- `lib/features/trips/presentation/trip_overview_page.dart`
- `lib/features/trips/presentation/trip_shell_page.dart`
- `lib/features/trips/presentation/trips_page.dart`
- `lib/features/auth/data/user_display_label.dart`

### Modifiés (infrastructure)
- `functions/index.js`
- `firestore.rules`
