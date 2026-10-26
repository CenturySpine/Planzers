import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:planerz/core/presentation/osm_map.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_journey.dart';
import 'package:planerz/features/activities/presentation/trip_missing_transport.dart';
import 'package:planerz/features/activities/presentation/trip_transport_connection.dart';

// Milazzo to Lipari by boat (about 40 km), then a bus across the island to
// Quattrocchi (about 3 km).
const _milazzo = GeoPoint(38.221, 15.241);
const _lipariPort = GeoPoint(38.468, 14.957);
const _quattrocchi = GeoPoint(38.476, 14.925);

TripActivity _boat({
  DateTime? plannedAt,
  int? durationMinutes = 180,
  GeoPoint? departureLocation = _milazzo,
  GeoPoint? location = _quattrocchi,
}) {
  return TripActivity(
    id: 'boat',
    label: 'Milazzo → Quattrocchi',
    category: TripActivityCategory.transport,
    linkUrl: '',
    address: 'Quattrocchi, Lipari',
    freeComments: '',
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
    plannedAt: plannedAt ?? DateTime(2026, 5, 2, 9),
    durationMinutes: durationMinutes,
    location: location,
    departureAddress: 'Milazzo',
    departureLocation: departureLocation,
    transportMode: TripTransportMode.boat,
  );
}

String _route(String from, String to) => '$from → $to';

void main() {
  test('needs a planned transport with its departure and arrival', () {
    expect(canAddTripTransportConnection(_boat()), isTrue);
    expect(canAddTripTransportConnection(_boat(location: null)), isFalse);
    expect(
      canAddTripTransportConnection(_boat(departureLocation: null)),
      isFalse,
    );
    expect(
      canAddTripTransportConnection(
        TripActivity(
          id: 'visit',
          label: 'Visit',
          category: TripActivityCategory.visit,
          linkUrl: '',
          address: '',
          freeComments: '',
          createdBy: 'u1',
          createdAt: DateTime(2026, 1, 1),
          plannedAt: DateTime(2026, 5, 2, 9),
          location: _quattrocchi,
        ),
      ),
      isFalse,
    );
  });

  test('the first part keeps its start, the second arrives on time', () {
    final schedule = tripTransportConnectionSchedule(
      _boat(),
      stop: _lipariPort.toLatLng(),
      mode: TripTransportMode.bus,
    );

    expect(
      schedule.firstMinutes,
      estimateTripTravelMinutes(
        const Distance().as(
          LengthUnit.Meter,
          _milazzo.toLatLng(),
          _lipariPort.toLatLng(),
        ),
        TripTransportMode.boat,
      ),
    );
    expect(
      schedule.secondStart.add(Duration(minutes: schedule.secondMinutes)),
      DateTime(2026, 5, 2, 12),
    );
  });

  test('the second part never leaves before the first one arrives', () {
    final schedule = tripTransportConnectionSchedule(
      _boat(durationMinutes: 30),
      stop: _lipariPort.toLatLng(),
      mode: TripTransportMode.bus,
    );

    expect(
      schedule.secondStart,
      DateTime(2026, 5, 2, 9).add(Duration(minutes: schedule.firstMinutes)),
    );
  });

  test('the parts follow each other on the journey with no gap', () {
    final boat = _boat();
    final schedule = tripTransportConnectionSchedule(
      boat,
      stop: _lipariPort.toLatLng(),
      mode: TripTransportMode.bus,
    );
    final firstPart = TripActivity(
      id: boat.id,
      label: boat.label,
      category: boat.category,
      linkUrl: '',
      address: 'Porto di Lipari',
      freeComments: '',
      createdBy: 'u1',
      createdAt: boat.createdAt,
      plannedAt: boat.plannedAt,
      durationMinutes: schedule.firstMinutes,
      location: _lipariPort,
      departureAddress: boat.departureAddress,
      departureLocation: boat.departureLocation,
      transportMode: boat.transportMode,
    );
    final secondPart = TripActivity(
      id: 'bus',
      label: 'Porto di Lipari → Quattrocchi',
      category: TripActivityCategory.transport,
      linkUrl: '',
      address: boat.address,
      freeComments: '',
      createdBy: 'u1',
      createdAt: boat.createdAt,
      plannedAt: schedule.secondStart,
      durationMinutes: schedule.secondMinutes,
      location: boat.location,
      departureAddress: 'Porto di Lipari',
      departureLocation: _lipariPort,
      transportMode: TripTransportMode.bus,
    );
    final viewpoint = TripActivity(
      id: 'viewpoint',
      label: 'Quattrocchi',
      category: TripActivityCategory.visit,
      linkUrl: '',
      address: '',
      freeComments: '',
      createdBy: 'u1',
      createdAt: boat.createdAt,
      plannedAt: DateTime(2026, 5, 2, 12),
      location: _quattrocchi,
    );

    final journey = buildTripJourney([viewpoint, secondPart, firstPart]);

    expect(tripMissingTransports(journey), isEmpty);
    expect(
      [for (final leg in journey.legs) leg.transport?.id],
      ['boat', 'bus'],
    );
  });

  test('a place is named by the first part of its address', () {
    expect(
      tripTransportPlaceName('Porto di Lipari, Via Marina Corta, 98055 Lipari'),
      'Porto di Lipari',
    );
    expect(tripTransportPlaceName(' Lipari '), 'Lipari');
    expect(tripTransportPlaceName(''), '');
  });

  test('a label from one place to another is cut at the stop', () {
    final labels = tripTransportConnectionLabels(
      label: 'Milazzo → Quattrocchi',
      stopName: 'Porto di Lipari',
      arrivalName: 'Quattrocchi',
      routeLabel: _route,
    );

    expect(labels.first, 'Milazzo → Porto di Lipari');
    expect(labels.second, 'Porto di Lipari → Quattrocchi');
  });

  test('another label stays on the first part', () {
    final labels = tripTransportConnectionLabels(
      label: 'Ferry Liberty Lines',
      stopName: 'Porto di Lipari',
      arrivalName: 'Quattrocchi',
      routeLabel: _route,
    );

    expect(labels.first, 'Ferry Liberty Lines');
    expect(labels.second, 'Porto di Lipari → Quattrocchi');
  });
}
