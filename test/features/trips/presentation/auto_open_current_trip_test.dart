import 'package:flutter_test/flutter_test.dart';
import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/presentation/auto_open_current_trip.dart';

void main() {
  Trip buildTrip({
    required String id,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return Trip(
      id: id,
      title: 'Trip $id',
      destination: 'Destination',
      address: '',
      linkUrl: '',
      ownerId: 'owner',
      memberIds: const ['owner'],
      createdAt: DateTime(2026, 1, 1),
      startDate: startDate,
      endDate: endDate,
    );
  }

  test('returns null when preference is disabled', () {
    final trips = [
      buildTrip(
        id: 'a',
        startDate: DateTime(2026, 4, 10),
        endDate: DateTime(2026, 4, 20),
      ),
    ];

    final result = resolveTripToAutoOpen(
      trips: trips,
      isPreferenceEnabled: false,
      now: DateTime(2026, 4, 17),
    );

    expect(result, isNull);
  });

  test('returns trip when exactly one trip is ongoing today', () {
    final ongoingTrip = buildTrip(
      id: 'a',
      startDate: DateTime(2026, 4, 10),
      endDate: DateTime(2026, 4, 20),
    );
    final trips = [
      ongoingTrip,
      buildTrip(
        id: 'b',
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 5, 3),
      ),
    ];

    final result = resolveTripToAutoOpen(
      trips: trips,
      isPreferenceEnabled: true,
      now: DateTime(2026, 4, 17),
    );

    expect(result?.id, ongoingTrip.id);
  });

  test('returns null when multiple trips are ongoing today', () {
    final trips = [
      buildTrip(
        id: 'a',
        startDate: DateTime(2026, 4, 10),
        endDate: DateTime(2026, 4, 20),
      ),
      buildTrip(
        id: 'b',
        startDate: DateTime(2026, 4, 15),
        endDate: DateTime(2026, 4, 25),
      ),
    ];

    final result = resolveTripToAutoOpen(
      trips: trips,
      isPreferenceEnabled: true,
      now: DateTime(2026, 4, 17),
    );

    expect(result, isNull);
  });

  test('returns null when one trip exists but today is out of range', () {
    final trips = [
      buildTrip(
        id: 'a',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 5),
      ),
    ];

    final result = resolveTripToAutoOpen(
      trips: trips,
      isPreferenceEnabled: true,
      now: DateTime(2026, 4, 17),
    );

    expect(result, isNull);
  });
}
