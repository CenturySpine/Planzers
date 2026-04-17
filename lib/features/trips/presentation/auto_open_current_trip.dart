import 'package:planzers/features/trips/data/trip.dart';

Trip? resolveTripToAutoOpen({
  required List<Trip> trips,
  required bool isPreferenceEnabled,
  DateTime? now,
}) {
  if (!isPreferenceEnabled) return null;

  final today = _dateOnly(now ?? DateTime.now());
  final ongoingTrips = trips.where((trip) => _isOngoingOnDay(trip, today)).toList();

  if (ongoingTrips.length != 1) return null;
  return ongoingTrips.single;
}

bool _isOngoingOnDay(Trip trip, DateTime day) {
  final startDate = trip.startDate;
  final endDate = trip.endDate;
  if (startDate == null || endDate == null) {
    return false;
  }

  var start = _dateOnly(startDate);
  var end = _dateOnly(endDate);
  if (start.isAfter(end)) {
    final tmp = start;
    start = end;
    end = tmp;
  }

  return !day.isBefore(start) && !day.isAfter(end);
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
