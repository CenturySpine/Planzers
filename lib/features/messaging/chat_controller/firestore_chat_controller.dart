import 'dart:async';
import 'dart:typed_data';

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
class FirestoreChatController
    with ScrollToMessageMixin, UploadProgressMixin
    implements ChatController {
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

  /// Outgoing image messages shown before Firestore confirms them.
  final _optimisticById = <String, ImageMessage>{};
  final _optimisticPreviewBytes = <String, Uint8List>{};

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
    disposeScrollMethods();
    _sub?.cancel();
    _inner.dispose();
  }

  @override
  Stream<double> getUploadProgress(String id) =>
      _inner.getUploadProgress(id);

  @override
  void updateUploadProgress(String id, double progress) =>
      _inner.updateUploadProgress(id, progress);

  @override
  void clearUploadProgress(String id) => _inner.clearUploadProgress(id);

  Uint8List? optimisticPreviewBytes(String messageId) =>
      _optimisticPreviewBytes[messageId];

  /// Inserts a local image bubble while upload and Firestore write run.
  Future<void> insertOptimisticImage({
    required ImageMessage message,
    required Uint8List previewBytes,
  }) async {
    _optimisticById[message.id] = message;
    _optimisticPreviewBytes[message.id] = previewBytes;
    _rebuildMessages();
  }

  Future<void> markOptimisticImageFailed(String messageId) async {
    final current = _optimisticById[messageId];
    if (current == null) return;
    _optimisticById[messageId] = current.copyWith(
      status: MessageStatus.error,
      failedAt: DateTime.now().toUtc(),
    );
    clearUploadProgress(messageId);
    _rebuildMessages();
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

    _dropConfirmedOptimisticMessages();
    _rebuildMessages();
    _initialized = true;
  }

  void _dropConfirmedOptimisticMessages() {
    final confirmedIds = <String>{
      for (final m in _recentMessages) m.id,
      ..._olderById.keys,
    };
    for (final id in confirmedIds) {
      if (_optimisticById.remove(id) != null) {
        _optimisticPreviewBytes.remove(id);
        clearUploadProgress(id);
      }
    }
  }

  /// Updates reactions in the in-memory list immediately (before Firestore echoes).
  Future<void> applyLocalReaction({
    required String messageId,
    required String userId,
    String? emoji,
  }) async {
    final index = _inner.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final old = _inner.messages[index];
    final updated = _messageWithReactions(
      old,
      reactions: _reactionsAfterUserChange(
        old.reactions,
        userId: userId,
        emoji: emoji,
      ),
    );
    if (updated == old) return;
    await _inner.updateMessage(old, updated);
  }

  List<Message> _buildMappedMessages() {
    final olderSorted = _olderById.values.toList()
      ..sort((a, b) => a.$1.createdAt.compareTo(b.$1.createdAt));

    final firestoreMessages = <Message>[
      for (final entry in olderSorted) mapTripMessage(entry.$1, entry.$2),
      for (final m in _recentMessages)
        mapTripMessage(m, _recentReactions[m.id] ?? []),
    ];

    final firestoreIds = firestoreMessages.map((m) => m.id).toSet();
    final merged = List<Message>.from(firestoreMessages);
    for (final optimistic in _optimisticById.values) {
      if (!firestoreIds.contains(optimistic.id)) {
        merged.add(optimistic);
      }
    }
    merged.sort((a, b) {
      final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });
    return merged;
  }

  void _rebuildMessages() {
    final allMapped = _buildMappedMessages();

    final previous = _inner.messages;
    if (previous.length == allMapped.length &&
        _sameMessageIdsInOrder(previous, allMapped)) {
      // ChatMessageInternal only listens to ChatOperationType.update — not set.
      for (var i = 0; i < previous.length; i++) {
        if (previous[i] != allMapped[i]) {
          unawaited(_inner.updateMessage(previous[i], allMapped[i]));
        }
      }
      return;
    }

    // Always non-animated: using animated:true on a setMessages diff causes
    // a key collision when _onChanged removes then re-inserts the same message
    // ID — both 250ms animations coexist during any concurrent layout rebuild
    // (e.g. keyboard dismiss), tripping SliverAnimatedList's ordering assertion.
    // With Duration.zero the remove animation completes synchronously before
    // the insert, so the two children never overlap.
    unawaited(_inner.setMessages(allMapped, animated: false));
  }
}

bool _sameMessageIdsInOrder(List<Message> previous, List<Message> next) {
  for (var i = 0; i < previous.length; i++) {
    if (previous[i].id != next[i].id) return false;
  }
  return true;
}

Map<String, List<String>>? _reactionsAfterUserChange(
  Map<String, List<String>>? current, {
  required String userId,
  required String? emoji,
}) {
  final next = <String, List<String>>{};
  if (current != null) {
    for (final entry in current.entries) {
      final users = entry.value.where((id) => id != userId).toList();
      if (users.isNotEmpty) next[entry.key] = users;
    }
  }
  final cleanEmoji = emoji?.trim();
  if (cleanEmoji != null && cleanEmoji.isNotEmpty) {
    next.putIfAbsent(cleanEmoji, () => []).add(userId);
  }
  return next.isEmpty ? null : next;
}

Message _messageWithReactions(
  Message message, {
  required Map<String, List<String>>? reactions,
}) {
  return message.map(
    text: (m) => m.copyWith(reactions: reactions),
    textStream: (m) => m.copyWith(reactions: reactions),
    image: (m) => m.copyWith(reactions: reactions),
    file: (m) => m.copyWith(reactions: reactions),
    video: (m) => m.copyWith(reactions: reactions),
    audio: (m) => m.copyWith(reactions: reactions),
    system: (m) => m.copyWith(reactions: reactions),
    custom: (m) => m.copyWith(reactions: reactions),
    unsupported: (m) => m.copyWith(reactions: reactions),
  );
}
