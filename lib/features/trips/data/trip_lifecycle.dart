import 'package:planerz/features/trips/data/trip.dart';

/// Must match functions/trip_lifecycle.js (daily server job).
const int tripAutoArchiveAfterDays = 30;
const int tripDocumentsRetentionDays = 60;

/// Whole calendar days since the trip's last day (end date, else start
/// date); null when the trip has no date or is not over yet (a trip is
/// "past" from the day after its last day, as in the trips list).
int? daysSinceTripEnded(Trip trip, DateTime now) {
  final lastDay = trip.endDate ?? trip.startDate;
  if (lastDay == null) return null;
  final days = DateTime.utc(now.year, now.month, now.day)
      .difference(DateTime.utc(lastDay.year, lastDay.month, lastDay.day))
      .inDays;
  return days >= 1 ? days : null;
}

/// Days left before the trip is archived automatically; null when not
/// applicable (not over yet, or no date).
int? daysUntilTripAutoArchive(Trip trip, DateTime now) {
  final since = daysSinceTripEnded(trip, now);
  if (since == null) return null;
  final left = tripAutoArchiveAfterDays - since;
  return left < 0 ? 0 : left;
}

/// Days left before the traveler's personal documents are deleted
/// automatically; null when not applicable.
int? daysUntilTripDocumentsDeletion(Trip trip, DateTime now) {
  final since = daysSinceTripEnded(trip, now);
  if (since == null) return null;
  final left = tripDocumentsRetentionDays - since;
  return left < 0 ? 0 : left;
}
