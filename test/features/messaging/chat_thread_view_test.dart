import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/messaging/chat_controller/trip_chat_controller.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/presentation/chat_message_bubble.dart';
import 'package:planerz/features/messaging/presentation/chat_thread_view.dart';
import 'package:planerz/l10n/app_localizations.dart';

import 'fake_trip_chat_backend.dart';

void main() {
  late FakeTripChatBackend backend;
  late TripChatController controller;

  Future<void> pumpChat(
    WidgetTester tester, {
    required List<TripMessage> history,
    DateTime? unreadSince,
  }) async {
    backend = FakeTripChatBackend(history: history);
    controller = TripChatController(backend: backend);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatThreadView(
            controller: controller,
            currentUserId: 'me',
            memberLabels: const {'me': 'Bruno', 'bob': 'Bob'},
            memberPhotoUrls: const {},
            fallbackAuthorLabel: 'Participant',
            unreadSince: unreadSince,
          ),
        ),
      ),
    );
    backend.emit();
    await tester.pumpAndSettle();
  }

  List<TripMessage> smallTalk() => [
        chatMessage('b1', text: 'Salut', at: DateTime(2026, 11, 9, 10)),
        chatMessage(
          'm1',
          authorId: 'me',
          text: 'Bonjour Bob',
          at: DateTime(2026, 11, 9, 10, 5),
        ),
      ];

  testWidgets('shows a loader, then the empty state', (tester) async {
    backend = FakeTripChatBackend();
    controller = TripChatController(backend: backend);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatThreadView(
            controller: controller,
            currentUserId: 'me',
            memberLabels: const {},
            memberPhotoUrls: const {},
            fallbackAuthorLabel: 'Participant',
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    backend.emit();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Aucun message'), findsOneWidget);
  });

  testWidgets('messages show their author, and a marker before unread ones',
      (tester) async {
    await pumpChat(
      tester,
      history: smallTalk()
        ..add(chatMessage('b2', text: 'Ça va ?', at: DateTime(2026, 11, 9, 11))),
      unreadSince: DateTime(2026, 11, 9, 10, 30),
    );

    expect(find.text('Bob'), findsNWidgets(2));
    expect(find.text('Bruno'), findsNothing);
    expect(find.text('Messages non lus'), findsOneWidget);
    final markerY = tester.getCenter(find.text('Messages non lus')).dy;
    expect(tester.getCenter(find.textContaining('Bonjour Bob')).dy,
        lessThan(markerY));
    expect(tester.getCenter(find.textContaining('Ça va ?')).dy,
        greaterThan(markerY));
  });

  testWidgets('typing and sending shows the message at once', (tester) async {
    await pumpChat(tester, history: smallTalk());

    await tester.enterText(find.byType(TextField), 'À samedi');
    await tester.pump();
    await tester.tap(find.byIcon(PhosphorIconsFill.paperPlaneRight));
    await tester.pump();

    expect(find.textContaining('À samedi'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await tester.pumpAndSettle();
    expect(backend.log, contains('sendText:À samedi'));
  });

  testWidgets('long press offers reactions and only the allowed actions',
      (tester) async {
    await pumpChat(tester, history: smallTalk());

    await tester.longPress(find.textContaining('Salut'));
    await tester.pumpAndSettle();

    // Someone else's message: no edit, no delete.
    expect(find.text('👍'), findsOneWidget);
    expect(find.text('Répondre'), findsOneWidget);
    expect(find.text('Copier'), findsOneWidget);
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Supprimer'), findsNothing);

    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();

    expect(find.text('Répondre'), findsNothing);
    expect(controller.messageById('b1')!.reactionsByUser, {'me': '👍'});
    expect(find.text('👍'), findsOneWidget); // reaction chip under the bubble
  });

  testWidgets('replying from the menu quotes the message', (tester) async {
    await pumpChat(tester, history: smallTalk());

    await tester.longPress(find.textContaining('Salut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Répondre'));
    await tester.pumpAndSettle();

    // Banner above the input: author + preview.
    expect(find.text('Bob'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'Oui !');
    await tester.pump();
    await tester.tap(find.byIcon(PhosphorIconsFill.paperPlaneRight));
    await tester.pumpAndSettle();

    final sent = controller.messages.first;
    expect(sent.text, 'Oui !');
    expect(sent.replyToMessageId, 'b1');
  });

  testWidgets('swiping a message to the right starts a reply', (tester) async {
    await pumpChat(tester, history: smallTalk());

    await tester.drag(find.textContaining('Salut'), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(find.byIcon(PhosphorIconsRegular.x), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Vu');
    await tester.pump();
    await tester.tap(find.byIcon(PhosphorIconsFill.paperPlaneRight));
    await tester.pumpAndSettle();
    expect(controller.messages.first.replyToMessageId, 'b1');
  });

  testWidgets('editing happens in the input bar and keeps the draft',
      (tester) async {
    await pumpChat(tester, history: smallTalk());
    await tester.enterText(find.byType(TextField), 'brouillon');

    await tester.longPress(find.textContaining('Bonjour Bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Bonjour Bob');
    expect(find.text('Modifier le message'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Bonjour Robert');
    await tester.pump();
    await tester.tap(find.byTooltip('Enregistrer'));
    await tester.pumpAndSettle();

    expect(controller.messageById('m1')!.text, 'Bonjour Robert');
    expect(find.textContaining('modifié'), findsOneWidget);
    expect(backend.log, contains('updateText:m1:Bonjour Robert'));
    expect(field.controller!.text, 'brouillon');
    expect(find.text('Modifier le message'), findsNothing);
  });

  testWidgets('deleting asks for confirmation', (tester) async {
    await pumpChat(tester, history: smallTalk());

    await tester.longPress(find.textContaining('Bonjour Bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer ce message ?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(controller.messageById('m1'), isNull);
    expect(find.textContaining('Bonjour Bob'), findsNothing);
  });

  testWidgets('copy puts the text in the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await pumpChat(tester, history: smallTalk());

    await tester.longPress(find.textContaining('Salut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copier'));
    await tester.pumpAndSettle();

    expect(copied, 'Salut');
  });

  testWidgets('a refused message offers to retry or delete', (tester) async {
    await pumpChat(tester, history: smallTalk());
    backend.failNextWrite = StateError('denied');
    await tester.enterText(find.byType(TextField), 'Raté');
    await tester.pump();
    await tester.tap(find.byIcon(PhosphorIconsFill.paperPlaneRight));
    await tester.pumpAndSettle();
    expect(find.byIcon(PhosphorIconsRegular.warningCircle), findsOneWidget);

    // The time overlays the end of this short text: long press still
    // reaches the message row.
    await tester.longPress(find.textContaining('Raté'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('👍'), findsNothing);
    expect(find.text('Répondre'), findsNothing);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();

    expect(find.byIcon(PhosphorIconsRegular.warningCircle), findsNothing);
    expect(backend.log.where((l) => l == 'sendText:Raté'), hasLength(2));
  });

  testWidgets('tapping reactions lists who reacted and lets me remove mine',
      (tester) async {
    await pumpChat(
      tester,
      history: [
        chatMessage('b1', text: 'Salut', reactions: const {
          'me': '❤️',
          'bob': '😂',
        }),
      ],
    );

    await tester.tap(find.textContaining('❤️'));
    await tester.pumpAndSettle();
    expect(find.text('Moi'), findsOneWidget);
    expect(find.text('😂'), findsOneWidget);

    await tester.tap(find.byIcon(PhosphorIconsRegular.x));
    await tester.pumpAndSettle();

    expect(controller.messageById('b1')!.reactionsByUser, {'bob': '😂'});
  });

  test('emoji-only messages are detected', () {
    expect(isEmojiOnlyMessage('🎉'), isTrue);
    expect(isEmojiOnlyMessage('👍🏽 ❤️'), isTrue);
    expect(isEmojiOnlyMessage('👨‍👩‍👧🇫🇷😂'), isTrue);
    expect(isEmojiOnlyMessage('😂😂😂😂'), isFalse);
    expect(isEmojiOnlyMessage('ok 👍'), isFalse);
    expect(isEmojiOnlyMessage('123'), isFalse);
    expect(isEmojiOnlyMessage(''), isFalse);
  });
}
