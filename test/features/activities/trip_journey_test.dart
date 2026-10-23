import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_journey.dart';

TripActivity _activity(
  String id, {
  TripActivityCategory category = TripActivityCategory.visit,
  DateTime? plannedAt,
  GeoPoint? location,
  GeoPoint? departureLocation,
}) {
  return TripActivity(
    id: id,
    label: id,
    category: category,
    linkUrl: '',
    address: '',
    freeComments: '',
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
    plannedAt: plannedAt,
    location: location,
    departureLocation: departureLocation,
  );
}

const _hotel = GeoPoint(36.89, 15.07);
const _cave = GeoPoint(36.93, 15.03);
const _station = GeoPoint(36.88, 15.06);
const _catania = GeoPoint(37.50, 15.09);

LatLng _p(GeoPoint point) => LatLng(point.latitude, point.longitude);

void main() {
  test('stops are numbered in time order, linked by plain lines', () {
    final journey = buildTripJourney([
      _activity('cave', plannedAt: DateTime(2026, 5, 2, 10), location: _cave),
      _activity(
        'hotel',
        category: TripActivityCategory.accommodation,
        plannedAt: DateTime(2026, 5, 1, 18),
        location: _hotel,
      ),
      _activity('suggestion', location: _catania),
      _activity('unlocated', plannedAt: DateTime(2026, 5, 2, 8)),
      _activity(
        'restaurant',
        category: TripActivityCategory.restaurant,
        plannedAt: DateTime(2026, 5, 2, 12),
        location: _catania,
      ),
    ]);

    expect(
      journey.stops.map((s) => (s.number, s.activity.id)),
      [(1, 'hotel'), (2, 'cave')],
    );
    expect(journey.legs, hasLength(1));
    expect(journey.legs.single.transport, isNull);
    expect((journey.legs.single.from, journey.legs.single.to),
        (_p(_hotel), _p(_cave)));
  });

  test('a transport draws its own line, linked to the place before it', () {
    final journey = buildTripJourney([
      _activity(
        'hotel',
        plannedAt: DateTime(2026, 5, 1, 8),
        location: _hotel,
      ),
      _activity(
        'train',
        category: TripActivityCategory.transport,
        plannedAt: DateTime(2026, 5, 1, 9),
        departureLocation: _station,
        location: _catania,
      ),
      _activity(
        'catania',
        plannedAt: DateTime(2026, 5, 1, 12),
        location: _catania,
      ),
    ]);

    expect(journey.stops.map((s) => s.activity.id), ['hotel', 'catania']);
    expect(
      journey.legs.map((l) => (l.from, l.to, l.transport?.id)),
      [
        (_p(_hotel), _p(_station), null),
        (_p(_station), _p(_catania), 'train'),
      ],
    );
  });

  test('a transport without its ends joins the places around it', () {
    final journey = buildTripJourney([
      _activity('hotel', plannedAt: DateTime(2026, 5, 1, 8), location: _hotel),
      _activity(
        'bus',
        category: TripActivityCategory.transport,
        plannedAt: DateTime(2026, 5, 1, 9),
      ),
      _activity('cave', plannedAt: DateTime(2026, 5, 1, 10), location: _cave),
    ]);

    expect(
      journey.legs.map((l) => (l.from, l.to, l.transport?.id)),
      [(_p(_hotel), _p(_cave), 'bus')],
    );
  });

  test('stops at the same place share one marker', () {
    final journey = buildTripJourney([
      for (var night = 1; night <= 5; night++) ...[
        _activity(
          'hotel$night',
          category: TripActivityCategory.accommodation,
          plannedAt: DateTime(2026, 5, night, 21),
          location: _hotel,
        ),
        _activity(
          'cave$night',
          plannedAt: DateTime(2026, 5, night, 10),
          location: _cave,
        ),
      ],
    ]);

    final places = journey.places;
    expect(places.map((p) => p.point), [_p(_cave), _p(_hotel)]);
    expect(places.first.numbersLabel, '1·3 +3');
    expect(places.last.stops.map((s) => s.activity.id).first, 'hotel1');
    expect(
      buildTripJourney([
        _activity('a', plannedAt: DateTime(2026, 5, 1, 9), location: _hotel),
        _activity('b', plannedAt: DateTime(2026, 5, 1, 10), location: _cave),
        _activity('c', plannedAt: DateTime(2026, 5, 1, 11), location: _hotel),
      ]).places.first.numbersLabel,
      '1·3',
    );
  });

  test('one day at a time, and the days that have places', () {
    final activities = [
      _activity('d1', plannedAt: DateTime(2026, 5, 1, 9), location: _hotel),
      _activity('d2', plannedAt: DateTime(2026, 5, 2, 9), location: _cave),
      _activity('d3-unlocated', plannedAt: DateTime(2026, 5, 3, 9)),
    ];

    expect(tripJourneyDays(activities), [DateTime(2026, 5, 1), DateTime(2026, 5, 2)]);
    final day2 = buildTripJourney(activities, day: DateTime(2026, 5, 2));
    expect(day2.stops.map((s) => (s.number, s.activity.id)), [(1, 'd2')]);
    expect(day2.legs, isEmpty);
    expect(buildTripJourney(const []).isEmpty, isTrue);
  });
}
