import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// A place found by [PlaceGeocodingClient]: the address shown and stored,
/// and its point. [address] is empty when no address is known for the point.
class GeocodedPlace {
  const GeocodedPlace({
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String address;
  final double lat;
  final double lng;
}

/// Photon (komoot): OpenStreetMap geocoding, free, no API key, open CORS,
/// and -- unlike Nominatim -- fine with a search as one types. Works both
/// ways: a place searched becomes a point, a point placed on a map becomes
/// an address. Every failure (timeout, network, unexpected shape) collapses
/// to "nothing found".
class PlaceGeocodingClient {
  PlaceGeocodingClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const _host = 'photon.komoot.io';

  /// Up to [limit] places matching [query], the ones near [nearLat]/[nearLng]
  /// first when given.
  Future<List<GeocodedPlace>> search(
    String query, {
    required String languageCode,
    double? nearLat,
    double? nearLng,
    int limit = 6,
  }) async {
    final text = query.trim();
    if (text.length < 3) return const [];
    final features = await _get('/api/', {
      'q': text,
      'limit': '$limit',
      ..._language(languageCode),
      if (nearLat != null && nearLng != null) ...{
        'lat': '$nearLat',
        'lon': '$nearLng',
      },
    });
    return features
        .map((feature) => _place(feature, withName: true))
        .whereType<GeocodedPlace>()
        .toList(growable: false);
  }

  /// The address nearest to a point, or null. The point stays the one
  /// placed, not the address's.
  Future<GeocodedPlace?> reverse({
    required double lat,
    required double lng,
    required String languageCode,
  }) async {
    final features = await _get('/reverse', {
      'lat': '$lat',
      'lon': '$lng',
      ..._language(languageCode),
    });
    if (features.isEmpty) return null;
    final place = _place(features.first, withName: true);
    if (place == null) return null;
    return GeocodedPlace(address: place.address, lat: lat, lng: lng);
  }

  /// Photon speaks French and English, the app's two languages.
  Map<String, String> _language(String code) =>
      code == 'fr' || code == 'en' ? {'lang': code} : const {};

  Future<List<Map<String, Object?>>> _get(
    String path,
    Map<String, String> query,
  ) async {
    try {
      final response = await _httpClient
          .get(Uri.https(_host, path, query))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return const [];
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      final features = json['features'];
      if (features is! List) return const [];
      return features.whereType<Map<String, Object?>>().toList();
    } catch (_) {
      return const [];
    }
  }

  GeocodedPlace? _place(
    Map<String, Object?> feature, {
    required bool withName,
  }) {
    final properties = feature['properties'];
    final geometry = feature['geometry'];
    if (properties is! Map || geometry is! Map) return null;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;
    final lng = (coordinates[0] as num?)?.toDouble();
    final lat = (coordinates[1] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    String? text(String key) {
      final value = (properties[key] as String?)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final name = text('name');
    final street = text('street');
    final number = text('housenumber');
    final city = text('city') ?? text('locality') ?? text('county');
    final postcode = text('postcode');
    final country = text('country');
    final parts = [
      if (name != null && (withName || street == null) && name != street) name,
      if (street != null) number == null ? street : '$number $street',
      if (postcode != null || city != null)
        [postcode, city].whereType<String>().join(' '),
      if (street == null && city == null && country != null && country != name)
        country,
    ];
    if (parts.isEmpty) return null;
    return GeocodedPlace(address: parts.join(', '), lat: lat, lng: lng);
  }
}

final placeGeocodingClientProvider = Provider<PlaceGeocodingClient>(
  (ref) => PlaceGeocodingClient(),
);
