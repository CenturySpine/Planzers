# Plan de migration — Chat custom → flyer.chat SDK

## Contexte

Le chat actuel est entièrement custom : `ChatWidget` (~1 000 lignes) gère la liste, le scroll, la sélection, les réactions, l'édition, la suppression et la barre de saisie. La couche données (`TripMessagesRepository`, providers Riverpod) alimente ce widget via des streams Firestore.

Les problèmes identifiés :
- Rebuild complet du `ListView` à chaque changement de message ou de réaction.
- État de pagination (`_olderCursor`, `_olderMessagesById`) porté dans le `State` du widget de page.
- Réactions chargées pour tous les messages du voyage, même hors écran.
- Widget difficile à faire évoluer (reply-to, statuts d'envoi, pièces jointes).

**Objectif :** remplacer toute l'infrastructure client du chat par le SDK [flyer.chat](https://pub.dev/packages/flutter_chat_ui) (`flutter_chat_ui` v2.x + `flutter_chat_core`), qui fournit une liste animée granulaire (`ChatAnimatedList`) pilotée par un `Stream<ChatOperation>` — seule opération modifiée = seul item animé.

---

## Périmètre : ce qui est conservé, ce qui est supprimé

### Conservé intégralement — ne pas toucher

| Élément | Chemin | Raison |
|---|---|---|
| Schéma et données Firestore | `trips/{id}/messages/` + sous-collection `reactions/` | Aucune migration de données |
| `TripMessage` | `lib/features/messaging/data/trip_message.dart` | Modèle domaine, inchangé |
| `TripMessageReaction` | `lib/features/messaging/data/trip_message_reaction.dart` | Idem |
| `TripMessageThreadScope` | `lib/features/messaging/data/trip_message_thread_scope.dart` | Idem |
| `TripMessagesRepository` | `lib/features/messaging/data/trip_messages_repository.dart` | Toutes les opérations Firestore restent |
| Providers Riverpod | Dans le repository | `tripChatDataScopedStreamProvider` et ses variantes restent |
| Logique de présence et de read marks | Dans `TripThreadMessagingPage` | Indépendante du widget UI |
| Tabs admin / main | Dans `TripThreadMessagingPage` | Indépendants du widget UI |
| `NotificationCenterRepository` | Core | Indépendant |

### Supprimé — repartir de zéro côté client

| Élément | Chemin | Remplacé par |
|---|---|---|
| `ChatWidget` (entier) | `lib/features/messaging/presentation/chat_widget.dart` | Widget `Chat` du SDK |
| État de pagination dans la page | `_TripThreadMessagingPageState` : `_olderCursor`, `_olderMessagesById`, `_olderReactionsByMessage`, `_hasMoreOlder`, `_loadingOlder`, `_loadOlderMessages()` | `FirestoreChatController.insertAllMessages()` |
| Logique de merge messages (stream + paginated) | `build()` de `_TripThreadMessagingPageState` | Absorbée par le contrôleur |
| `_chatListEntry`, `_ReactionGroup`, `_groupReactions()` | Fin de `chat_widget.dart` | Builders custom du SDK |
| `_MessageDayPill` | `chat_widget.dart` | `messageListOptions.dateSeparatorBuilder` |
| `_InlineMessageQuickReactionBar` | `chat_widget.dart` | Builder custom dans `Builders` |
| `_MessageReactionsBadge` | `chat_widget.dart` | Builder custom dans `Builders` |
| `_ScrollToBottomButton` | `chat_widget.dart` | `ScrollToBottomOptions` du SDK |
| Dépendance `emoji_picker_flutter` | `pubspec.yaml` | Conservée si on garde le picker custom, sinon retirer |

---

## Nouvelles dépendances

```yaml
# pubspec.yaml — à ajouter
dependencies:
  flutter_chat_ui: ^2.11.1
  flutter_chat_core: ^2.9.0
  flyer_chat_text_message: ^<dernière_version>  # rendu des bulles texte
  provider: ^6.1.5                              # requis par flutter_chat_ui (coexiste avec Riverpod)
```

`intl: ^0.20.2` (Planerz) est compatible avec `flutter_chat_core` (`intl: >=0.19.0 <1.0.0`). Aucun conflit.

---

## Nouveaux fichiers à créer

```
lib/features/messaging/
├── data/
│   └── trip_message_mapper.dart          # TripMessage → Message (flyer.chat)
├── chat_controller/
│   └── firestore_chat_controller.dart    # Implémente ChatController
└── presentation/
    ├── chat_builders.dart                # Builders custom (avatar, réactions, etc.)
    └── trip_messaging_page.dart          # Remplace l'existant (réduit)
```

---

## Étapes de migration

### Étape 1 — Dépendances

Ajouter `flutter_chat_ui`, `flutter_chat_core`, `flyer_chat_text_message`, `provider` dans `pubspec.yaml`. Lancer `flutter pub get`. Vérifier l'absence de conflits.

---

### Étape 2 — Mapper `TripMessage` → `Message`

Créer `trip_message_mapper.dart`. C'est une fonction pure, sans état.

```dart
// Conversion du format réactions :
// Planerz  : List<TripMessageReaction> → {userId: emoji}  (un emoji par user)
// flyer.chat: Map<String, List<UserID>> → {emoji: [uid, uid, ...]}
Map<String, List<String>> _mapReactions(List<TripMessageReaction> reactions) {
  final result = <String, List<String>>{};
  for (final r in reactions) {
    result.putIfAbsent(r.emoji.trim(), () => []).add(r.userId);
  }
  return result;
}

Message mapTripMessage(
  TripMessage m,
  List<TripMessageReaction> reactions,
) {
  return Message.text(
    id: m.id,
    authorId: m.authorId,
    text: m.text,
    createdAt: m.createdAt.millisecondsSinceEpoch,
    updatedAt: m.updatedAt?.millisecondsSinceEpoch,
    editedAt: m.wasEdited ? m.updatedAt?.millisecondsSinceEpoch : null,
    reactions: reactions.isEmpty ? null : _mapReactions(reactions),
    metadata: {
      'threadType': m.threadType.value,
      'visibilityType': m.visibilityType.value,
    },
  );
}
```

---

### Étape 3 — `FirestoreChatController`

C'est la pièce centrale. Elle implémente `ChatController` (interface de `flutter_chat_core`) en pilotant l'état interne à partir du stream Riverpod existant.

**Responsabilités :**
- S'abonner au stream `tripChatDataScopedStreamProvider`.
- À chaque émission, calculer le diff entre l'état précédent et le nouvel état (messages ajoutés, modifiés, supprimés).
- Appeler `insertMessage`, `updateMessage`, `removeMessage` sur l'état interne — ce qui alimente le `operationsStream` consommé par `ChatAnimatedList`.
- Exposer `insertAllMessages(olderMessages, index: 0)` pour la pagination "load older".
- Se disposer proprement (`StreamSubscription.cancel()`).

**Ce qu'elle ne fait pas :**
- Aucun appel Firestore direct — tout passe par `TripMessagesRepository`.
- Aucune logique métier (permissions, scopes) — ce n'est pas son rôle.

**Cycle de vie :** instanciée dans un provider Riverpod `autoDispose.family` scopé sur `TripMessageThreadRequest`. Se dispose automatiquement quand le scope n'est plus watché.

```dart
// Provider — un contrôleur par (tripId, scope)
final firestoreChatControllerProvider = AutoDisposeProvider
    .family<FirestoreChatController, TripMessageThreadRequest>(
  (ref, request) {
    final controller = FirestoreChatController(
      stream: ref.watch(tripChatDataScopedStreamProvider(request)),
      reactionsByMessageStream: ref.watch(
        tripMessageReactionsStreamProvider(request.tripId),
      ),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
);
```

**Gestion du diff :** comparer la liste précédente et la nouvelle par ID. Les IDs présents uniquement dans la nouvelle → `insertMessage`. Les IDs dans les deux mais avec `updatedAt` différent → `updateMessage`. Les IDs absents de la nouvelle → `removeMessage`. Cette comparaison est O(n) mais n est borné à 50 (taille de la fenêtre stream).

---

### Étape 4 — Builders custom

Créer `chat_builders.dart`. Fournit les customisations visuelles à passer dans `Builders(...)`.

**Avatar (`avatarBuilder`) :** utilise le `ProfileBadge` Planerz existant en lisant `userDocs[user.id]`.

**Bulle de message (`messageBuilder` ou builder `flyer_chat_text_message`) :** conserver l'apparence actuelle (couleurs `primaryContainer` / `surfaceContainerHighest`, radius 12, heure + indicateur d'édition).

**Réactions (`bottomMessageBuilder` ou overlay) :** afficher le badge `_MessageReactionsBadge` équivalent (emojis groupés + compteur), repositionné en overlay sous la bulle. Tap sur une réaction → toggle via `onSetReaction` / `onRemoveReaction` du repository.

**Barre de réaction rapide (sélection) :** reproduire `_InlineMessageQuickReactionBar` dans `onMessageLongPress`, déclenché par le long press natif du SDK.

**Séparateurs de date (`dateSeparatorBuilder`) :** reproduire `_MessageDayPill` (pill centrée, "Aujourd'hui" / "Hier" / date longue).

**Load older (`loadMoreBuilder`) :** spinner centré 18×18, identique à l'actuel.

**Scroll to bottom (`scrollToBottomBuilder`) :** reproduire `_ScrollToBottomButton`.

---

### Étape 5 — `resolveUser`

Le widget `Chat` résout les auteurs de façon asynchrone via un callback :

```dart
Future<User> resolveUser(String userId) async {
  return User(
    id: userId,
    name: authorLabels[userId] ?? l10n.roleParticipant,
    imageSource: null, // on utilise avatarBuilder, pas imageSource
    metadata: {'userData': userDocs[userId]},
  );
}
```

`imageSource` est laissé null car l'avatar est rendu via `avatarBuilder` avec `ProfileBadge` (URLs internes Firestore, pas Google-hosted — cf. guidelines).

---

### Étape 6 — Réécrire `TripThreadMessagingPage`

Supprimer tout l'état de pagination (`_olderCursor`, `_olderMessagesById`, etc.) et le bloc de merge dans `build()`. Conserver uniquement :
- `_syncPresenceIfNeeded`
- `_markMessagesAsReadIfNeeded`
- `_isMessagingTabCurrentlyVisible`
- `dispose()` (clearOpenChannel)

Remplacer le `ChatWidget(...)` par :

```dart
Chat(
  currentUserId: myUid ?? '',
  chatController: ref.watch(firestoreChatControllerProvider(request)),
  resolveUser: resolveUser,
  builders: buildChatBuilders(
    context: context,
    currentUserId: myUid,
    userDocs: userDocs,
    authorLabels: memberLabels,
    onSetReaction: (msgId, emoji) => repo.setMyReaction(...),
    onRemoveReaction: (msgId) => repo.removeMyReaction(...),
    onEdit: (msg) => _editMessage(msg),
    onDelete: (msg) => _deleteMessage(msg),
    onCopy: (msg) => _copyMessage(msg),
    onLoadOlder: () => chatController.loadOlderPage(repo: repo),
  ),
  onMessageSend: (msg) => repo.sendMessage(
    tripId: trip.id,
    text: msg.text,
    scope: scope,
  ),
  theme: buildChatTheme(context),
)
```

---

### Étape 7 — Suppression du `ChatWidget`

Une fois le `Chat` SDK branché et validé : supprimer `chat_widget.dart` en entier.

---

### Étape 8 — Nettoyage

- Retirer les imports de `ChatWidget` partout.
- Vérifier si `emoji_picker_flutter` est encore utilisé ailleurs dans l'app ; si non, le retirer de `pubspec.yaml`.
- Lancer `flutter analyze` et corriger les nouveaux warnings.
- Tester les deux threads (main + admin), la pagination load-older, les réactions, l'édition et la suppression.

---

## Points d'attention

**Réactions :** le modèle `Message` de flyer.chat porte `reactions: Map<String, List<UserID>>`. Le rendu visuel (badge, barre rapide) est entièrement custom via les builders — il ne dépend pas du package `flyer_chat_text_message` pour cela.

**Pagination :** `insertAllMessages(messages, index: 0)` insère les anciens messages en tête. Le `ChatAnimatedList` les anime correctement. Il faut s'assurer que le contrôleur ne réinsère pas des messages déjà présents (vérification par ID avant insertion).

**Multiples instances :** chaque `TripMessageThreadRequest(tripId, scope)` produit un contrôleur indépendant via le provider family. Les futurs threads (carpool, courses, etc.) s'ajoutent simplement avec un nouveau `TripMessageThreadScope.object(...)` — aucune modification de l'infrastructure.

**`provider` vs Riverpod :** `flutter_chat_ui` utilise le package `provider` en interne pour son arbre de widgets. Cela coexiste sans conflit avec Riverpod, qui reste la couche de state management de Planerz.

**Aucune migration Firestore :** le schéma `trips/{id}/messages/{id}` et la sous-collection `reactions/{userId}` sont conservés tels quels. Le mapper lit les mêmes champs qu'aujourd'hui.
