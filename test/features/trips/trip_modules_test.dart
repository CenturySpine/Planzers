import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/presentation/trip_module_tab.dart';

Trip _trip([Map<String, dynamic> data = const {}]) => Trip.fromMap('t1', {
      'title': 'Test',
      'ownerId': 'owner',
      'memberUserIds': ['owner', 'traveler'],
      ...data,
    });

void main() {
  group('modules', () {
    test('trips created before the new modules have them all', () {
      final trip = _trip();
      expect(trip.journeyModuleEnabled, isTrue);
      expect(trip.homeMealsModuleEnabled, isTrue);
      expect(trip.shoppingModuleEnabled, isTrue);
    });

    test('modules switched off are read back and written', () {
      final trip = _trip({
        'journeyModuleEnabled': false,
        'homeMealsModuleEnabled': false,
        'shoppingModuleEnabled': false,
      });
      expect(trip.journeyModuleEnabled, isFalse);
      expect(trip.homeMealsModuleEnabled, isFalse);
      expect(trip.shoppingModuleEnabled, isFalse);
      final map = trip.toMap();
      expect(map['journeyModuleEnabled'], isFalse);
      expect(map['homeMealsModuleEnabled'], isFalse);
      expect(map['shoppingModuleEnabled'], isFalse);
    });
  });

  group('fifth tab', () {
    test('shopping comes first', () {
      expect(tripModuleTabFor(_trip()), TripModuleTab.shopping);
    });

    test('the map without shopping', () {
      expect(
        tripModuleTabFor(_trip({'shoppingModuleEnabled': false})),
        TripModuleTab.map,
      );
    });

    test('none without shopping nor itinerary', () {
      expect(
        tripModuleTabFor(_trip({
          'shoppingModuleEnabled': false,
          'journeyModuleEnabled': false,
        })),
        isNull,
      );
    });
  });

  group('rooms permission', () {
    test('open to participants on trips without it', () {
      final trip = _trip();
      expect(
        trip.roomsPermissions.manageRoomsMinRole,
        TripPermissionRole.participant,
      );
      expect(canManageRoomsForTrip(trip: trip, userId: 'traveler'), isTrue);
      expect(canManageRoomsForTrip(trip: trip, userId: 'stranger'), isFalse);
    });

    test('kept for admins when set so', () {
      final trip = _trip({
        'permissions': {
          'rooms': {'manageRooms': 'admin'},
        },
      });
      expect(canManageRoomsForTrip(trip: trip, userId: 'traveler'), isFalse);
      expect(canManageRoomsForTrip(trip: trip, userId: 'owner'), isTrue);
      expect(
        trip.toMap()['permissions']['rooms'],
        {'manageRooms': 'admin'},
      );
    });
  });

  group('own stay permission', () {
    test('every traveler sets their dates by default', () {
      final trip = _trip();
      expect(canEditOwnStayForTrip(trip: trip, userId: 'traveler'), isTrue);
      // Someone joining counts as a participant.
      expect(canEditOwnStayForTrip(trip: trip, userId: 'newcomer'), isTrue);
    });

    test('the organizer sets them when locked', () {
      final trip = _trip({
        'permissions': {
          'participants': {'editOwnStay': 'admin'},
        },
      });
      expect(canEditOwnStayForTrip(trip: trip, userId: 'traveler'), isFalse);
      expect(canEditOwnStayForTrip(trip: trip, userId: 'newcomer'), isFalse);
      expect(canEditOwnStayForTrip(trip: trip, userId: 'owner'), isTrue);
    });
  });

  test('a stay in whole days runs from the first morning to the last evening',
      () {
    const stay = TripMemberStay(
      startDateKey: '2026-08-01',
      startDayPart: TripDayPart.evening,
      endDateKey: '2026-08-03',
      endDayPart: TripDayPart.morning,
    );
    final wholeDays = stay.asWholeDays();
    expect(wholeDays.startDateKey, '2026-08-01');
    expect(wholeDays.startDayPart, TripDayPart.morning);
    expect(wholeDays.endDateKey, '2026-08-03');
    expect(wholeDays.endDayPart, TripDayPart.evening);
  });
}
