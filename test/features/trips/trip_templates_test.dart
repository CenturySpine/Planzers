import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trip_templates.dart';
import 'package:planerz/features/trips/presentation/trip_template_picker.dart';
import 'package:planerz/l10n/app_localizations.dart';

Trip _tripFrom(TripTemplate template) => Trip.fromMap('t1', {
      'title': 'Test',
      'ownerId': 'owner',
      'memberUserIds': ['owner', 'traveler'],
      'permissions': template.settings.permissions.toFirestore(),
    });

void main() {
  group('presets', () {
    test('a stay with friends has rooms, home meals and shopping, no map', () {
      final s = TripTemplate.friendsStay.settings;
      expect(s.journeyModuleEnabled, isFalse);
      expect(s.homeMealsModuleEnabled, isTrue);
      expect(s.shoppingModuleEnabled, isTrue);
      expect(s.roomsModuleEnabled, isTrue);
      expect(s.carpoolModuleEnabled, isTrue);
      expect(s.lodgingAllNights, isTrue);
    });

    test('a road trip keeps the itinerary only, night by night', () {
      final s = TripTemplate.roadTrip.settings;
      expect(s.journeyModuleEnabled, isTrue);
      expect(s.homeMealsModuleEnabled, isFalse);
      expect(s.shoppingModuleEnabled, isFalse);
      expect(s.roomsModuleEnabled, isFalse);
      expect(s.carpoolModuleEnabled, isFalse);
      expect(s.gamesModuleEnabled, isFalse);
      expect(s.lodgingAllNights, isFalse);
    });

    test('a day outing is a day trip', () {
      final s = TripTemplate.dayOuting.settings;
      expect(s.isDayTrip, isTrue);
      expect(s.roomsModuleEnabled, isFalse);
      expect(s.journeyModuleEnabled, isFalse);
    });

    test('only the guided trip changes the permissions', () {
      for (final template in TripTemplate.values) {
        expect(
          identical(
            template.settings.permissions,
            TripTemplatePermissions.defaults,
          ),
          template != TripTemplate.guidedTrip,
          reason: template.name,
        );
      }
    });

    test('the permissions block has every section', () {
      expect(
        TripTemplatePermissions.guided.toFirestore().keys,
        unorderedEquals([
          'tripGeneral',
          'participants',
          'expenses',
          'activities',
          'meals',
          'shopping',
          'carpool',
          'rooms',
        ]),
      );
    });
  });

  group('guided trip', () {
    final trip = _tripFrom(TripTemplate.guidedTrip);

    test('travelers cannot change the program, rooms nor their dates', () {
      expect(canSuggestActivityForTrip(trip: trip, userId: 'traveler'), isFalse);
      expect(canEditActivityForTrip(trip: trip, userId: 'traveler'), isFalse);
      expect(canManageRoomsForTrip(trip: trip, userId: 'traveler'), isFalse);
      expect(canEditOwnStayForTrip(trip: trip, userId: 'traveler'), isFalse);
      expect(
        trip.generalPermissions.shareAccessMinRole,
        TripPermissionRole.admin,
      );
      expect(
        trip.mealsPermissions.addContributionMinRole,
        TripPermissionRole.admin,
      );
    });

    test('travelers still share their expenses', () {
      expect(
        canCreateExpenseForTrip(
          trip: trip,
          userId: 'traveler',
          currentUserMemberId: 'm1',
          expensePostVisibleToMemberIds: const ['m1'],
        ),
        isTrue,
      );
    });

    test('the organizer keeps every right', () {
      expect(canSuggestActivityForTrip(trip: trip, userId: 'owner'), isTrue);
      expect(canManageRoomsForTrip(trip: trip, userId: 'owner'), isTrue);
      expect(canEditOwnStayForTrip(trip: trip, userId: 'owner'), isTrue);
    });
  });

  testWidgets('a chosen template shows what it offers and its modules',
      (tester) async {
    TripTemplate? selected;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TripTemplatePicker(
              selected: selected,
              onSelected: (template) => setState(() => selected = template),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Voyage organisé'), findsOneWidget);
    expect(find.text("Seul l'organisateur invite de nouveaux voyageurs."),
        findsNothing);

    await tester.tap(find.text('Voyage organisé'));
    await tester.pump();

    expect(selected, TripTemplate.guidedTrip);
    expect(find.text("Seul l'organisateur invite de nouveaux voyageurs."),
        findsOneWidget);
    expect(find.text('Itinéraire'), findsOneWidget);
    expect(find.text('Chambres'), findsOneWidget);
    expect(find.text('Courses'), findsNothing);
  });
}
