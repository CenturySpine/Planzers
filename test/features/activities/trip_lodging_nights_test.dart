import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_journey.dart';
import 'package:planerz/features/activities/presentation/trip_lodging_nights.dart';
import 'package:planerz/features/activities/presentation/trip_missing_transport.dart';
import 'package:planerz/features/trips/data/trip_lodging.dart';
import 'package:planerz/features/trips/data/trip_lodging_plan.dart';

const _hotel = GeoPoint(37.048, 14.951);
const _cave = GeoPoint(36.927, 15.026);

TripActivity _activity(
  String id, {
  TripActivityCategory category = TripActivityCategory.visit,
  required DateTime plannedAt,
  GeoPoint? location,
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
  );
}

void main() {
  final nights =
      tripNightsBetween(DateTime(2026, 7, 10), DateTime(2026, 7, 13));
  const borgo = TripLodging(
    id: 'borgo',
    name: 'Borgo degli Ulivi',
    location: _hotel,
    nightKeys: ['2026-07-10', '2026-07-11'],
  );

  test('each night is spent at its lodging or is left to fill in', () {
    final planning = tripLodgingNightsForPlanning(
      nights: nights,
      lodgings: [borgo],
      activities: const [],
    );
    expect(planning.map((n) => n.lodging?.id), ['borgo', 'borgo', null]);
    final stop = planning.first.stop;
    expect(isTripLodgingStopId(stop.id), isTrue);
    expect(stop.category, TripActivityCategory.accommodation);
    expect(stop.plannedAt, DateTime(2026, 7, 10, tripLodgingNightStartHour));
    expect(stop.plannedEndAt, DateTime(2026, 7, 11, tripLodgingNightEndHour));
    expect(stop.location, _hotel);
  });

  test('a night with an accommodation planned is left to it', () {
    final planning = tripLodgingNightsForPlanning(
      nights: nights,
      lodgings: [borgo],
      activities: [
        _activity(
          'Nuit en agritourisme',
          category: TripActivityCategory.accommodation,
          plannedAt: DateTime(2026, 7, 12, 20),
        ),
      ],
    );
    expect(planning.map((n) => tripNightKey(n.night)), [
      '2026-07-10',
      '2026-07-11',
    ]);
  });

  test('the journey offers transports to and from the lodging', () {
    final stops = [
      for (final night in tripLodgingNightsForPlanning(
        nights: nights,
        lodgings: [borgo],
        activities: const [],
      ))
        if (!night.isMissing) night.stop,
    ];
    final cave = _activity(
      'cave',
      plannedAt: DateTime(2026, 7, 11, 10),
      location: _cave,
    );
    final missing = tripMissingTransports(buildTripJourney([cave, ...stops]));
    expect(
      missing.map((m) => '${m.from.label} → ${m.to.label}'),
      [
        'Borgo degli Ulivi → cave',
        'cave → Borgo degli Ulivi',
      ],
    );
    // Leaves the lodging once the night is over.
    final morning = missing.first.schedule(TripTransportMode.car);
    expect(
      morning.start.isBefore(DateTime(2026, 7, 11, tripLodgingNightEndHour)),
      isFalse,
    );
  });
}
