import 'package:latlong2/latlong.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_journey.dart';

/// Places further apart than this, with no transport planned between them,
/// are offered a transport to fill in; closer ones are a walk not worth
/// noting.
const double tripMissingTransportMinMeters = 1000;

/// A move between two planned places with no transport planned for it.
/// Never stored: worked out from the journey each time it is shown.
class TripMissingTransport {
  const TripMissingTransport({
    required this.from,
    required this.to,
    required this.fromPoint,
    required this.toPoint,
    required this.distanceMeters,
  });

  /// The place left: an activity, or a transport (its arrival).
  final TripActivity from;

  /// The place reached: an activity, or a transport (its departure).
  final TripActivity to;
  final LatLng fromPoint;
  final LatLng toPoint;

  /// As the crow flies.
  final double distanceMeters;

  bool _isTransport(TripActivity activity) =>
      activity.category == TripActivityCategory.transport;

  String get fromAddress => _isTransport(from)
      ? from.address.trim()
      : _addressOrLabel(from.address, from.label);

  String get toAddress => _isTransport(to)
      ? to.departureAddress.trim()
      : _addressOrLabel(to.address, to.label);

  /// How the place left is named: the activity's label, or the address of a
  /// transport's arrival.
  String get fromName => _isTransport(from)
      ? _addressOrLabel(from.address, from.label)
      : from.label.trim();

  String get toName => _isTransport(to)
      ? _addressOrLabel(to.departureAddress, to.label)
      : to.label.trim();

  /// When to leave and for how long with [mode]: arriving as [to] starts,
  /// but never leaving before [from] ends.
  ({DateTime start, int minutes}) schedule(TripTransportMode mode) {
    final minutes = estimateTripTravelMinutes(distanceMeters, mode);
    var start = to.plannedAt!.subtract(Duration(minutes: minutes));
    final leftAt = from.plannedEndAt;
    if (leftAt != null && start.isBefore(leftAt)) start = leftAt;
    return (start: start, minutes: minutes);
  }

  static String _addressOrLabel(String address, String label) =>
      address.trim().isNotEmpty ? address.trim() : label.trim();
}

/// The plain links of [journey] long enough to call for a transport.
List<TripMissingTransport> tripMissingTransports(TripJourney journey) {
  const distance = Distance();
  return [
    for (final leg in journey.legs)
      if (leg.transport == null &&
          leg.fromActivity != null &&
          leg.toActivity != null)
        TripMissingTransport(
          from: leg.fromActivity!,
          to: leg.toActivity!,
          fromPoint: leg.from,
          toPoint: leg.to,
          distanceMeters: distance.as(LengthUnit.Meter, leg.from, leg.to),
        ),
  ].where((m) => m.distanceMeters > tripMissingTransportMinMeters).toList();
}

/// A rough travel time, in minutes rounded up to 5, from the distance as
/// the crow flies: an average speed per mode, a detour for roads and paths,
/// and the airport time for a flight. Only a starting point to adjust.
int estimateTripTravelMinutes(double distanceMeters, TripTransportMode mode) {
  final (speedKmh, detour, extraMinutes) = switch (mode) {
    TripTransportMode.walk => (4.5, 1.2, 0),
    TripTransportMode.bike => (15.0, 1.2, 0),
    TripTransportMode.car => (50.0, 1.3, 0),
    TripTransportMode.bus => (30.0, 1.3, 0),
    TripTransportMode.train => (70.0, 1.2, 0),
    TripTransportMode.plane => (700.0, 1.0, 90),
    TripTransportMode.boat => (25.0, 1.1, 0),
    TripTransportMode.other => (40.0, 1.3, 0),
  };
  final minutes = distanceMeters / 1000 * detour / speedKmh * 60 + extraMinutes;
  final rounded = (minutes / 5).ceil() * 5;
  return rounded.clamp(5, tripActivityMaxDurationMinutes);
}
