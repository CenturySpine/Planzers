import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_place_field.dart';
import 'package:planerz/features/activities/presentation/trip_transport_mode_presentation.dart';

TripActivity _activity({
  String id = 'a',
  TripActivityCategory category = TripActivityCategory.visit,
  GeoPoint? location,
  GeoPoint? departureLocation,
  TripTransportMode? transportMode,
}) {
  return TripActivity(
    id: id,
    label: 'Activité',
    category: category,
    linkUrl: '',
    address: '',
    freeComments: '',
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
    location: location,
    departureLocation: departureLocation,
    transportMode: transportMode,
  );
}

void main() {
  test('transport modes round-trip through Firestore values', () {
    for (final mode in TripTransportMode.values) {
      expect(TripTransportMode.fromFirestore(mode.firestoreValue), mode);
    }
    expect(TripTransportMode.fromFirestore('rocket'), isNull);
    expect(TripTransportMode.fromFirestore(null), isNull);
  });

  test('a transport shows its mode icon, else its category icon', () {
    expect(
      _activity(
        category: TripActivityCategory.transport,
        transportMode: TripTransportMode.train,
      ).displayIcon,
      PhosphorIconsRegular.train,
    );
    expect(
      _activity(category: TripActivityCategory.transport).displayIcon,
      PhosphorIconsRegular.bus,
    );
  });

  test('map points: the place, or a transport from departure to arrival', () {
    expect(tripActivityMapPoints(_activity()), isEmpty);
    expect(
      tripActivityMapPoints(_activity(location: const GeoPoint(45, 6))),
      [const LatLng(45, 6)],
    );
    expect(
      tripActivityMapPoints(
        _activity(
          category: TripActivityCategory.transport,
          departureLocation: const GeoPoint(48.8, 2.3),
          location: const GeoPoint(43.3, 5.4),
        ),
      ),
      [const LatLng(48.8, 2.3), const LatLng(43.3, 5.4)],
    );
  });

  test('the picker opens on the latest located activity', () {
    final center = tripActivitiesFallbackCenter([
      _activity(id: 'newest'),
      _activity(
        id: 'transport',
        category: TripActivityCategory.transport,
        departureLocation: const GeoPoint(48.8, 2.3),
      ),
      _activity(id: 'oldest', location: const GeoPoint(45, 6)),
    ]);
    expect(center, const GeoPoint(48.8, 2.3));
    expect(tripActivitiesFallbackCenter(const []), isNull);
  });
}
