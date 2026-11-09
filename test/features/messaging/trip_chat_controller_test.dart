import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/messaging/chat_controller/trip_chat_controller.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';

import 'fake_trip_chat_backend.dart';

List<String> ids(TripChatController controller) =>
    controller.messages.map((m) => m.id).toList();

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeTripChatBackend backend;
  late TripChatController controller;

  TripChatController build({List<TripMessage>? history, int pageSize = 40}) {
    backend = FakeTripChatBackend(history: history);
    controller = TripChatController(backend: backend, pageSize: pageSize);
    addTearDown(controller.dispose);
    return controller;
  }

  List<TripMessage> history(int count) => [
        for (var i = 0; i < count; i++)
          chatMessage('m$i', at: DateTime(2026, 11, 1, 8).add(Duration(minutes: i))),
      ];

  test('shows the latest messages newest first once loaded', () async {
    build(history: history(3));
    expect(controller.isLoading, isTrue);

    backend.emit();
    await settle();

    expect(controller.isLoading, isFalse);
    expect(ids(controller), ['m2', 'm1', 'm0']);
    expect(controller.hasMoreOlder, isFalse);
  });

  test('a sent message appears immediately, before the server answers',
      () async {
    build(history: history(2));
    backend.emit();
    await settle();
    backend.sendGate = Completer<void>();

    final id = controller.sendText('  Salut  ', replyToMessageId: 'm1');

    expect(ids(controller).first, id);
    final pending = controller.messages.first;
    expect(pending.text, 'Salut');
    expect(pending.authorId, 'me');
    expect(pending.replyToMessageId, 'm1');
    expect(pending.isSending, isTrue);

    backend.sendGate!.complete();
    await settle();

    final confirmed = controller.messages.first;
    expect(confirmed.id, id);
    expect(confirmed.sendState, TripMessageSendState.sent);
    expect(controller.messages, hasLength(3));
  });

  test('an unconfirmed message stays last even if the device clock is late',
      () async {
    backend = FakeTripChatBackend(history: history(1));
    controller = TripChatController(
      backend: backend,
      // Device clock one year behind the server.
      now: () => DateTime(2025, 1, 1),
    );
    addTearDown(controller.dispose);
    backend.emit();
    await settle();
    backend.echoSends = false;

    final id = controller.sendText('Hors ligne');

    expect(ids(controller), [id, 'm0']);
  });

  test('a refused message is kept as failed and can be retried', () async {
    build(history: history(1));
    backend.emit();
    await settle();
    backend.failNextWrite = StateError('denied');

    final id = controller.sendText('Raté');
    await settle();

    expect(controller.messageById(id)!.isFailed, isTrue);

    controller.retry(id);
    expect(controller.messageById(id)!.isSending, isTrue);
    await settle();

    expect(controller.messageById(id)!.sendState, TripMessageSendState.sent);
    expect(backend.log.where((l) => l == 'sendText:Raté'), hasLength(2));
  });

  test('a failed message can be discarded', () async {
    build();
    backend.emit();
    await settle();
    backend.failNextWrite = StateError('denied');
    final id = controller.sendText('Raté');
    await settle();

    controller.discardFailed(id);

    expect(controller.messages, isEmpty);
  });

  test('a photo is shown from the device while it uploads', () async {
    build();
    backend.emit();
    await settle();
    backend.sendGate = Completer<void>();
    final bytes = Uint8List.fromList([1, 2, 3]);

    final id = controller.sendImage(bytes: bytes, fileExt: 'jpg');
    await settle();

    expect(controller.messageById(id)!.isImage, isTrue);
    expect(controller.localImageBytes(id), same(bytes));
    expect(controller.uploadProgress(id)!.value, 0.5);

    backend.sendGate!.complete();
    await settle();

    expect(controller.uploadProgress(id), isNull);
    // Still displayed from memory: no flicker while the download starts.
    expect(controller.localImageBytes(id), same(bytes));
  });

  test('reacting is applied at once and toggles off with the same emoji',
      () async {
    build(history: history(1));
    backend.emit();
    await settle();

    final first = controller.toggleReaction('m0', '👍');
    expect(controller.messageById('m0')!.reactionsByUser, {'me': '👍'});
    await first;

    await controller.toggleReaction('m0', '❤️');
    expect(controller.messageById('m0')!.reactionsByUser, {'me': '❤️'});

    await controller.toggleReaction('m0', '❤️');
    expect(controller.messageById('m0')!.reactionsByUser, isEmpty);
    expect(backend.log, ['react:m0:👍', 'react:m0:❤️', 'react:m0:none']);
  });

  test('a refused reaction is rolled back', () async {
    build(history: [chatMessage('m0', reactions: const {'bob': '😂'})]);
    backend.emit();
    await settle();
    backend.failNextWrite = StateError('denied');

    await expectLater(controller.toggleReaction('m0', '👍'), throwsStateError);

    expect(controller.messageById('m0')!.reactionsByUser, {'bob': '😂'});
  });

  test('editing and deleting apply at once and roll back when refused',
      () async {
    build(history: history(2));
    backend.emit();
    await settle();

    final edit = controller.editText('m1', 'Corrigé');
    expect(controller.messageById('m1')!.text, 'Corrigé');
    await edit;

    backend.failNextWrite = StateError('denied');
    await expectLater(controller.editText('m1', 'Refusé'), throwsStateError);
    expect(controller.messageById('m1')!.text, 'Corrigé');

    final delete = controller.deleteMessage('m0');
    expect(ids(controller), ['m1']);
    await delete;

    backend.failNextWrite = StateError('denied');
    await expectLater(controller.deleteMessage('m1'), throwsStateError);
    expect(ids(controller), ['m1']);
  });

  test('older history is loaded page by page without duplicates', () async {
    build(history: history(25), pageSize: 10);
    backend.emit();
    await settle();
    expect(controller.messages, hasLength(10));
    expect(controller.hasMoreOlder, isTrue);

    await controller.loadOlder();
    expect(controller.messages, hasLength(20));

    await controller.loadOlder();
    await controller.loadOlder();
    expect(controller.messages, hasLength(25));
    expect(controller.hasMoreOlder, isFalse);
    expect(ids(controller).first, 'm24');
    expect(ids(controller).last, 'm0');
    expect(ids(controller).toSet(), hasLength(25));
  });

  test('messages pushed out of the live window by new ones are kept',
      () async {
    build(history: history(10), pageSize: 10);
    backend.emit();
    await settle();

    backend.receive(chatMessage('new', at: DateTime(2026, 11, 2)));
    await settle();

    expect(controller.messages, hasLength(11));
    expect(ids(controller).first, 'new');
    expect(ids(controller).last, 'm0');
  });

  test('a message deleted by someone else disappears', () async {
    build(history: history(3));
    backend.emit();
    await settle();

    backend.store.removeWhere((m) => m.id == 'm1');
    backend.emit();
    await settle();

    expect(ids(controller), ['m2', 'm0']);
  });

  test('messages received while reading the history are held back',
      () async {
    build(history: history(3));
    backend.emit();
    await settle();
    controller.setFollowingLatest(false);

    backend.receive(chatMessage('n1', at: DateTime(2026, 11, 2)));
    backend.receive(chatMessage('n2', at: DateTime(2026, 11, 2, 1)));
    await settle();

    expect(ids(controller), ['m2', 'm1', 'm0']);
    expect(controller.heldIncomingCount, 2);

    controller.setFollowingLatest(true);

    expect(ids(controller), ['n2', 'n1', 'm2', 'm1', 'm0']);
    expect(controller.heldIncomingCount, 0);
  });

  test('sending while reading the history releases held messages', () async {
    build(history: history(1));
    backend.emit();
    await settle();
    controller.setFollowingLatest(false);
    backend.receive(chatMessage('n1', at: DateTime(2026, 11, 2)));
    await settle();

    final id = controller.sendText('Réponse');
    await settle();

    expect(ids(controller), [id, 'n1', 'm0']);
  });

  test('a quoted message older than the loaded history is fetched once',
      () async {
    build(history: history(25), pageSize: 10);
    backend.emit();
    await settle();
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(controller.quotedMessage('m24')!.id, 'm24');
    expect(controller.quotedMessage('m2'), isNull);
    expect(controller.quotedMessage('m2'), isNull);
    await settle();

    expect(controller.quotedMessage('m2')!.text, 'Message m2');
    expect(notifications, 1);
    expect(backend.log.where((l) => l == 'fetchMessage:m2'), hasLength(1));
    // Not part of the displayed history.
    expect(controller.messageById('m2'), isNull);
  });

  test('a loading error is reported, then cleared by the next data',
      () async {
    build(history: history(1));
    backend.emitError();
    await settle();
    expect(controller.hasError, isTrue);
    expect(controller.isLoading, isFalse);

    backend.emit();
    await settle();
    expect(controller.hasError, isFalse);
    expect(ids(controller), ['m0']);
  });
}
