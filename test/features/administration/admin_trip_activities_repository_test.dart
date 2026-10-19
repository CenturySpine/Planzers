import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/administration/data/admin_trip_activities_repository.dart';

void main() {
  group('AdminTripActivityCount', () {
    test('reads a trip sent by the server', () {
      final trip = AdminTripActivityCount.fromMap({
        'tripId': 'abc123',
        'title': 'Sardaigne',
        'startDate': '2026-07-10',
        'endDate': '2026-07-17',
        'activityCount': 12,
      });

      expect(trip.tripId, 'abc123');
      expect(trip.title, 'Sardaigne');
      expect(trip.startDate, '2026-07-10');
      expect(trip.activityCount, 12);
    });

    test('keeps missing fields empty', () {
      final trip = AdminTripActivityCount.fromMap({'tripId': 'abc123'});

      expect(trip.title, isEmpty);
      expect(trip.endDate, isEmpty);
      expect(trip.activityCount, 0);
    });
  });
}
