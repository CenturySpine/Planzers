import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_lifecycle.dart';

Trip _trip({DateTime? start, DateTime? end}) => Trip.fromMap('t1', {
      'title': 'Test',
      if (start != null) 'startDate': Timestamp.fromDate(start),
      if (end != null) 'endDate': Timestamp.fromDate(end),
    });

void main() {
  final end = DateTime(2026, 8, 10);

  test('nothing is shown before or on the last day of the trip', () {
    final trip = _trip(start: DateTime(2026, 8, 1), end: end);
    expect(daysUntilTripAutoArchive(trip, DateTime(2026, 8, 5)), isNull);
    expect(daysUntilTripAutoArchive(trip, DateTime(2026, 8, 10, 23)), isNull);
    expect(daysUntilTripDocumentsDeletion(trip, DateTime(2026, 8, 10)), isNull);
  });

  test('countdowns start the day after the last day', () {
    final trip = _trip(start: DateTime(2026, 8, 1), end: end);
    final dayAfter = DateTime(2026, 8, 11, 9);
    expect(daysUntilTripAutoArchive(trip, dayAfter), 29);
    expect(daysUntilTripDocumentsDeletion(trip, dayAfter), 59);
  });

  test('countdowns reach zero on day 30 and day 60, never negative', () {
    final trip = _trip(start: DateTime(2026, 8, 1), end: end);
    expect(daysUntilTripAutoArchive(trip, DateTime(2026, 9, 9)), 0);
    expect(daysUntilTripDocumentsDeletion(trip, DateTime(2026, 9, 9)), 30);
    expect(daysUntilTripDocumentsDeletion(trip, DateTime(2026, 10, 9)), 0);
    expect(daysUntilTripDocumentsDeletion(trip, DateTime(2027, 1, 1)), 0);
  });

  test('a trip without end date uses its start date; no date means never', () {
    expect(
      daysUntilTripDocumentsDeletion(_trip(start: end), DateTime(2026, 8, 11)),
      59,
    );
    expect(daysUntilTripDocumentsDeletion(_trip(), DateTime(2027, 1, 1)), isNull);
  });
}
