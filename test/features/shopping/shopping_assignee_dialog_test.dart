import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/shopping/presentation/widgets/shopping_assignee_dialog.dart';
import 'package:planerz/features/trips/data/trip_member.dart';
import 'package:planerz/l10n/app_localizations.dart';

void main() {
  group('shoppingAssigneesFor', () {
    test('keeps current members with an account, sorted by name', () {
      final assignees = shoppingAssigneesFor(
        participants: const [
          TripMember(id: 'm1', participantName: 'Zoé', userId: 'u1'),
          TripMember(id: 'm2', participantName: 'Placeholder'),
          TripMember(id: 'm3', participantName: 'Anna', userId: 'u3'),
          TripMember(id: 'm4', participantName: 'Gone', userId: 'u4'),
        ],
        memberUserIds: const ['u1', 'u3'],
        labelsById: const {'u3': 'Anna B.'},
        photoUrlsByUserId: const {'u1': 'https://example.com/z.png'},
      );

      expect(assignees.map((a) => a.userId), ['u3', 'u1']);
      expect(assignees.first.label, 'Anna B.');
      expect(assignees.last.label, 'Zoé');
      expect(assignees.last.photoUrl, 'https://example.com/z.png');
    });
  });

  group('showShoppingAssigneeDialog', () {
    const assignees = [
      ShoppingAssignee(userId: 'u1', label: 'Anna'),
      ShoppingAssignee(userId: 'u2', label: 'Bruno'),
    ];

    Future<String?> pickWith(
      WidgetTester tester, {
      required Future<void> Function() interact,
      String? initialUserId,
      bool allowNobody = false,
    }) async {
      String? result = 'not closed';
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showShoppingAssigneeDialog(
                  context,
                  assignees: assignees,
                  initialUserId: initialUserId,
                  allowNobody: allowNobody,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await interact();
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('returns the chosen participant', (tester) async {
      final result = await pickWith(
        tester,
        interact: () async {
          await tester.tap(find.text('Bruno'));
          await tester.pump();
          await tester.tap(find.text('Valider'));
        },
      );
      expect(result, 'u2');
    });

    testWidgets('returns an empty id for nobody', (tester) async {
      final result = await pickWith(
        tester,
        initialUserId: 'u1',
        allowNobody: true,
        interact: () async {
          await tester.tap(find.text('Personne'));
          await tester.pump();
          await tester.tap(find.text('Valider'));
        },
      );
      expect(result, '');
    });

    testWidgets('cannot confirm without a choice when nobody is not offered',
        (tester) async {
      final result = await pickWith(
        tester,
        interact: () async {
          expect(find.text('Personne'), findsNothing);
          await tester.tap(find.text('Valider'));
          await tester.pump();
          await tester.tap(find.text('Annuler'));
        },
      );
      expect(result, isNull);
    });
  });
}
