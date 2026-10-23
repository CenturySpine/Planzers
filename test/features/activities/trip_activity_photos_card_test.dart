import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/activities/data/activity_photo.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_photos_card.dart';

TripActivity _activity(String id, {DateTime? plannedAt}) {
  return TripActivity(
    id: id,
    label: id,
    category: TripActivityCategory.visit,
    linkUrl: '',
    address: '',
    freeComments: '',
    createdBy: 'u1',
    createdAt: DateTime(2025, 1, 1),
    plannedAt: plannedAt,
  );
}

ActivityPhoto _photo(String id, String activityId) {
  return ActivityPhoto(id: id, activityId: activityId, url: 'u', thumbUrl: 't');
}

void main() {
  group('activityPhotosCountOnDay', () {
    final morning = _activity('morning', plannedAt: DateTime(2025, 6, 10, 9));
    final evening = _activity('evening', plannedAt: DateTime(2025, 6, 10, 21));
    final nextDay = _activity('nextDay', plannedAt: DateTime(2025, 6, 11, 10));
    final unplanned = _activity('unplanned');
    final photos = [
      _photo('p1', 'morning'),
      _photo('p2', 'morning'),
      _photo('p3', 'evening'),
      _photo('p4', 'nextDay'),
      _photo('p5', 'unplanned'),
      _photo('p6', 'deleted'),
    ];

    test('counts the photos of every activity of the same day', () {
      final count = activityPhotosCountOnDay(
        photos: photos,
        activitiesById: {
          for (final a in [morning, evening, nextDay, unplanned]) a.id: a,
        },
        day: DateTime(2025, 6, 10, 15),
      );
      expect(count, 3);
    });

    test('follows an activity moved to another day', () {
      final moved = _activity('evening', plannedAt: DateTime(2025, 6, 11, 21));
      final activitiesById = {
        for (final a in [morning, moved, nextDay, unplanned]) a.id: a,
      };
      expect(
        activityPhotosCountOnDay(
          photos: photos,
          activitiesById: activitiesById,
          day: DateTime(2025, 6, 10),
        ),
        2,
      );
      expect(
        activityPhotosCountOnDay(
          photos: photos,
          activitiesById: activitiesById,
          day: DateTime(2025, 6, 11),
        ),
        2,
      );
    });
  });

  group('activityFavoritePhotos', () {
    ActivityPhoto photo(String id, String activityId,
            {bool favorite = false, DateTime? createdAt}) =>
        ActivityPhoto(
          id: id,
          activityId: activityId,
          url: 'u',
          thumbUrl: 't',
          favorite: favorite,
          createdAt: createdAt,
        );

    test('maps each activity to its favorite photo only', () {
      final favorites = activityFavoritePhotos([
        photo('p1', 'a1'),
        photo('p2', 'a1', favorite: true),
        photo('p3', 'a2'),
        photo('p4', 'a3', favorite: true),
      ]);
      expect(favorites.keys, unorderedEquals(['a1', 'a3']));
      expect(favorites['a1']!.id, 'p2');
      expect(favorites['a3']!.id, 'p4');
    });

    test('keeps the first in display order when two are marked', () {
      final favorites = activityFavoritePhotos([
        photo('late', 'a1', favorite: true, createdAt: DateTime(2025, 2, 1)),
        photo('early', 'a1', favorite: true, createdAt: DateTime(2025, 1, 1)),
      ]);
      expect(favorites['a1']!.id, 'early');
    });
  });

  test('compareActivityPhotos puts pending photos last', () {
    final pending = _photo('b', 'a');
    final older = ActivityPhoto(
      id: 'c',
      activityId: 'a',
      url: 'u',
      thumbUrl: 't',
      createdAt: DateTime(2025, 1, 1),
    );
    final newer = ActivityPhoto(
      id: 'a',
      activityId: 'a',
      url: 'u',
      thumbUrl: 't',
      createdAt: DateTime(2025, 2, 1),
    );
    final sorted = [pending, newer, older]..sort(compareActivityPhotos);
    expect(sorted.map((p) => p.id), ['c', 'a', 'b']);
  });
}
