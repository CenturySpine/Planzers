import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/wallet/data/wallet_activity_import_repository.dart';

void main() {
  group('WalletActivityProposal', () {
    test('reads the document time as a device local time', () {
      final proposal = WalletActivityProposal.fromMap({
        'label': 'Vol Paris → Rome',
        'category': 'transport',
        'plannedAtLocal': '2026-10-10T18:20',
        'durationMinutes': 125,
        'address': '',
        'freeComments': 'AF1234',
        'sourceDocumentIds': ['doc1'],
      });

      expect(proposal.category, TripActivityCategory.transport);
      expect(proposal.plannedAt, DateTime(2026, 10, 10, 18, 20));
      expect(proposal.plannedAt!.isUtc, isFalse);
      expect(proposal.durationMinutes, 125);
      expect(proposal.sourceDocumentIds, ['doc1']);
    });

    test('keeps unknown fields empty', () {
      final proposal = WalletActivityProposal.fromMap({
        'label': 'Visite',
        'category': 'unknown',
        'plannedAtLocal': '',
        'durationMinutes': 0,
      });

      expect(proposal.category, TripActivityCategory.visit);
      expect(proposal.plannedAt, isNull);
      expect(proposal.durationMinutes, isNull);
      expect(proposal.effectiveDuration, const Duration(hours: 2));
    });

    test('sends the planned time as an instant', () {
      final plannedAt = DateTime(2026, 10, 10, 18, 20);
      final map = WalletActivityProposal(
        label: 'Vol',
        category: TripActivityCategory.transport,
        plannedAt: plannedAt,
        durationMinutes: null,
        address: '',
        freeComments: '',
        sourceDocumentIds: const ['doc1'],
      ).toImportMap();

      expect(map['plannedAtMillis'], plannedAt.millisecondsSinceEpoch);
      expect(map.containsKey('durationMinutes'), isFalse);
      expect(map['category'], 'transport');
    });
  });
}
