/// Reads a GPS point from text pasted in a place search, for places no
/// geocoder knows:
/// - decimal coordinates: `37.0478, 15.0102` (French decimal commas too);
/// - degrees, minutes, seconds: `37°02'52.1"N 15°00'36.7"E`;
/// - a Google Maps, Apple Maps or OpenStreetMap link that carries them.
///
/// Null when the text holds no point. Short share links (`maps.app.goo.gl`)
/// carry no coordinates and are not read.
({double lat, double lng})? parsePastedCoordinates(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    return _fromUrl(uri);
  }
  return _fromDecimal(text) ?? _fromDms(text);
}

/// `37.04780, 15.01020`.
String formatCoordinates(double lat, double lng) =>
    '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

const _number = r'-?\d{1,3}(?:\.\d+)?';

/// Both numbers need decimals, so that a plain search ("12 34") is not
/// taken for a point.
final _decimalPair = RegExp(
  r'^\(?\s*(-?\d{1,3}[.,]\d+)\s*[,;\s]\s*\+?(-?\d{1,3}[.,]\d+)\s*\)?$',
);

final _dmsPart = RegExp(
  r'''(\d{1,3}(?:[.,]\d+)?)\s*°\s*(?:(\d{1,2}(?:[.,]\d+)?)\s*['′’]\s*)?(?:(\d{1,2}(?:[.,]\d+)?)\s*(?:"|″|”|'')\s*)?([NSEWO])''',
  caseSensitive: false,
);

({double lat, double lng})? _point(String lat, String lng) {
  final latValue = double.tryParse(lat.replaceAll(',', '.'));
  final lngValue = double.tryParse(lng.replaceAll(',', '.'));
  if (latValue == null || lngValue == null) return null;
  if (latValue.abs() > 90 || lngValue.abs() > 180) return null;
  return (lat: latValue, lng: lngValue);
}

({double lat, double lng})? _fromDecimal(String text) {
  final match = _decimalPair.firstMatch(text.trim());
  if (match == null) return null;
  return _point(match.group(1)!, match.group(2)!);
}

({double lat, double lng})? _fromDms(String text) {
  double? lat;
  double? lng;
  for (final match in _dmsPart.allMatches(text)) {
    double part(int group) =>
        double.tryParse((match.group(group) ?? '0').replaceAll(',', '.')) ??
        0;
    final value = part(1) + part(2) / 60 + part(3) / 3600;
    switch (match.group(4)!.toUpperCase()) {
      case 'N':
        lat = value;
      case 'S':
        lat = -value;
      case 'E':
        lng = value;
      default: // W, or O for "ouest".
        lng = -value;
    }
  }
  if (lat == null || lng == null) return null;
  return _point('$lat', '$lng');
}

({double lat, double lng})? _fromUrl(Uri uri) {
  final raw = Uri.decodeFull(uri.toString());

  // Google Maps place link: the place itself wins over the view (`@`).
  final place = RegExp('!3d($_number)!4d($_number)').firstMatch(raw);
  if (place != null) return _point(place.group(1)!, place.group(2)!);

  // OpenStreetMap marker.
  final markerLat = uri.queryParameters['mlat'];
  final markerLng = uri.queryParameters['mlon'];
  if (markerLat != null && markerLng != null) {
    return _point(markerLat, markerLng);
  }

  // Google Maps (`q`, `query`, `destination`...) and Apple Maps (`ll`, `q`).
  for (final key in const ['q', 'query', 'll', 'destination', 'daddr']) {
    final value = uri.queryParameters[key];
    if (value == null) continue;
    final point = _fromDecimal(value.replaceFirst('loc:', ''));
    if (point != null) return point;
  }

  // OpenStreetMap view: `#map=zoom/lat/lng`.
  final osmView = RegExp('map=[\\d.]+/($_number)/($_number)').firstMatch(raw);
  if (osmView != null) return _point(osmView.group(1)!, osmView.group(2)!);

  // Google Maps view (`/@lat,lng,17z`) or searched point (`/search/lat,lng`).
  final googleView = RegExp('@($_number),($_number)').firstMatch(raw) ??
      RegExp('/(?:search|place|dir)/($_number),\\s*\\+?($_number)')
          .firstMatch(raw);
  if (googleView != null) {
    return _point(googleView.group(1)!, googleView.group(2)!);
  }
  return null;
}
