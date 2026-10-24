import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/activities/data/activity_photo.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_photos_card.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';

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

TripMeal _meal(String id, String dateKey) {
  return TripMeal(
    id: id,
    mealDateKey: dateKey,
    mealDayPart: TripDayPart.midday,
    mealTimeHHMM: '12:30',
    participantIds: const [],
    createdBy: 'u1',
    createdAt: DateTime(2025, 1, 1),
  );
}

ActivityPhoto _photo(String id, String activityId) {
  return ActivityPhoto(id: id, activityId: activityId, url: 'u', thumbUrl: 't');
}

void main() {
  group('photosCountOnDay', () {
    final morning = _activity('morning', plannedAt: DateTime(2025, 6, 10, 9));
    final evening = _activity('evening', plannedAt: DateTime(2025, 6, 10, 21));
    final nextDay = _activity('nextDay', plannedAt: DateTime(2025, 6, 11, 10));
    final unplanned = _activity('unplanned');
    final lunch = _meal('lunch', '2025-06-10');
    final photos = [
      _photo('p1', 'morning'),
      _photo('p2', 'morning'),
      _photo('p3', 'evening'),
      _photo('p4', 'nextDay'),
      _photo('p5', 'unplanned'),
      _photo('p6', 'deleted'),
      const ActivityPhoto(id: 'p7', mealId: 'lunch', url: 'u', thumbUrl: 't'),
    ];

    test('counts the photos of every activity and meal of the same day', () {
      final count = photosCountOnDay(
        photos: photos,
        subjectDays: photoSubjectDays(
          activities: [morning, evening, nextDay, unplanned],
          meals: [lunch],
        ),
        day: DateTime(2025, 6, 10, 15),
      );
      expect(count, 4);
    });

    test('follows an activity or a meal moved to another day', () {
      final moved = _activity('evening', plannedAt: DateTime(2025, 6, 11, 21));
      final subjectDays = photoSubjectDays(
        activities: [morning, moved, nextDay, unplanned],
        meals: [_meal('lunch', '2025-06-11')],
      );
      expect(
        photosCountOnDay(
          photos: photos,
          subjectDays: subjectDays,
          day: DateTime(2025, 6, 10),
        ),
        2,
      );
      expect(
        photosCountOnDay(
          photos: photos,
          subjectDays: subjectDays,
          day: DateTime(2025, 6, 11),
        ),
        3,
      );
    });
  });

  test('the application owner gets a larger daily limit', () {
    expect(activityPhotosMaxPerDayFor(isApplicationOwner: false), 10);
    expect(activityPhotosMaxPerDayFor(isApplicationOwner: true), 15);
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

  group('resolveActivityFavorites', () {
    ActivityPhoto photo(String owner, String id, String activityId,
            {bool favorite = false}) =>
        ActivityPhoto(
          id: id,
          ownerId: owner,
          activityId: activityId,
          url: 'u',
          thumbUrl: 't',
          favorite: favorite,
        );
    ActivityFavoriteRef ref(String subjectId, String owner, String id) =>
        ActivityFavoriteRef(subjectId: subjectId, ownerId: owner, photoId: id);

    final mine = [
      photo('me', 'm1', 'a1', favorite: true),
      photo('me', 'm2', 'a2', favorite: true),
      photo('me', 'm3', 'a3'),
    ];
    final others = [photo('bob', 'b1', 'a1'), photo('bob', 'b3', 'a3')];

    test('a chosen favorite wins, even another member photo', () {
      final favorites = resolveActivityFavorites(
        favorites: {'a1': ref('a1', 'bob', 'b1')},
        visiblePhotos: [...mine, ...others],
        myPhotos: mine,
      );
      expect(favorites['a1']!.key, 'bob/b1');
    });

    test('a meal has its favorite photo too', () {
      const mealPhoto = ActivityPhoto(
        id: 'b9',
        ownerId: 'bob',
        mealId: 'lunch',
        url: 'u',
        thumbUrl: 't',
      );
      final favorites = resolveActivityFavorites(
        favorites: {'lunch': ref('lunch', 'bob', 'b9')},
        visiblePhotos: [...mine, ...others, mealPhoto],
        myPhotos: mine,
      );
      expect(favorites['lunch']!.key, 'bob/b9');
    });

    test('activities never chosen again keep the former mark', () {
      final favorites = resolveActivityFavorites(
        favorites: const {},
        visiblePhotos: [...mine, ...others],
        myPhotos: mine,
      );
      expect(favorites['a2']!.key, 'me/m2');
      expect(favorites.containsKey('a3'), isFalse);
    });

    test('a favorite whose photo is gone or private shows none', () {
      final favorites = resolveActivityFavorites(
        favorites: {'a3': ref('a3', 'bob', 'deleted')},
        visiblePhotos: [...mine, ...others],
        myPhotos: mine,
      );
      expect(favorites.containsKey('a3'), isFalse);
    });

    test('a favorite pointing at a photo of another activity is ignored', () {
      final favorites = resolveActivityFavorites(
        favorites: {'a2': ref('a2', 'bob', 'b1')},
        visiblePhotos: [...mine, ...others],
        myPhotos: mine,
      );
      expect(favorites.containsKey('a2'), isFalse);
    });
  });

  test('PhotoReport.idFor gives one report per reporter and photo', () {
    expect(
      PhotoReport.idFor(reporterId: 'me', photoOwnerId: 'bob', photoId: 'b1'),
      'me_bob_b1',
    );
  });

  group('photo reports', () {
    PhotoReport report(String reporter, String owner, String photo,
            {PhotoReportResolution? resolution, int day = 1}) =>
        PhotoReport(
          id: '${reporter}_${owner}_$photo',
          tripId: 't1',
          photoOwnerId: owner,
          photoId: photo,
          activityId: 'a1',
          reporterId: reporter,
          reason: PhotoReportReason.other,
          resolution: resolution,
          createdAt: DateTime(2026, 10, day),
        );

    test('groups by photo, most pending reports first', () {
      final groups = groupPhotoReports([
        report('r1', 'bob', 'p1', day: 1),
        report('r2', 'bob', 'p1', day: 2),
        report('r3', 'bob', 'p1', day: 3),
        report('r1', 'ann', 'p2', day: 5),
        report('r2', 'ann', 'p3',
            day: 6, resolution: PhotoReportResolution.dismissed),
      ]);
      expect(groups.map((g) => g.photoId), ['p1', 'p2', 'p3']);
      expect(groups.first.reports.map((r) => r.reporterId), ['r3', 'r2', 'r1']);
      expect(groups.first.thresholdReached, isTrue);
      expect(groups[1].thresholdReached, isFalse);
      expect(groups[2].pending, isEmpty);
    });

    test('handled reports do not count towards the threshold', () {
      final group = groupPhotoReports([
        report('r1', 'bob', 'p1'),
        report('r2', 'bob', 'p1'),
        report('r3', 'bob', 'p1', resolution: PhotoReportResolution.dismissed),
      ]).single;
      expect(group.pending, hasLength(2));
      expect(group.thresholdReached, isFalse);
    });

    test('reporter stats tell outcomes and targeted authors', () {
      final stats = photoReporterStats([
        report('r1', 'bob', 'p1', resolution: PhotoReportResolution.dismissed),
        report('r1', 'bob', 'p2', resolution: PhotoReportResolution.dismissed),
        report('r1', 'bob', 'p3'),
        report('r2', 'ann', 'p4',
            resolution: PhotoReportResolution.photoRemoved),
      ]);
      expect(stats.first.reporterId, 'r1');
      expect(stats.first.total, 3);
      expect(stats.first.pending, 1);
      expect(stats.first.dismissed, 2);
      expect(stats.first.distinctAuthors, 1);
      expect(stats.last.photoRemoved, 1);
    });

    test('reports dismissed before outcomes existed read as dismissed', () {
      expect(
        PhotoReportResolution.fromFirestore({'dismissed': true}),
        PhotoReportResolution.dismissed,
      );
      expect(
        PhotoReportResolution.fromFirestore({'resolution': 'photoRemoved'}),
        PhotoReportResolution.photoRemoved,
      );
      expect(PhotoReportResolution.fromFirestore({}), isNull);
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
