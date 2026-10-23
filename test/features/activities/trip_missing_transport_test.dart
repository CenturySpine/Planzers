import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_journey.dart';
import 'package:planerz/features/activities/presentation/trip_missing_transport.dart';

TripActivity _activity(
  String label, {
  TripActivityCategory category = TripActivityCategory.visit,
  required DateTime plannedAt,
  int? durationMinutes,
  String address = '',
  GeoPoint? location,
  String departureAddress = '',
  GeoPoint? departureLocation,
}) {
  return TripActivity(
    id: label,
    label: label,
    category: category,
    linkUrl: '',
    address: address,
    freeComments: '',
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
    plannedAt: plannedAt,
    durationMinutes: durationMinutes,
    location: location,
    departureAddress: departureAddress,
    departureLocation: departureLocation,
  );
}

// Borgo degli Ulivi to Cava Carosello: about 15 km. The café is 300 m from
// the cave.
const _hotel = GeoPoint(37.048, 14.951);
const _cave = GeoPoint(36.927, 15.026);
const _cafe = GeoPoint(36.9285, 15.0285);
const _station = GeoPoint(36.884, 15.072);
const _catania = GeoPoint(37.506, 15.098);

void main() {
  test('only moves over a kilometre with no transport planned', () {
    final missing = tripMissingTransports(
      buildTripJourney([
        _activity(
          'Borgo degli Ulivi',
          category: TripActivityCategory.accommodation,
          plannedAt: DateTime(2026, 5, 1, 21),
          address: 'Contrada Bibbia',
          location: _hotel,
        ),
        _activity('Cava Carosello',
            plannedAt: DateTime(2026, 5, 2, 10), location: _cave),
        _activity('Café', plannedAt: DateTime(2026, 5, 2, 13), location: _cafe),
      ]),
    );

    expect(missing, hasLength(1));
    final hotelToCave = missing.single;
    expect((hotelToCave.fromName, hotelToCave.toName),
        ('Borgo degli Ulivi', 'Cava Carosello'));
    expect((hotelToCave.fromAddress, hotelToCave.toAddress),
        ('Contrada Bibbia', 'Cava Carosello'));
    expect(hotelToCave.distanceMeters, inInclusiveRange(14000, 16000));
  });

  test('a transport ends a move and starts the next one', () {
    final missing = tripMissingTransports(
      buildTripJourney([
        _activity('Borgo degli Ulivi',
            plannedAt: DateTime(2026, 5, 3, 7), location: _hotel),
        _activity(
          'Train',
          category: TripActivityCategory.transport,
          plannedAt: DateTime(2026, 5, 3, 9),
          departureAddress: 'Gare de Noto',
          departureLocation: _station,
          address: 'Gare de Catane',
          location: _catania,
        ),
        _activity('Cava Carosello',
            plannedAt: DateTime(2026, 5, 3, 15), location: _cave),
      ]),
    );

    expect(
      missing.map((m) => (m.fromName, m.toName)),
      [
        ('Borgo degli Ulivi', 'Gare de Noto'),
        ('Gare de Catane', 'Cava Carosello'),
      ],
    );
    expect(missing.first.toAddress, 'Gare de Noto');
    expect(missing.last.fromAddress, 'Gare de Catane');
  });

  test('the transport arrives as the next activity starts', () {
    final missing = TripMissingTransport(
      // A visit from 7:00, ending at 9:00 (two hours by default).
      from: _activity('Noto', plannedAt: DateTime(2026, 5, 2, 7)),
      to: _activity('Cava Carosello', plannedAt: DateTime(2026, 5, 2, 10)),
      fromPoint: const LatLng(36.892, 15.069),
      toPoint: const LatLng(36.927, 15.026),
      distanceMeters: 15000,
    );

    // 15 km by car: 15 * 1.3 / 50 h = 23.4 min, rounded up to 25.
    final byCar = missing.schedule(TripTransportMode.car);
    expect(byCar.minutes, 25);
    expect(byCar.start, DateTime(2026, 5, 2, 9, 35));

    // Four hours on foot would mean leaving at 6:00, during the visit: it
    // leaves when the visit ends instead.
    final onFoot = missing.schedule(TripTransportMode.walk);
    expect(onFoot.minutes, 240);
    expect(onFoot.start, DateTime(2026, 5, 2, 9));
  });

  test('travel times per mode stay plausible', () {
    expect(estimateTripTravelMinutes(1200, TripTransportMode.walk), 20);
    expect(estimateTripTravelMinutes(1200, TripTransportMode.car), 5);
    expect(estimateTripTravelMinutes(1100000, TripTransportMode.plane), 185);
  });
}
