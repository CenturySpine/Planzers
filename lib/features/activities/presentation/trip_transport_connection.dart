import 'package:latlong2/latlong.dart';
import 'package:planerz/core/presentation/osm_map.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_missing_transport.dart';

/// Whether [activity] is a transport that can be cut at a connection: a
/// planned one with its departure and arrival on the map, to work out the
/// time of each part.
bool canAddTripTransportConnection(TripActivity activity) =>
    activity.category == TripActivityCategory.transport &&
    activity.plannedAt != null &&
    activity.departureLocation != null &&
    activity.location != null;

/// When the two parts of [transport] cut at [stop] run: the first keeps its
/// start and mode, for the time it takes to reach [stop]; the second, with
/// [mode], arrives when [transport] used to, but never leaves before the
/// first one arrives. Only for [canAddTripTransportConnection].
({int firstMinutes, DateTime secondStart, int secondMinutes})
    tripTransportConnectionSchedule(
  TripActivity transport, {
  required LatLng stop,
  required TripTransportMode mode,
}) {
  const distance = Distance();
  final firstMinutes = estimateTripTravelMinutes(
    distance.as(
        LengthUnit.Meter, transport.departureLocation!.toLatLng(), stop),
    transport.transportMode ?? TripTransportMode.other,
  );
  final secondMinutes = estimateTripTravelMinutes(
    distance.as(LengthUnit.Meter, stop, transport.location!.toLatLng()),
    mode,
  );
  final firstEnd = transport.plannedAt!.add(Duration(minutes: firstMinutes));
  var secondStart =
      transport.plannedEndAt!.subtract(Duration(minutes: secondMinutes));
  if (secondStart.isBefore(firstEnd)) secondStart = firstEnd;
  return (
    firstMinutes: firstMinutes,
    secondStart: secondStart,
    secondMinutes: secondMinutes,
  );
}

/// How a place is named in a transport's label: the first part of its
/// address (`Porto di Milazzo, Via dei Mille, 98057 Milazzo` gives
/// `Porto di Milazzo`).
String tripTransportPlaceName(String address) =>
    address.split(',').first.trim();

/// The labels of the two parts of a transport labelled [label], cut at
/// [stopName]. A label written by [routeLabel] (`from → to`) becomes
/// `from → stop`, then `stop → to`; any other label stays on the first part,
/// the second going from the stop to [arrivalName].
({String first, String second}) tripTransportConnectionLabels({
  required String label,
  required String stopName,
  required String arrivalName,
  required String Function(String from, String to) routeLabel,
}) {
  final separator = routeLabel('', '');
  final cut = separator.trim().isEmpty ? -1 : label.indexOf(separator);
  if (cut < 0) {
    return (first: label, second: routeLabel(stopName, arrivalName));
  }
  return (
    first: routeLabel(label.substring(0, cut), stopName),
    second: routeLabel(stopName, label.substring(cut + separator.length)),
  );
}
