import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';

TripActivity _activity({
  required String id,
  required String label,
  TripActivityCategory category = TripActivityCategory.visit,
  DateTime? plannedAt,
  DateTime? createdAt,
}) {
  return TripActivity(
    id: id,
    label: label,
    category: category,
    linkUrl: '',
    address: '',
    freeComments: '',
    createdBy: 'u1',
    createdAt: createdAt ?? DateTime.utc(2025, 1, 1),
    plannedAt: plannedAt,
  );
}

void main() {
  group('buildTripActivitiesSuggestionEntries', () {
    test('filters unplanned only and sorts by createdAt desc', () {
      final older = _activity(
        id: 'a',
        label: 'Old',
        createdAt: DateTime.utc(2025, 1, 1),
      );
      final newer = _activity(
        id: 'b',
        label: 'New',
        createdAt: DateTime.utc(2025, 6, 1),
      );
      final planned = _activity(
        id: 'c',
        label: 'Planned',
        plannedAt: DateTime.utc(2025, 3, 1),
        createdAt: DateTime.utc(2025, 7, 1),
      );
      final entries = buildTripActivitiesSuggestionEntries(
        [planned, older, newer],
        query: '',
        creatorLabelFor: (_) => 'Alice',
      );
      expect(entries.length, 2);
      expect(entries[0].activity?.id, 'b');
      expect(entries[1].activity?.id, 'a');
    });

    test('filters by category when categoryFilter is set', () {
      final hotel = _activity(
        id: 'h',
        label: 'Hotel',
        category: TripActivityCategory.accommodation,
      );
      final cafe = _activity(
        id: 'c',
        label: 'Cafe',
        category: TripActivityCategory.cafe,
      );
      final entries = buildTripActivitiesSuggestionEntries(
        [hotel, cafe],
        query: '',
        creatorLabelFor: (_) => 'Bob',
        categoryFilter: const [TripActivityCategory.accommodation],
      );
      expect(entries.length, 1);
      expect(entries.single.activity?.id, 'h');
    });

    test('matches query on label', () {
      final a = _activity(id: '1', label: 'Beach day');
      final b = _activity(id: '2', label: 'Museum');
      final entries = buildTripActivitiesSuggestionEntries(
        [a, b],
        query: 'museum',
        creatorLabelFor: (_) => 'x',
      );
      expect(entries.single.activity?.id, '2');
    });
  });

  group('tripActivityMatchesQuery', () {
    test('includes linkPreview string values', () {
      final activity = TripActivity(
        id: 'x',
        label: 'x',
        category: TripActivityCategory.visit,
        linkUrl: '',
        address: '',
        freeComments: '',
        createdBy: 'u',
        createdAt: DateTime.utc(2025),
        linkPreview: {'title': 'UniquePreviewTitle'},
      );
      expect(
        tripActivityMatchesQuery(
          activity,
          'uniquepreview',
          creatorLabel: '',
        ),
        isTrue,
      );
    });
  });

  group('buildTripActivitiesPlannedEntries', () {
    test('inserts day separators and excludes unplanned', () {
      final day1Morning = _activity(
        id: 'm',
        label: 'Morning',
        plannedAt: DateTime.utc(2025, 3, 10, 9, 0),
        createdAt: DateTime.utc(2025),
      );
      final day1Afternoon = _activity(
        id: 'a',
        label: 'Afternoon',
        plannedAt: DateTime.utc(2025, 3, 10, 15, 0),
        createdAt: DateTime.utc(2025),
      );
      final day2 = _activity(
        id: 'd2',
        label: 'Next',
        plannedAt: DateTime.utc(2025, 3, 11, 10, 0),
        createdAt: DateTime.utc(2025),
      );
      final suggestion = _activity(id: 's', label: 'Sug');
      final entries = buildTripActivitiesPlannedEntries(
        [suggestion, day2, day1Afternoon, day1Morning],
        query: '',
        creatorLabelFor: (_) => 'p',
        dayLabelFor: (d) => '${d.year}-${d.month}-${d.day}',
      );
      expect(entries.where((e) => e.daySeparatorLabel != null).length, 2);
      expect(entries.where((e) => e.activity != null).length, 3);
    });
  });
}
