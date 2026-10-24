import 'package:latlong2/latlong.dart';
import 'package:planerz/core/presentation/osm_map.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/features/activities/presentation/trip_activity_place_field.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';

/// A located planned activity of the journey, numbered in time order.
class TripJourneyStop {
  const TripJourneyStop({
    required this.number,
    required this.activity,
    required this.point,
  });

  final int number;
  final TripActivity activity;
  final LatLng point;
}

/// A line of the journey: a transport, from its departure to its arrival,
/// or a plain link between two places with no transport planned between
/// them.
class TripJourneyLeg {
  const TripJourneyLeg({
    required this.from,
    required this.to,
    this.transport,
    this.fromActivity,
    this.toActivity,
  });

  final LatLng from;
  final LatLng to;

  /// Null for a plain link.
  final TripActivity? transport;

  /// Plain link only: the activity left (a place, or a transport's
  /// arrival) and the one reached (a place, or a transport's departure).
  final TripActivity? fromActivity;
  final TripActivity? toActivity;
}

/// Stops sharing a place (e.g. the same hotel several nights), shown as one
/// marker.
class TripJourneyPlace {
  const TripJourneyPlace({required this.point, required this.stops});

  final LatLng point;
  final List<TripJourneyStop> stops;

  /// `1`, `1·4`, `1·4·7`, then `1·4 +2` past three stops.
  String get numbersLabel {
    final numbers = [for (final stop in stops) '${stop.number}'];
    if (numbers.length <= 3) return numbers.join('·');
    return '${numbers.take(2).join('·')} +${numbers.length - 2}';
  }
}

class TripJourney {
  const TripJourney({required this.stops, required this.legs});

  final List<TripJourneyStop> stops;
  final List<TripJourneyLeg> legs;

  bool get isEmpty => stops.isEmpty && legs.isEmpty;

  /// [stops] grouped by place, in order of first visit.
  List<TripJourneyPlace> get places {
    final byPoint = <LatLng, List<TripJourneyStop>>{};
    for (final stop in stops) {
      byPoint.putIfAbsent(stop.point, () => []).add(stop);
    }
    return [
      for (final entry in byPoint.entries)
        TripJourneyPlace(point: entry.key, stops: entry.value),
    ];
  }

  /// Every point shown, to frame the map.
  List<LatLng> get points => [
        for (final stop in stops) stop.point,
        for (final leg in legs) ...[leg.from, leg.to],
      ];
}

/// A meal at the restaurant standing in the journey as a planned stop: its
/// restaurant, at the meal's time.
class TripJourneyMealStop {
  const TripJourneyMealStop({required this.meal, required this.activity});

  final TripMeal meal;

  /// The meal's restaurant at the meal's time, under
  /// [tripJourneyMealStopId].
  final TripActivity activity;
}

/// Id of a meal's stop in the journey, never the id of an activity.
String tripJourneyMealStopId(String mealId) => 'meal:$mealId';

/// The [meals] at the restaurant whose restaurant, among [activities], has a
/// place.
List<TripJourneyMealStop> tripJourneyMealStops(
  Iterable<TripMeal> meals,
  Iterable<TripActivity> activities,
) {
  final activitiesById = {for (final a in activities) a.id: a};
  return [
    for (final meal in meals)
      if (meal.mealMode == MealMode.restaurant)
        if (activitiesById[meal.restaurantActivityId.trim()]
            case final restaurant? when restaurant.location != null)
          TripJourneyMealStop(
            meal: meal,
            activity: TripActivity(
              id: tripJourneyMealStopId(meal.id),
              label: restaurant.displayLabel,
              category: TripActivityCategory.restaurant,
              linkUrl: restaurant.linkUrl,
              address: restaurant.address,
              freeComments: '',
              createdBy: restaurant.createdBy,
              createdAt: meal.createdAt,
              plannedAt: DateTime(
                meal.mealDateAsDateTime.year,
                meal.mealDateAsDateTime.month,
                meal.mealDateAsDateTime.day,
                0,
                tripMealPlannedMinutesSinceMidnight(meal),
              ),
              durationMinutes: restaurant.durationMinutes,
              linkPreview: restaurant.linkPreview,
              location: restaurant.location,
            ),
          ),
  ];
}

/// Planned activities of the trip map, in time order, on [day] only when
/// given. Restaurants are left out, as in the agenda: the [mealStops]
/// going there stand for them.
List<TripActivity> tripJourneyActivities(
  Iterable<TripActivity> activities, {
  Iterable<TripJourneyMealStop> mealStops = const [],
  DateTime? day,
}) {
  return [
    ...activities.where(
      (activity) =>
          activity.plannedAt != null &&
          activity.category != TripActivityCategory.restaurant,
    ),
    for (final stop in mealStops) stop.activity,
  ]
      .where(
        (activity) =>
            day == null || tripActivityDateOnly(activity.plannedAt!) == day,
      )
      .toList()
    ..sort((a, b) => a.plannedAt!.compareTo(b.plannedAt!));
}

/// The days with something to show on the map, in order.
List<DateTime> tripJourneyDays(
  Iterable<TripActivity> activities, {
  Iterable<TripJourneyMealStop> mealStops = const [],
}) {
  return {
    for (final activity
        in tripJourneyActivities(activities, mealStops: mealStops))
      if (tripActivityMapPoints(activity).isNotEmpty)
        tripActivityDateOnly(activity.plannedAt!),
  }.toList()
    ..sort();
}

/// The journey drawn on the trip map: numbered stops, transports, and plain
/// links keeping the line continuous between places. A transport missing its
/// departure or arrival starts from the place before it or ends at the next
/// one.
TripJourney buildTripJourney(
  Iterable<TripActivity> activities, {
  Iterable<TripJourneyMealStop> mealStops = const [],
  DateTime? day,
}) {
  final ordered =
      tripJourneyActivities(activities, mealStops: mealStops, day: day);
  final stops = <TripJourneyStop>[];
  final legs = <TripJourneyLeg>[];
  LatLng? last;
  TripActivity? lastActivity;

  for (var i = 0; i < ordered.length; i++) {
    final activity = ordered[i];
    if (activity.category == TripActivityCategory.transport) {
      final from = activity.departureLocation?.toLatLng() ?? last;
      final to = activity.location?.toLatLng() ?? _nextPlace(ordered, i + 1);
      if (from != null && to != null) {
        if (last != null && last != from) {
          legs.add(
            TripJourneyLeg(
              from: last,
              to: from,
              fromActivity: lastActivity,
              toActivity: activity,
            ),
          );
        }
        legs.add(TripJourneyLeg(from: from, to: to, transport: activity));
      }
      // Without an arrival nor a place after it, nothing follows anyway.
      if (to != null) {
        last = to;
        lastActivity = activity;
      }
      continue;
    }

    final point = activity.location?.toLatLng();
    if (point == null) continue;
    if (last != null && last != point) {
      legs.add(
        TripJourneyLeg(
          from: last,
          to: point,
          fromActivity: lastActivity,
          toActivity: activity,
        ),
      );
    }
    lastActivity = activity;
    stops.add(
      TripJourneyStop(
        number: stops.length + 1,
        activity: activity,
        point: point,
      ),
    );
    last = point;
  }
  return TripJourney(stops: stops, legs: legs);
}

/// Where the journey goes next from [start]: the next place, or the next
/// transport's departure.
LatLng? _nextPlace(List<TripActivity> ordered, int start) {
  for (var i = start; i < ordered.length; i++) {
    final activity = ordered[i];
    final point = activity.category == TripActivityCategory.transport
        ? activity.departureLocation
        : activity.location;
    if (point != null) return point.toLatLng();
  }
  return null;
}
