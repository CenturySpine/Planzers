import 'dart:async';
import 'dart:typed_data';

import 'package:planerz/features/messaging/chat_controller/trip_chat_controller.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/data/trip_message_kind.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';

TripMessage chatMessage(
  String id, {
  String authorId = 'bob',
  String? text,
  DateTime? at,
  String? replyTo,
  Map<String, String> reactions = const {},
  TripMessageKind kind = TripMessageKind.text,
}) {
  return TripMessage(
    id: id,
    text: text ?? 'Message $id',
    authorId: authorId,
    createdAt: at ?? DateTime(2026, 11, 9, 10),
    threadType: TripMessageThreadType.main,
    visibilityType: TripMessageVisibilityType.tripAll,
    kind: kind,
    replyToMessageId: replyTo,
    reactionsByUser: reactions,
  );
}

/// In-memory conversation standing in for Firestore in tests.
class FakeTripChatBackend implements TripChatBackend {
  FakeTripChatBackend({this.currentUserId = 'me', List<TripMessage>? history})
      : store = [...?history];

  /// Every stored message, oldest first.
  final List<TripMessage> store;
  final _windows = StreamController<TripChatWindow>.broadcast();
  int _liveLimit = 40;
  int _nextId = 0;

  /// When set, the next write fails with this error.
  Object? failNextWrite;

  /// When set, sends wait for this to complete.
  Completer<void>? sendGate;

  /// Whether a successful send is stored and pushed to listeners.
  bool echoSends = true;

  final List<String> log = [];
  DateTime serverNow = DateTime(2026, 11, 9, 12);

  @override
  String? currentUserId;

  @override
  TripMessageThreadScope get scope => const TripMessageThreadScope.main();

  @override
  String newMessageId() => 'local-${_nextId++}';

  @override
  Stream<TripChatWindow> watchLatest({required int limit}) {
    _liveLimit = limit;
    return _windows.stream;
  }

  /// Pushes the current latest messages to the controller.
  void emit() {
    final start = store.length > _liveLimit ? store.length - _liveLimit : 0;
    _windows.add(
      TripChatWindow(
        messages: store.sublist(start),
        olderCursor: start < store.length ? start : null,
        mayHaveOlder: store.length - start >= _liveLimit,
      ),
    );
  }

  void emitError() => _windows.addError(StateError('offline'));

  /// Adds a message as if another device had sent it.
  void receive(TripMessage message) {
    store.add(message);
    emit();
  }

  void _maybeFail() {
    final error = failNextWrite;
    if (error != null) {
      failNextWrite = null;
      throw error;
    }
  }

  @override
  Future<TripChatWindow> fetchOlder({
    required Object cursor,
    required int limit,
  }) async {
    log.add('fetchOlder');
    final end = cursor as int;
    final start = end > limit ? end - limit : 0;
    return TripChatWindow(
      messages: store.sublist(start, end),
      olderCursor: start < end ? start : null,
      mayHaveOlder: end - start >= limit,
    );
  }

  @override
  Future<TripMessage?> fetchMessage(String messageId) async {
    log.add('fetchMessage:$messageId');
    for (final message in store) {
      if (message.id == messageId) return message;
    }
    return null;
  }

  @override
  Future<void> sendText({
    required String messageId,
    required String text,
    String? replyToMessageId,
  }) async {
    log.add('sendText:$text');
    await sendGate?.future;
    _maybeFail();
    if (!echoSends) return;
    serverNow = serverNow.add(const Duration(seconds: 1));
    receive(
      chatMessage(
        messageId,
        authorId: currentUserId ?? '',
        text: text,
        at: serverNow,
        replyTo: replyToMessageId,
      ),
    );
  }

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
  }) async {
    log.add('sendImage:$fileExt');
    onUploadProgress?.call(0.5);
    await sendGate?.future;
    _maybeFail();
    if (!echoSends) return;
    serverNow = serverNow.add(const Duration(seconds: 1));
    receive(
      chatMessage(
        messageId,
        authorId: currentUserId ?? '',
        text: caption ?? '',
        at: serverNow,
        kind: TripMessageKind.image,
      ),
    );
  }

  @override
  Future<void> updateText({
    required String messageId,
    required String text,
  }) async {
    log.add('updateText:$messageId:$text');
    _maybeFail();
    final index = store.indexWhere((m) => m.id == messageId);
    if (index != -1) store[index] = store[index].copyWith(text: text);
  }

  @override
  Future<void> delete(TripMessage message) async {
    log.add('delete:${message.id}');
    _maybeFail();
    store.removeWhere((m) => m.id == message.id);
  }

  @override
  Future<void> setMyReaction({
    required String messageId,
    required String? emoji,
  }) async {
    log.add('react:$messageId:${emoji ?? 'none'}');
    _maybeFail();
  }
}
