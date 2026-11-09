import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/data/trip_message_kind.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';

/// Riverpod provider — one controller per (tripId, scope) pair.
///
/// Auto-disposed when no longer watched; subscription cancelled on dispose.
final tripChatControllerProvider = Provider.autoDispose
    .family<TripChatController, TripMessageThreadRequest>((ref, request) {
  final controller = TripChatController(
    backend: FirestoreTripChatBackend(
      repository: ref.watch(tripMessagesRepositoryProvider),
      tripId: request.tripId,
      scope: request.scope,
    ),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Storage operations a [TripChatController] needs for one conversation.
abstract class TripChatBackend {
  TripMessageThreadScope get scope;

  String? get currentUserId;

  String newMessageId();

  Stream<TripChatWindow> watchLatest({required int limit});

  Future<TripChatWindow> fetchOlder({
    required Object cursor,
    required int limit,
  });

  /// Reads a single message, or null when it does not exist.
  Future<TripMessage?> fetchMessage(String messageId);

  Future<void> sendText({
    required String messageId,
    required String text,
    String? replyToMessageId,
  });

  Future<void> sendImage({
    required String messageId,
    required Uint8List bytes,
    required String fileExt,
    String? caption,
    String? replyToMessageId,
    double? imageWidth,
    double? imageHeight,
    void Function(double progress)? onUploadProgress,
  });

  Future<void> updateText({required String messageId, required String text});

  Future<void> delete(TripMessage message);

  Future<void> setMyReaction({
    required String messageId,
    required String? emoji,
  });
}

class FirestoreTripChatBackend implements TripChatBackend {
  FirestoreTripChatBackend({
    required this.repository,
    required this.tripId,
    required this.scope,
  });

  final TripMessagesRepository repository;
  final String tripId;

  @override
  final TripMessageThreadScope scope;

  @override
  String? get currentUserId => repository.currentUserId;

  @override
  String newMessageId() => repository.newMessageId(tripId);

  @override
  Stream<TripChatWindow> watchLatest({required int limit}) =>
      repository.watchLatest(tripId, scope: scope, limit: limit);

  @override
  Future<TripChatWindow> fetchOlder({
    required Object cursor,
    required int limit,
  }) =>
      repository.fetchOlder(tripId, scope: scope, cursor: cursor, limit: limit);

  @override
  Future<TripMessage?> fetchMessage(String messageId) =>
      repository.fetchMessage(tripId, scope: scope, messageId: messageId);

  @override
  Future<void> sendText({
    required String messageId,
    required String text,
    String? replyToMessageId,
  }) =>
      repository.sendTextMessage(
        tripId: tripId,
        messageId: messageId,
        text: text,
        scope: scope,
        replyToMessageId: replyToMessageId,
      );

  @override
  Future<void> sendImage({
    required String messageId,
    required Uint8List bytes,
    required String fileExt,
    String? caption,
    String? replyToMessageId,
    double? imageWidth,
    double? imageHeight,
    void Function(double progress)? onUploadProgress,
  }) =>
      repository.sendImageMessage(
        tripId: tripId,
        messageId: messageId,
        bytes: bytes,
        fileExt: fileExt,
        scope: scope,
        caption: caption,
        replyToMessageId: replyToMessageId,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        onUploadProgress: onUploadProgress,
      );

  @override
  Future<void> updateText({required String messageId, required String text}) =>
      repository.updateMessageText(
        tripId: tripId,
        messageId: messageId,
        text: text,
      );

  @override
  Future<void> delete(TripMessage message) => repository.deleteMessage(
        tripId: tripId,
        messageId: message.id,
        imageStoragePath: message.imageStoragePath,
      );

  @override
  Future<void> setMyReaction({
    required String messageId,
    required String? emoji,
  }) =>
      repository.setMyReaction(
        tripId: tripId,
        messageId: messageId,
        emoji: emoji,
      );
}

class _OutgoingImage {
  const _OutgoingImage({required this.bytes, required this.fileExt});

  final Uint8List bytes;
  final String fileExt;
}

/// Holds the messages of one conversation and applies every user action
/// locally first, so the screen never waits for the network.
///
/// - The most recent messages are followed live; older ones are loaded page
///   by page with [loadOlder].
/// - Messages being sent are shown immediately and stay at the end of the
///   conversation until the server confirms them.
/// - While the reader is scrolled up in the history
///   ([setFollowingLatest] false), messages from other people are held back
///   and counted in [heldIncomingCount] instead of moving the list.
class TripChatController extends ChangeNotifier {
  TripChatController({
    required TripChatBackend backend,
    this.pageSize = 40,
    DateTime Function()? now,
  })  : _backend = backend,
        _now = now ?? DateTime.now {
    _sub = _backend.watchLatest(limit: pageSize).listen(
      _onLiveWindow,
      onError: (Object _) {
        _hasError = true;
        _isLoading = false;
        _notify();
      },
    );
  }

  static const int _maxKeptLocalImages = 8;

  final TripChatBackend _backend;
  final DateTime Function() _now;
  final int pageSize;

  StreamSubscription<TripChatWindow>? _sub;
  bool _disposed = false;

  bool _isLoading = true;
  bool _hasError = false;

  /// Messages currently followed live, oldest first.
  List<TripMessage> _live = const <TripMessage>[];

  /// Messages outside the live window (older pages, or pushed out of the
  /// window by newer messages).
  final _older = <String, TripMessage>{};

  /// Messages created on this device and not yet visible in [_live].
  final _outbox = <String, TripMessage>{};

  /// Sends whose outcome is not known yet.
  final _inFlight = <String, TripMessage>{};
  final _outgoingImages = <String, _OutgoingImage>{};

  /// Placeholder creation time for messages the server has not stamped yet.
  final _localCreatedAt = <String, DateTime>{};

  /// Insertion-ordered, so the oldest entries can be dropped first.
  final _localImageBytes = <String, Uint8List>{};
  final _uploadProgress = <String, ValueNotifier<double>>{};

  /// Quoted messages that are older than the loaded history (null when the
  /// original no longer exists).
  final _quotedOutsideHistory = <String, TripMessage?>{};

  Object? _olderCursor;
  bool _hasMoreOlder = false;
  bool _hasPaginated = false;
  bool _isLoadingOlder = false;

  bool _followingLatest = true;
  final _seenIds = <String>{};
  final _heldIds = <String>{};

  List<TripMessage> _visibleNewestFirst = const <TripMessage>[];
  Map<String, int> _indexById = const <String, int>{};

  // ── Read state ─────────────────────────────────────────────────────────

  /// Messages to display, newest first (index 0 is the latest message).
  List<TripMessage> get messages => _visibleNewestFirst;

  bool get isLoading => _isLoading;

  bool get hasError => _hasError;

  bool get hasMoreOlder => _hasMoreOlder;

  bool get isLoadingOlder => _isLoadingOlder;

  String? get currentUserId => _backend.currentUserId;

  /// Number of messages received while the reader was away from the latest
  /// messages and not shown yet.
  int get heldIncomingCount => _heldIds.length;

  TripMessage? messageById(String id) {
    final index = _indexById[id];
    return index == null ? null : _visibleNewestFirst[index];
  }

  /// The message a reply refers to. When it is older than the loaded
  /// history it is fetched in the background and listeners are notified
  /// once it is available; null is returned meanwhile.
  TripMessage? quotedMessage(String id) {
    final loaded = messageById(id);
    if (loaded != null) return loaded;
    if (_quotedOutsideHistory.containsKey(id)) return _quotedOutsideHistory[id];
    if (_isLoading || _heldIds.contains(id)) return null;
    _quotedOutsideHistory[id] = null;
    unawaited(_fetchQuoted(id));
    return null;
  }

  Future<void> _fetchQuoted(String id) async {
    try {
      final message = await _backend.fetchMessage(id);
      if (_disposed || message == null) return;
      _quotedOutsideHistory[id] = message;
      _notify();
    } catch (_) {
      // Allow another attempt the next time the reply is displayed.
      _quotedOutsideHistory.remove(id);
    }
  }

  /// Position of a message in [messages], or null when it is not loaded.
  int? indexOfMessage(String id) => _indexById[id];

  /// Bytes of an image sent from this device, to display it without
  /// downloading it again.
  Uint8List? localImageBytes(String messageId) => _localImageBytes[messageId];

  /// Upload progress (0..1) of an image being sent, or null.
  ValueListenable<double>? uploadProgress(String messageId) =>
      _uploadProgress[messageId];

  // ── Reading position ───────────────────────────────────────────────────

  /// Tells the controller whether the reader is looking at the latest
  /// messages. When they come back, held messages are released.
  void setFollowingLatest(bool following) {
    if (_followingLatest == following) return;
    _followingLatest = following;
    if (following && _heldIds.isNotEmpty) {
      _heldIds.clear();
      _recompute();
    }
  }

  /// Loads the previous page of the history, if any.
  Future<void> loadOlder() async {
    final cursor = _olderCursor;
    if (_isLoadingOlder || !_hasMoreOlder || cursor == null) return;
    _isLoadingOlder = true;
    _notify();
    try {
      final page = await _backend.fetchOlder(cursor: cursor, limit: pageSize);
      if (_disposed) return;
      _hasPaginated = true;
      _olderCursor = page.olderCursor ?? cursor;
      _hasMoreOlder = page.mayHaveOlder && page.olderCursor != null;
      final liveIds = {for (final m in _live) m.id};
      for (final message in page.messages) {
        _seenIds.add(message.id);
        if (!liveIds.contains(message.id)) _older[message.id] = message;
      }
    } catch (_) {
      // Keep the current state: scrolling up again retries.
    } finally {
      _isLoadingOlder = false;
      if (!_disposed) _recompute();
    }
  }

  // ── Sending ────────────────────────────────────────────────────────────

  /// Shows the message immediately and sends it in the background.
  /// Returns the id of the new message.
  String sendText(String text, {String? replyToMessageId}) {
    final message = _newOutgoing(
      kind: TripMessageKind.text,
      text: text.trim(),
      replyToMessageId: replyToMessageId,
    );
    _enqueue(message);
    unawaited(_deliver(message));
    return message.id;
  }

  /// Shows the image immediately and uploads it in the background.
  /// Returns the id of the new message.
  String sendImage({
    required Uint8List bytes,
    required String fileExt,
    String? caption,
    String? replyToMessageId,
    double? imageWidth,
    double? imageHeight,
  }) {
    final message = _newOutgoing(
      kind: TripMessageKind.image,
      text: (caption ?? '').trim(),
      replyToMessageId: replyToMessageId,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    _outgoingImages[message.id] =
        _OutgoingImage(bytes: bytes, fileExt: fileExt);
    _localImageBytes[message.id] = bytes;
    _enqueue(message);
    unawaited(_deliver(message));
    return message.id;
  }

  /// Sends again a message whose delivery failed.
  void retry(String messageId) {
    final failed = _outbox[messageId];
    if (failed == null || !failed.isFailed) return;
    final message = failed.copyWith(sendState: TripMessageSendState.sending);
    _outbox[messageId] = message;
    _recompute();
    unawaited(_deliver(message));
  }

  /// Drops a message whose delivery failed.
  void discardFailed(String messageId) {
    final failed = _outbox[messageId];
    if (failed == null || !failed.isFailed) return;
    _outbox.remove(messageId);
    _forgetOutgoing(messageId);
    _localImageBytes.remove(messageId);
    _recompute();
  }

  TripMessage _newOutgoing({
    required TripMessageKind kind,
    required String text,
    String? replyToMessageId,
    double? imageWidth,
    double? imageHeight,
  }) {
    final scope = _backend.scope;
    final id = _backend.newMessageId();
    final createdAt = _now();
    _localCreatedAt[id] = createdAt;
    final cleanReplyId = replyToMessageId?.trim() ?? '';
    return TripMessage(
      id: id,
      text: text,
      authorId: _backend.currentUserId ?? '',
      createdAt: createdAt,
      threadType: scope.threadType,
      visibilityType: scope.visibilityType,
      threadObjectType: scope.threadObjectType,
      threadObjectId: scope.threadObjectId,
      kind: kind,
      replyToMessageId: cleanReplyId.isEmpty ? null : cleanReplyId,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      sendState: TripMessageSendState.sending,
      hasServerTimestamp: false,
    );
  }

  void _enqueue(TripMessage message) {
    _seenIds.add(message.id);
    _outbox[message.id] = message;
    // Sending always brings the reader back to the latest messages.
    _followingLatest = true;
    _heldIds.clear();
    _recompute();
  }

  Future<void> _deliver(TripMessage message) async {
    final id = message.id;
    _inFlight[id] = message;
    try {
      if (message.isImage) {
        final image = _outgoingImages[id];
        if (image == null) throw StateError('Image invalide');
        final progress = _uploadProgress[id] ??= ValueNotifier<double>(0);
        progress.value = 0;
        await _backend.sendImage(
          messageId: id,
          bytes: image.bytes,
          fileExt: image.fileExt,
          caption: message.text,
          replyToMessageId: message.replyToMessageId,
          imageWidth: message.imageWidth,
          imageHeight: message.imageHeight,
          onUploadProgress: (value) {
            if (!_disposed) progress.value = value.clamp(0.0, 1.0);
          },
        );
      } else {
        await _backend.sendText(
          messageId: id,
          text: message.text,
          replyToMessageId: message.replyToMessageId,
        );
      }
      if (_disposed) return;
      _forgetOutgoing(id);
      final queued = _outbox[id];
      if (queued != null) {
        _outbox[id] = queued.copyWith(sendState: TripMessageSendState.sent);
      }
      _trimLocalImages();
      _recompute();
    } catch (_) {
      if (_disposed) return;
      _inFlight.remove(id);
      _disposeProgress(id);
      // The server may have refused a message that was already displayed
      // from the live window: bring it back as failed so it can be retried.
      _outbox[id] = message.copyWith(sendState: TripMessageSendState.failed);
      _recompute();
    }
  }

  void _forgetOutgoing(String id) {
    _inFlight.remove(id);
    _outgoingImages.remove(id);
    _disposeProgress(id);
  }

  void _disposeProgress(String id) {
    final progress = _uploadProgress.remove(id);
    if (progress != null) {
      // Listeners (progress rings) are unmounted on the next frame.
      scheduleMicrotask(progress.dispose);
    }
  }

  void _trimLocalImages() {
    while (_localImageBytes.length > _maxKeptLocalImages) {
      final oldest = _localImageBytes.keys.firstWhere(
        (id) => !_outgoingImages.containsKey(id),
        orElse: () => '',
      );
      if (oldest.isEmpty) return;
      _localImageBytes.remove(oldest);
    }
  }

  // ── Actions on existing messages ───────────────────────────────────────

  /// Reacts with [emoji], or removes the reaction when the user already
  /// reacted with the same emoji.
  Future<void> toggleReaction(String messageId, String emoji) async {
    final uid = _backend.currentUserId;
    final cleanEmoji = emoji.trim();
    final message = _stored(messageId);
    if (uid == null || cleanEmoji.isEmpty || message == null) return;
    final previous = message.reactionsByUser[uid];
    final next = previous == cleanEmoji ? null : cleanEmoji;
    _replaceStored(message.copyWith(
      reactionsByUser: _withReaction(message.reactionsByUser, uid, next),
    ));
    _recompute();
    try {
      await _backend.setMyReaction(messageId: messageId, emoji: next);
    } catch (_) {
      final current = _stored(messageId);
      if (!_disposed && current != null) {
        _replaceStored(current.copyWith(
          reactionsByUser:
              _withReaction(current.reactionsByUser, uid, previous),
        ));
        _recompute();
      }
      rethrow;
    }
  }

  Future<void> editText(String messageId, String text) async {
    final message = _stored(messageId);
    final trimmed = text.trim();
    if (message == null || trimmed.isEmpty || trimmed == message.text) return;
    _replaceStored(message.copyWith(text: trimmed));
    _recompute();
    try {
      await _backend.updateText(messageId: messageId, text: trimmed);
    } catch (_) {
      final current = _stored(messageId);
      if (!_disposed && current != null) {
        _replaceStored(current.copyWith(text: message.text));
        _recompute();
      }
      rethrow;
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final message = _stored(messageId);
    if (message == null) return;
    final liveIndex = _live.indexWhere((m) => m.id == messageId);
    final wasOlder = _older.remove(messageId) != null;
    if (liveIndex != -1) {
      _live = [..._live]..removeAt(liveIndex);
    }
    _recompute();
    try {
      await _backend.delete(message);
      _localImageBytes.remove(messageId);
    } catch (_) {
      if (!_disposed) {
        if (wasOlder) {
          _older[messageId] = message;
        } else if (liveIndex != -1 && !_live.any((m) => m.id == messageId)) {
          _live = [..._live, message];
        }
        _recompute();
      }
      rethrow;
    }
  }

  TripMessage? _stored(String id) {
    for (final message in _live) {
      if (message.id == id) return message;
    }
    return _older[id];
  }

  void _replaceStored(TripMessage message) {
    final liveIndex = _live.indexWhere((m) => m.id == message.id);
    if (liveIndex != -1) {
      _live = [..._live]..[liveIndex] = message;
    } else if (_older.containsKey(message.id)) {
      _older[message.id] = message;
    }
  }

  static Map<String, String> _withReaction(
    Map<String, String> reactions,
    String userId,
    String? emoji,
  ) {
    final next = Map<String, String>.of(reactions);
    if (emoji == null || emoji.isEmpty) {
      next.remove(userId);
    } else {
      next[userId] = emoji;
    }
    return next;
  }

  // ── Live window ────────────────────────────────────────────────────────

  void _onLiveWindow(TripChatWindow window) {
    _isLoading = false;
    _hasError = false;

    final incoming = window.messages;
    final incomingIds = {for (final m in incoming) m.id};

    // A message that left the live window was either deleted or pushed out
    // by newer ones. Keep it in the second case.
    if (window.mayHaveOlder && incoming.isNotEmpty) {
      final oldestLive = incoming.first.createdAt;
      for (final previous in _live) {
        if (incomingIds.contains(previous.id)) continue;
        if (previous.hasServerTimestamp &&
            !previous.createdAt.isAfter(oldestLive)) {
          _older[previous.id] = previous;
        }
      }
    }
    for (final id in incomingIds) {
      _older.remove(id);
      // Confirmed by the store: no longer only local. A failed entry stays
      // until the user retries or discards it.
      if (_outbox[id]?.isFailed == false) _outbox.remove(id);
    }

    final myUid = _backend.currentUserId;
    final isFirstWindow = _seenIds.isEmpty && _live.isEmpty;
    for (final message in incoming) {
      final isNew = _seenIds.add(message.id);
      if (isNew &&
          !isFirstWindow &&
          !_followingLatest &&
          message.authorId != myUid) {
        _heldIds.add(message.id);
      }
    }

    _live = incoming;
    if (!_hasPaginated) {
      _olderCursor = window.olderCursor;
      _hasMoreOlder = window.mayHaveOlder && window.olderCursor != null;
    }
    _recompute();
  }

  void _recompute() {
    final merged = <String, TripMessage>{
      ..._older,
      for (final m in _live) m.id: m,
    };
    for (final entry in _outbox.entries) {
      if (entry.value.isFailed) {
        merged[entry.key] = entry.value;
      } else {
        merged.putIfAbsent(entry.key, () => entry.value);
      }
    }
    _heldIds.removeWhere((id) => !merged.containsKey(id));

    final list = <TripMessage>[];
    for (final message in merged.values) {
      if (_heldIds.contains(message.id)) continue;
      list.add(_withLocalTime(message));
    }
    list.sort(_compareNewestFirst);

    _visibleNewestFirst = List<TripMessage>.unmodifiable(list);
    _indexById = {
      for (var i = 0; i < list.length; i++) list[i].id: i,
    };
    _notify();
  }

  TripMessage _withLocalTime(TripMessage message) {
    if (message.hasServerTimestamp) {
      _localCreatedAt.remove(message.id);
      return message;
    }
    final localTime = _localCreatedAt.putIfAbsent(message.id, _now);
    return message.createdAt == localTime
        ? message
        : message.copyWith(createdAt: localTime);
  }

  /// Unconfirmed messages always come after confirmed ones, whatever the
  /// device clock says.
  static int _compareNewestFirst(TripMessage a, TripMessage b) {
    if (a.hasServerTimestamp != b.hasServerTimestamp) {
      return a.hasServerTimestamp ? 1 : -1;
    }
    final byTime = b.createdAt.compareTo(a.createdAt);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    for (final progress in _uploadProgress.values) {
      progress.dispose();
    }
    _uploadProgress.clear();
    super.dispose();
  }
}
