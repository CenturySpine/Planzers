import 'dart:ui' show Locale;

import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_category_presentation.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/trips/data/trip.dart';

/// Single row in a trip activities list: either an activity or a day separator label.
class TripActivitiesListEntry {
  const TripActivitiesListEntry.activity(this.activity)
      : daySeparatorLabel = null;

  const TripActivitiesListEntry.daySeparator(this.daySeparatorLabel)
      : activity = null;

  final TripActivity? activity;
  final String? daySeparatorLabel;
}

String creatorLabelForActivity(
  TripActivity activity,
  Map<String, String> tripMemberPublicLabels, {
  required Map<String, Map<String, dynamic>> usersDataById,
  String? currentUserId,
  required String unknownLabel,
}) {
  final id = activity.createdBy.trim();
  if (id.isEmpty) return unknownLabel;
  return resolveTripMemberDisplayLabel(
    memberId: id,
    userData: usersDataById[id],
    tripMemberPublicLabels: tripMemberPublicLabels,
    currentUserId: currentUserId,
    emptyFallback: unknownLabel,
  );
}

DateTime tripActivityDateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool tripActivitiesSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

DateTime tripActivityDateForGrouping(TripActivity activity) {
  return activity.plannedAt ?? activity.doneAt ?? activity.createdAt;
}

int tripActivityPlannedMinutesSinceMidnight(TripActivity activity) {
  final plannedAt = activity.plannedAt;
  if (plannedAt == null) return -1;
  final local = plannedAt.toLocal();
  return local.hour * 60 + local.minute;
}

Set<DateTime> tripActivitiesPlannedDaysSet(List<TripActivity> items) {
  return items
      .where((activity) => activity.plannedAt != null)
      .map((activity) => tripActivityDateOnly(activity.plannedAt!))
      .toSet();
}

List<TripActivity> tripActivitiesAgendaItemsForDay(
  List<TripActivity> items, {
  required DateTime selectedDay,
}) {
  final filtered = items
      .where((activity) => activity.plannedAt != null)
      .where(
        (activity) =>
            tripActivitiesSameDay(tripActivityDateOnly(activity.plannedAt!), selectedDay),
      )
      .toList()
    ..sort((a, b) {
      final byPlanned = tripActivityPlannedMinutesSinceMidnight(a).compareTo(
        tripActivityPlannedMinutesSinceMidnight(b),
      );
      if (byPlanned != 0) return byPlanned;
      return b.createdAt.compareTo(a.createdAt);
    });
  return filtered;
}

bool tripActivityMatchesQuery(
  TripActivity activity,
  String rawQuery, {
  required String creatorLabel,
}) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return true;
  final previewValues = activity.linkPreview.values
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty);
  final haystack = <String>[
    activity.id,
    activity.label,
    activity.category.categoryLabelFr,
    activity.linkUrl,
    activity.address,
    activity.freeComments,
    activity.createdBy,
    creatorLabel,
    ...previewValues,
  ].join(' ').toLowerCase();
  return haystack.contains(query);
}

/// Suggestions: unplanned activities, optionally filtered by [categoryFilter].
List<TripActivitiesListEntry> buildTripActivitiesSuggestionEntries(
  List<TripActivity> items, {
  required String query,
  required String Function(TripActivity activity) creatorLabelFor,
  List<TripActivityCategory>? categoryFilter,
}) {
  final suggestions = items
      .where((a) => a.plannedAt == null)
      .where(
        (a) =>
            categoryFilter == null || categoryFilter.isEmpty || categoryFilter.contains(a.category),
      )
      .where(
        (a) => tripActivityMatchesQuery(
          a,
          query,
          creatorLabel: creatorLabelFor(a),
        ),
      )
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return suggestions.map(TripActivitiesListEntry.activity).toList();
}

List<TripActivitiesListEntry> buildTripActivitiesPlannedEntries(
  List<TripActivity> items, {
  required String query,
  required String Function(TripActivity activity) creatorLabelFor,
  required String Function(DateTime day) dayLabelFor,
}) {
  final dated = items
      .where((a) => a.plannedAt != null)
      .where(
        (a) => tripActivityMatchesQuery(
          a,
          query,
          creatorLabel: creatorLabelFor(a),
        ),
      )
      .toList()
    ..sort((a, b) {
      final aDate = tripActivityDateForGrouping(a);
      final bDate = tripActivityDateForGrouping(b);
      final byDay = bDate.compareTo(aDate);
      if (byDay != 0) return byDay;
      final byTime = tripActivityPlannedMinutesSinceMidnight(a).compareTo(
        tripActivityPlannedMinutesSinceMidnight(b),
      );
      if (byTime != 0) return byTime;
      return b.createdAt.compareTo(a.createdAt);
    });

  final entries = <TripActivitiesListEntry>[];

  DateTime? previousDay;
  for (final activity in dated) {
    final date = tripActivityDateForGrouping(activity).toLocal();
    final day = DateTime(date.year, date.month, date.day);
    if (previousDay == null || previousDay != day) {
      entries.add(TripActivitiesListEntry.daySeparator(dayLabelFor(day)));
      previousDay = day;
    }
    entries.add(TripActivitiesListEntry.activity(activity));
  }
  return entries;
}

DateTime defaultAgendaDayForTrip(Trip trip) {
  final today = tripActivityDateOnly(DateTime.now());
  final start =
      trip.startDate == null ? null : tripActivityDateOnly(trip.startDate!);
  final end = trip.endDate == null ? null : tripActivityDateOnly(trip.endDate!);

  if (start != null && today.isBefore(start)) {
    return start;
  }
  if (end != null && today.isAfter(end)) {
    return end;
  }
  return today;
}

DateTime startOfAtomicWeekForLocale(DateTime day, Locale locale) {
  final date = tripActivityDateOnly(day);
  final firstWeekday = firstWeekdayForLocale(locale);
  final delta = (date.weekday - firstWeekday + DateTime.daysPerWeek) %
      DateTime.daysPerWeek;
  return date.subtract(Duration(days: delta));
}

int firstWeekdayForLocale(Locale locale) {
  final countryCode = (locale.countryCode ?? '').toUpperCase();
  return countryCode == 'US' ? DateTime.sunday : DateTime.monday;
}
