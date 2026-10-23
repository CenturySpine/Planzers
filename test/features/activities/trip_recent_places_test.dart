import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_recent_places.dart';

TripActivity _activity(
  String label,
  DateTime createdAt, {
  TripActivityCategory category = TripActivityCategory.visit,
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
    createdAt: createdAt,
    location: location,
    departureAddress: departureAddress,
    departureLocation: departureLocation,
  );
}

void main() {
  test('newest first, each spot once, transports give both ends', () {
    final places = tripRecentPlaces([
      _activity(
        'Borgo degli Ulivi',
        DateTime(2026, 5, 1),
        address: 'Contrada Bibbia, Palazzolo Acreide',
        location: const GeoPoint(37.048, 14.951),
      ),
      _activity(
        'Train',
        DateTime(2026, 5, 3),
        category: TripActivityCategory.transport,
        address: 'Gare de Catane',
        location: const GeoPoint(37.506, 15.098),
        departureAddress: 'Gare de Noto',
        departureLocation: const GeoPoint(36.884, 15.072),
      ),
      _activity(
        'Borgo degli Ulivi, 2e nuit',
        DateTime(2026, 5, 2),
        location: const GeoPoint(37.048, 14.951),
      ),
      _activity('Sans lieu', DateTime(2026, 5, 4), address: 'Quelque part'),
    ]);

    expect(
      places.map((p) => (p.name, p.address)),
      [
        ('', 'Gare de Catane'),
        ('', 'Gare de Noto'),
        ('Borgo degli Ulivi, 2e nuit', ''),
      ],
    );
  });

  test('a search matches the name or the address, without accents', () {
    const place = TripRecentPlace(
      name: 'Musée Paolo Orsi',
      address: 'Viale Teocrito, Siracusa',
      lat: 37.08,
      lng: 15.28,
    );
    expect(place.matches('musee'), isTrue);
    expect(place.matches('SIRACUSA'), isTrue);
    expect(place.matches('  '), isTrue);
    expect(place.matches('catane'), isFalse);
  });
}
