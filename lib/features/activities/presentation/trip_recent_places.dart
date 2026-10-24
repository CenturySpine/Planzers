import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';

/// A place already used by an activity of the trip, offered first when
/// choosing a place.
class TripRecentPlace {
  const TripRecentPlace({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  /// The activity's label; empty for a transport's departure or arrival.
  final String name;
  final String address;
  final double lat;
  final double lng;

  /// Whether [query] appears in the name or the address, ignoring case and
  /// accents.
  bool matches(String query) {
    final folded = _fold(query.trim());
    if (folded.isEmpty) return true;
    return _fold(name).contains(folded) || _fold(address).contains(folded);
  }
}

/// The located places of [activities], most recently created first: each
/// activity's place, and a transport's arrival then departure. The same spot
/// comes once.
List<TripRecentPlace> tripRecentPlaces(Iterable<TripActivity> activities) {
  final newestFirst = activities.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final seen = <String>{};
  final places = <TripRecentPlace>[];

  void add(String name, String address, GeoPoint? point) {
    if (point == null) return;
    final key = '${point.latitude.toStringAsFixed(5)},'
        '${point.longitude.toStringAsFixed(5)}';
    if (!seen.add(key)) return;
    places.add(
      TripRecentPlace(
        name: name.trim(),
        address: address.trim(),
        lat: point.latitude,
        lng: point.longitude,
      ),
    );
  }

  for (final activity in newestFirst) {
    if (activity.category == TripActivityCategory.transport) {
      add('', activity.address, activity.location);
      add('', activity.departureAddress, activity.departureLocation);
    } else {
      add(activity.displayLabel, activity.address, activity.location);
    }
  }
  return places;
}

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae',
  'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i',
  'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
  'ö': 'o', 'œ': 'oe', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y',
  'ÿ': 'y',
};

String _fold(String text) {
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}
