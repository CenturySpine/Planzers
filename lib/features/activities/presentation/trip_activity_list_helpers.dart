import 'dart:ui' show Locale;

import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_category_presentation.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/data/trip.dart';

/// Single row in a trip activities list: either an activity or a day separator label.
class TripActivitiesListEntry {
  const TripActivitiesListEntry.activity(this.activity)
      : meal = null,
        adapterCategory = null,
        daySeparatorLabel = null;

  const TripActivitiesListEntry.meal(this.meal)
      : activity = null,
        adapterCategory = TripActivitiesAdapterCategory.repas,
        daySeparatorLabel = null;

  const TripActivitiesListEntry.daySeparator(this.daySeparatorLabel)
      : activity = null,
        meal = null,
        adapterCategory = null;

  final TripActivity? activity;
  final TripMeal? meal;
  final TripActivitiesAdapterCategory? adapterCategory;
  final String? daySeparatorLabel;
}

enum TripActivitiesAdapterCategory { repas }

String creatorLabelForActivity(
  TripActivity activity,
  Map<String, String> memberLabels, {
  required String unknownLabel,
}) {
  final id = activity.createdBy.trim();
  if (id.isEmpty) return unknownLabel;
  return memberLabels[id] ?? unknownLabel;
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

int tripMealPlannedMinutesSinceMidnight(TripMeal meal) {
  final parsedTime = _parseMealTime(meal.mealTimeHHMM);
  if (parsedTime != null) {
    return parsedTime;
  }
  final fallbackTime = _parseMealTime(
    TripMeal.defaultTimeHHMMForDayPart(meal.mealDayPart),
  );
  if (fallbackTime != null) {
    return fallbackTime;
  }
  return tripDayPartSortIndex(meal.mealDayPart) * 60;
}

int? _parseMealTime(String value) {
  final parts = value.trim().split(':');
  if (parts.length != 2) return null;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  if (hours == null || minutes == null) return null;
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
  return (hours * 60) + minutes;
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
      .where((a) => a.category != TripActivityCategory.restaurant)
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
      final byDay = aDate.compareTo(bDate);
      if (byDay != 0) return byDay;
      final byTime = tripActivityPlannedMinutesSinceMidnight(a).compareTo(
        tripActivityPlannedMinutesSinceMidnight(b),
      );
      if (byTime != 0) return byTime;
      return a.createdAt.compareTo(b.createdAt);
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

bool tripMealMatchesQuery(TripMeal meal, String rawQuery) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return true;
  final componentTitles = meal.components
      .map((component) => component.title.trim())
      .where((title) => title.isNotEmpty);
  final haystack = <String>[
    meal.id,
    meal.mealDateKey,
    meal.mealTimeHHMM,
    meal.mealDayPart.name,
    meal.mealMode.name,
    meal.restaurantName,
    meal.createdBy,
    ...meal.participantIds,
    ...componentTitles,
  ].join(' ').toLowerCase();
  return haystack.contains(query);
}

List<TripActivitiesListEntry> buildTripActivitiesPlannedEntriesMixed({
  required List<TripActivity> activities,
  required List<TripMeal> meals,
  required String query,
  required String Function(TripActivity activity) creatorLabelForActivity,
  required String Function(DateTime day) dayLabelFor,
}) {
  final plannedActivities = activities
      .where((activity) => activity.plannedAt != null)
      .where((activity) => activity.category != TripActivityCategory.restaurant)
      .where(
        (activity) => tripActivityMatchesQuery(
          activity,
          query,
          creatorLabel: creatorLabelForActivity(activity),
        ),
      )
      .toList(growable: false);
  final plannedMeals = meals
      .where((meal) => tripMealMatchesQuery(meal, query))
      .toList(growable: false);

  final combined = <_PlannedTimelineItem>[
    ...plannedActivities.map(_PlannedTimelineItem.fromActivity),
    ...plannedMeals.map(_PlannedTimelineItem.fromMeal),
  ]..sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      if (byDay != 0) return byDay;
      final byTime = a.minutesSinceMidnight.compareTo(b.minutesSinceMidnight);
      if (byTime != 0) return byTime;
      return a.createdAt.compareTo(b.createdAt);
    });

  final entries = <TripActivitiesListEntry>[];
  DateTime? previousDay;
  for (final item in combined) {
    if (previousDay == null || previousDay != item.day) {
      entries.add(TripActivitiesListEntry.daySeparator(dayLabelFor(item.day)));
      previousDay = item.day;
    }
    entries.add(item.asEntry);
  }
  return entries;
}

List<TripActivitiesListEntry> tripActivitiesAgendaEntriesForDayMixed({
  required List<TripActivity> activities,
  required List<TripMeal> meals,
  required DateTime selectedDay,
}) {
  final dayActivities = activities
      .where((activity) => activity.plannedAt != null)
      .where((activity) => activity.category != TripActivityCategory.restaurant)
      .where(
        (activity) => tripActivitiesSameDay(
          tripActivityDateOnly(activity.plannedAt!),
          selectedDay,
        ),
      )
      .map(_PlannedTimelineItem.fromActivity);
  final dayMeals = meals
      .where((meal) => tripActivitiesSameDay(meal.mealDateAsDateTime, selectedDay))
      .map(_PlannedTimelineItem.fromMeal);

  final combined = <_PlannedTimelineItem>[
    ...dayActivities,
    ...dayMeals,
  ]..sort((a, b) {
      final byTime = a.minutesSinceMidnight.compareTo(b.minutesSinceMidnight);
      if (byTime != 0) return byTime;
      return b.createdAt.compareTo(a.createdAt);
    });

  return combined.map((item) => item.asEntry).toList(growable: false);
}

Set<DateTime> tripActivitiesPlannedDaysSetMixed({
  required List<TripActivity> activities,
  required List<TripMeal> meals,
}) {
  return <DateTime>{
    ...activities
        .where((activity) => activity.plannedAt != null)
        .map((activity) => tripActivityDateOnly(activity.plannedAt!)),
    ...meals.map((meal) => meal.mealDateAsDateTime),
  };
}

class _PlannedTimelineItem {
  const _PlannedTimelineItem({
    required this.day,
    required this.minutesSinceMidnight,
    required this.createdAt,
    required this.asEntry,
  });

  factory _PlannedTimelineItem.fromActivity(TripActivity activity) {
    final plannedAt = activity.plannedAt!;
    final day = tripActivityDateOnly(plannedAt);
    return _PlannedTimelineItem(
      day: day,
      minutesSinceMidnight: tripActivityPlannedMinutesSinceMidnight(activity),
      createdAt: activity.createdAt,
      asEntry: TripActivitiesListEntry.activity(activity),
    );
  }

  factory _PlannedTimelineItem.fromMeal(TripMeal meal) {
    final day = meal.mealDateAsDateTime;
    return _PlannedTimelineItem(
      day: day,
      minutesSinceMidnight: tripMealPlannedMinutesSinceMidnight(meal),
      createdAt: meal.createdAt,
      asEntry: TripActivitiesListEntry.meal(meal),
    );
  }

  final DateTime day;
  final int minutesSinceMidnight;
  final DateTime createdAt;
  final TripActivitiesListEntry asEntry;
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
