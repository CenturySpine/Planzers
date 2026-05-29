import 'dart:async';

import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/data/trip_message_mapper.dart';
import 'package:planerz/features/messaging/data/trip_message_reaction.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';

/// Riverpod provider — one controller per (tripId, scope) pair.
///
/// Auto-disposed when no longer watched; subscription cancelled on dispose.
final firestoreChatControllerProvider = Provider.autoDispose
    .family<FirestoreChatController, TripMessageThreadRequest>((ref, request) {
  final repo = ref.read(tripMessagesRepositoryProvider);
  final stream = repo.watchRecentChatData(
    request.tripId,
    pageSize: 50,
    scope: request.scope,
  );
  final controller = FirestoreChatController(stream: stream);
  ref.onDispose(controller.dispose);
  return controller;
});

/// A [ChatController] that bridges the Planerz Firestore stream with the
/// flutter_chat_core animated list.
///
/// - On each stream emission, rebuilds the full merged message list
///   (older paginated + recent) and calls [setMessages], which lets the
///   [ChatAnimatedList] run a diff and animate only what changed.
/// - [loadOlderPage] fetches older messages and prepends them to the list.
class FirestoreChatController implements ChatController {
  final InMemoryChatController _inner;
  StreamSubscription<TripChatData>? _sub;
  bool _initialized = false;

  // Pagination state
  dynamic _olderCursor; // QueryDocumentSnapshot — typed as dynamic to avoid Firestore import
  bool _hasMoreOlder = false;
  bool _isPaginating = false;

  // State from the most recent stream emission
  List<TripMessage> _recentMessages = [];
  Map<String, List<TripMessageReaction>> _recentReactions = {};

  // Older messages fetched via pagination (messageId → (message, reactions))
  final _olderById = <String, (TripMessage, List<TripMessageReaction>)>{};

  FirestoreChatController({required Stream<TripChatData> stream})
      : _inner = InMemoryChatController() {
    _sub = stream.listen(_onData, onError: (_) {});
  }

  // ── ChatController delegation ──────────────────────────────────────────

  @override
  Future<void> insertMessage(Message message, {int? index}) =>
      _inner.insertMessage(message, index: index);

  @override
  Future<void> insertAllMessages(List<Message> messages, {int? index}) =>
      _inner.insertAllMessages(messages, index: index);

  @override
  Future<void> removeMessage(Message message) => _inner.removeMessage(message);

  @override
  Future<void> updateMessage(Message oldMessage, Message newMessage) =>
      _inner.updateMessage(oldMessage, newMessage);

  @override
  Future<void> setMessages(List<Message> messages) =>
      _inner.setMessages(messages);

  @override
  List<Message> get messages => _inner.messages;

  @override
  Stream<ChatOperation> get operationsStream => _inner.operationsStream;

  @override
  void dispose() {
    _sub?.cancel();
    _inner.dispose();
  }

  // ── Public pagination state ────────────────────────────────────────────

  bool get hasMoreOlder => _hasMoreOlder;

  // ── Pagination ─────────────────────────────────────────────────────────

  /// Fetches the next page of older messages and prepends them to the list.
  ///
  /// Called by [ChatAnimatedList.onEndReached] when the user scrolls to the
  /// top. Returns immediately if there are no more messages or a fetch is
  /// already in progress.
  Future<void> loadOlderPage({
    required TripMessagesRepository repo,
    required String tripId,
    required TripMessageThreadScope scope,
  }) async {
    if (_isPaginating || !_hasMoreOlder || _olderCursor == null) return;
    _isPaginating = true;
    try {
      final page = await repo.fetchOlderChatPage(
        tripId: tripId,
        pageSize: 50,
        startAfterDoc: _olderCursor,
        scope: scope,
      );
      _olderCursor = page.nextCursor;
      _hasMoreOlder = page.hasMore && page.nextCursor != null;

      // Store paginated messages (recent messages take precedence on overlap)
      for (final m in page.data.messages) {
        if (!_recentMessages.any((rm) => rm.id == m.id)) {
          _olderById[m.id] = (m, page.data.reactionsByMessage[m.id] ?? []);
        }
      }

      _rebuildMessages();
    } catch (_) {
      // Ignore pagination errors — the user can retry by scrolling up again.
    } finally {
      _isPaginating = false;
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────

  void _onData(TripChatData data) {
    // Only initialise cursor on first emission (preserve pagination across
    // subsequent stream updates which don't reflect older pages).
    if (!_initialized) {
      _olderCursor = data.oldestLoadedDoc;
      _hasMoreOlder = data.hasPotentialOlder && _olderCursor != null;
    }

    _recentMessages = data.messages;
    _recentReactions = data.reactionsByMessage;

    // Recent messages supersede any older snapshot with the same ID
    for (final m in _recentMessages) {
      _olderById.remove(m.id);
    }

    _rebuildMessages();
    _initialized = true;
  }

  void _rebuildMessages() {
    // Merge: older (sorted by createdAt) + recent (sorted by createdAt)
    // Recent messages appear after all older ones. IDs are unique.
    final olderSorted = _olderById.values.toList()
      ..sort((a, b) => a.$1.createdAt.compareTo(b.$1.createdAt));

    final allMapped = <Message>[
      for (final entry in olderSorted) mapTripMessage(entry.$1, entry.$2),
      for (final m in _recentMessages)
        mapTripMessage(m, _recentReactions[m.id] ?? []),
    ];

    // Always non-animated: using animated:true on a setMessages diff causes
    // a key collision when _onChanged removes then re-inserts the same message
    // ID — both 250ms animations coexist during any concurrent layout rebuild
    // (e.g. keyboard dismiss), tripping SliverAnimatedList's ordering assertion.
    // With Duration.zero the remove animation completes synchronously before
    // the insert, so the two children never overlap.
    unawaited(_inner.setMessages(allMapped, animated: false));
  }
}
