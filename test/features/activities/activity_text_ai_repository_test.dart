import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/activities/data/activity_text_ai_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';

void main() {
  group('TripActivityTextProposal', () {
    test('reads the time as a device local time', () {
      final proposal = TripActivityTextProposal.fromMap({
        'label': 'Kayak à Cala Gonone',
        'category': 'sport',
        'plannedAtLocal': '2026-07-11T14:00',
        'durationMinutes': 180,
        'address': 'Plage de Cala Gonone',
        'freeComments': '',
      });

      expect(proposal.category, TripActivityCategory.sport);
      expect(proposal.plannedAt, DateTime(2026, 7, 11, 14));
      expect(proposal.plannedAt!.isUtc, isFalse);
      expect(proposal.durationMinutes, 180);
      expect(proposal.address, 'Plage de Cala Gonone');
    });

    test('keeps unknown fields empty', () {
      final proposal = TripActivityTextProposal.fromMap({
        'label': 'Kayak',
        'category': 'unknown',
        'plannedAtLocal': '',
        'durationMinutes': null,
      });

      expect(proposal.category, TripActivityCategory.visit);
      expect(proposal.plannedAt, isNull);
      expect(proposal.durationMinutes, isNull);
      expect(proposal.freeComments, isEmpty);
    });
  });
}
