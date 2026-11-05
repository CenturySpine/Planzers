import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';
import 'package:planerz/features/shopping/presentation/widgets/shopping_assignee_dialog.dart';
import 'package:planerz/features/shopping/presentation/widgets/shopping_list_status_filter.dart';
import 'package:planerz/features/trips/data/trip_member.dart';
import 'package:planerz/l10n/app_localizations.dart';

void main() {
  group('shoppingAssigneesFor', () {
    test('offers every participant but children, sorted by name', () {
      final assignees = shoppingAssigneesFor(
        participants: const [
          TripMember(id: 'm1', participantName: 'Zoé', userId: 'u1'),
          TripMember(id: 'm2', participantName: 'Mamie'),
          TripMember(id: 'm3', participantName: 'Anna', userId: 'u3'),
          TripMember(id: 'm4', participantName: 'Gone', userId: 'u4'),
          TripMember(id: 'm5', participantName: 'Léo', isChild: true),
          TripMember(
            id: 'm6',
            participantName: 'Tom',
            userId: 'u6',
            isChild: true,
          ),
        ],
        memberUserIds: const ['u1', 'u3', 'u6'],
        labelsById: const {'u3': 'Anna B.', 'm2': 'Mamie Jo'},
        photoUrlsByUserId: const {'u1': 'https://example.com/z.png'},
      );

      // With an account: user id; without: participant id. Children and
      // former members are left out.
      expect(assignees.map((a) => a.claimId), ['u3', 'm2', 'u1']);
      expect(assignees.map((a) => a.label), ['Anna B.', 'Mamie Jo', 'Zoé']);
      expect(assignees.last.photoUrl, 'https://example.com/z.png');
      expect(assignees[1].photoUrl, isEmpty);
    });
  });

  group('showShoppingAssigneeDialog', () {
    const assignees = [
      ShoppingAssignee(claimId: 'u1', label: 'Anna'),
      ShoppingAssignee(claimId: 'm2', label: 'Bruno'),
    ];

    Future<String?> pickWith(
      WidgetTester tester, {
      required Future<void> Function() interact,
      String? initialClaimId,
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
                  initialClaimId: initialClaimId,
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
      expect(result, 'm2');
    });

    testWidgets('returns an empty id for nobody', (tester) async {
      final result = await pickWith(
        tester,
        initialClaimId: 'u1',
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

    testWidgets('preselects nothing for a whole category', (tester) async {
      final result = await pickWith(
        tester,
        allowNobody: true,
        interact: () async {
          // Disabled until a choice is made: the dialog stays open.
          await tester.tap(find.text('Valider'));
          await tester.pump();
          await tester.tap(find.text('Personne'));
          await tester.pump();
          await tester.tap(find.text('Valider'));
        },
      );
      expect(result, '');
    });
  });

  group('shoppingItemMatchesShoppingListFilters', () {
    ShoppingItem itemHeldBy(String? claimedBy) => ShoppingItem(
          id: 'i1',
          label: 'Pain',
          checked: false,
          quantityValue: 1,
          quantityUnit: ShoppingUnit.unit,
          createdAt: DateTime(2026),
          claimedBy: claimedBy,
        );

    bool claimedByMe(String? claimedBy) =>
        shoppingItemMatchesShoppingListFilters(
          itemHeldBy(claimedBy),
          statusFilter: ShoppingListStatusFilter.all,
          onlyClaimedByMe: true,
          currentUid: 'u1',
          currentParticipantId: 'm1',
        );

    test('recognizes items held by the account or the participant id', () {
      expect(claimedByMe('u1'), isTrue);
      expect(claimedByMe('m1'), isTrue);
      expect(claimedByMe('m2'), isFalse);
      expect(claimedByMe(null), isFalse);
    });

    test('keeps only private items when the private filter is on, '
        'combined with the other filters', () {
      ShoppingItem item({required bool isPrivate, required bool checked}) =>
          ShoppingItem(
            id: 'i1',
            label: 'Crème solaire',
            checked: checked,
            quantityValue: 1,
            quantityUnit: ShoppingUnit.unit,
            createdAt: DateTime(2026),
            claimedBy: 'u1',
            isPrivate: isPrivate,
          );
      bool matches(
        ShoppingItem it, {
        ShoppingListStatusFilter status = ShoppingListStatusFilter.all,
        bool onlyClaimedByMe = false,
      }) =>
          shoppingItemMatchesShoppingListFilters(
            it,
            statusFilter: status,
            onlyClaimedByMe: onlyClaimedByMe,
            currentUid: 'u1',
            onlyPrivate: true,
          );

      expect(matches(item(isPrivate: true, checked: false)), isTrue);
      expect(matches(item(isPrivate: false, checked: false)), isFalse);
      expect(
        matches(
          item(isPrivate: true, checked: true),
          status: ShoppingListStatusFilter.todo,
        ),
        isFalse,
      );
      expect(
        matches(item(isPrivate: true, checked: false), onlyClaimedByMe: true),
        isTrue,
      );
    });
  });

  group('ShoppingListFilterBar', () {
    Future<void> pumpBar(WidgetTester tester, double width) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ShoppingListFilterBar(
                selectedStatus: ShoppingListStatusFilter.all,
                onlyClaimedByMe: false,
                onStatusChanged: (_) {},
                onOnlyClaimedByMeChanged: (_) {},
                onOnlyPrivateChanged: (_) {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('spreads the chips from one margin to the other',
        (tester) async {
      await pumpBar(tester, 1000);
      final chips = find.byType(RawChip);
      expect(chips, findsNWidgets(5));
      expect(tester.getTopLeft(chips.first).dx, 16);
      expect(tester.getTopRight(chips.last).dx, 1000 - 16);
    });

    testWidgets('scrolls instead of overflowing on a narrow screen',
        (tester) async {
      await pumpBar(tester, 240);
      expect(tester.takeException(), isNull);
      expect(find.byType(RawChip), findsNWidgets(5));
    });
  });
}
