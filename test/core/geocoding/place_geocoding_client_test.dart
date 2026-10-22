import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:planerz/core/geocoding/place_geocoding_client.dart';

Map<String, Object?> _feature(
  Map<String, Object?> properties,
  double lng,
  double lat,
) =>
    {
      'type': 'Feature',
      'properties': properties,
      'geometry': {
        'type': 'Point',
        'coordinates': [lng, lat],
      },
    };

http.Response _json(List<Map<String, Object?>> features) => http.Response.bytes(
      utf8.encode(
        jsonEncode({'type': 'FeatureCollection', 'features': features}),
      ),
      200,
    );

void main() {
  test('search: named places with their address, near the given point',
      () async {
    late Uri asked;
    final client = PlaceGeocodingClient(
      httpClient: MockClient((request) async {
        asked = request.url;
        return _json([
          _feature(
            {
              'name': 'Refuge du Goûter',
              'city': 'Saint-Gervais-les-Bains',
              'postcode': '74170',
            },
            6.8546,
            45.8506,
          ),
          _feature({'osm_key': 'place'}, 2, 46),
        ]);
      }),
    );

    final places = await client.search(
      'refuge gouter',
      languageCode: 'fr',
      nearLat: 45.9,
      nearLng: 6.8,
    );

    expect(asked.host, 'photon.komoot.io');
    expect(asked.path, '/api/');
    expect(asked.queryParameters['lang'], 'fr');
    expect(asked.queryParameters['lat'], '45.9');
    expect(places, hasLength(1));
    expect(
      places.single.address,
      'Refuge du Goûter, 74170 Saint-Gervais-les-Bains',
    );
    expect((places.single.lat, places.single.lng), (45.8506, 6.8546));
  });

  test('search: a place known only by its name and country', () async {
    final client = PlaceGeocodingClient(
      httpClient: MockClient(
        (request) async => _json([
          _feature({'name': 'Laguna Verde', 'country': 'Bolivia'}, -67.8, -22.8),
        ]),
      ),
    );

    final places = await client.search('laguna verde', languageCode: 'en');

    expect(places.single.address, 'Laguna Verde, Bolivia');
  });

  test('search: nothing asked under three letters', () async {
    var called = false;
    final client = PlaceGeocodingClient(
      httpClient: MockClient((request) async {
        called = true;
        return _json(const []);
      }),
    );
    expect(await client.search('pa', languageCode: 'en'), isEmpty);
    expect(called, isFalse);
  });

  test('reverse: the address found, at the point placed', () async {
    late Uri asked;
    final client = PlaceGeocodingClient(
      httpClient: MockClient((request) async {
        asked = request.url;
        return _json([
          _feature(
            {
              'housenumber': '33',
              'street': 'Avenue Jean Capelle',
              'city': 'Villeurbanne',
              'postcode': '69100',
            },
            4.8766,
            45.7826,
          ),
        ]);
      }),
    );

    final place = await client.reverse(
      lat: 45.7825,
      lng: 4.8765,
      languageCode: 'de',
    );

    expect(asked.path, '/reverse');
    expect(asked.queryParameters.containsKey('lang'), isFalse);
    expect(place?.address, '33 Avenue Jean Capelle, 69100 Villeurbanne');
    expect((place?.lat, place?.lng), (45.7825, 4.8765));
  });

  test('every failure reads as nothing found', () async {
    final client = PlaceGeocodingClient(
      httpClient: MockClient((request) async => http.Response('oops', 500)),
    );
    expect(await client.search('parc', languageCode: 'fr'), isEmpty);
    expect(await client.reverse(lat: 1, lng: 2, languageCode: 'fr'), isNull);
  });
}
