import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_lodging.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';

/// Id of the lodging standing for a trip's former single link and address.
const String tripLegacyLodgingId = 'legacy';

/// Prefix of the ids of lodgings not stored yet.
const String tripNewLodgingIdPrefix = 'new-';

/// Evenings of the nights from [start] to [end] (calendar days), first to
/// last.
List<DateTime> tripNightsBetween(DateTime? start, DateTime? end) {
  if (start == null || end == null) return const [];
  final last = DateTime(end.year, end.month, end.day);
  return [
    for (var night = DateTime(start.year, start.month, start.day);
        night.isBefore(last);
        night = DateTime(night.year, night.month, night.day + 1))
      night,
  ];
}

/// The nights of [trip]; none for a day trip.
List<DateTime> tripNights(Trip trip) =>
    trip.isDayTrip ? const [] : tripNightsBetween(trip.startDate, trip.endDate);

String tripNightKey(DateTime night) =>
    TripMemberStay.dateKeyFromDateTime(night);

/// The lodgings of [trip]: the [stored] ones, or one for every night built
/// from the trip's former single link and address while none is stored.
List<TripLodging> effectiveTripLodgings(
  Trip trip,
  List<TripLodging> stored,
) {
  if (trip.isDayTrip) return const [];
  if (stored.isNotEmpty || trip.lodgingsByNight) return stored;
  if (trip.linkUrl.trim().isEmpty && trip.address.trim().isEmpty) {
    return const [];
  }
  return [
    TripLodging(
      id: tripLegacyLodgingId,
      address: trip.address.trim(),
      linkUrl: trip.linkUrl.trim(),
      linkPreview: trip.linkPreview,
      allNights: true,
      isLegacy: true,
    ),
  ];
}

/// Where the night of [nightKey] is spent, if known.
TripLodging? tripLodgingForNight(
  List<TripLodging> lodgings,
  String nightKey,
) {
  for (final lodging in lodgings) {
    if (!lodging.allNights && lodging.nightKeys.contains(nightKey)) {
      return lodging;
    }
  }
  for (final lodging in lodgings) {
    if (lodging.allNights) return lodging;
  }
  return null;
}

/// Consecutive nights spent at the same lodging, or not filled in.
class TripLodgingStage {
  const TripLodgingStage({required this.lodging, required this.nights});

  /// Null while the nights are not filled in.
  final TripLodging? lodging;

  /// Evenings, first to last; empty when the trip has no dates.
  final List<DateTime> nights;

  bool get isMissing => lodging == null;

  DateTime? get firstNight => nights.isEmpty ? null : nights.first;

  /// The morning the stage is left.
  DateTime? get checkOutDay {
    if (nights.isEmpty) return null;
    final last = nights.last;
    return DateTime(last.year, last.month, last.day + 1);
  }

  List<String> get nightKeys => [for (final n in nights) tripNightKey(n)];

  bool containsNight(DateTime night) =>
      nights.any((n) => tripNightKey(n) == tripNightKey(night));
}

/// The trip's [nights] grouped into stages: consecutive nights at the same
/// lodging, or not filled in, share one stage. Without dates, one stage per
/// lodging (one not filled in when there is none).
List<TripLodgingStage> tripLodgingStages(
  List<DateTime> nights,
  List<TripLodging> lodgings,
) {
  if (nights.isEmpty) {
    if (lodgings.isEmpty) {
      return const [TripLodgingStage(lodging: null, nights: [])];
    }
    return [
      for (final lodging in lodgings)
        TripLodgingStage(lodging: lodging, nights: const []),
    ];
  }
  final stages = <TripLodgingStage>[];
  TripLodging? current;
  var run = <DateTime>[];
  for (final night in nights) {
    final lodging = tripLodgingForNight(lodgings, tripNightKey(night));
    if (run.isNotEmpty && lodging?.id != current?.id) {
      stages.add(TripLodgingStage(lodging: current, nights: run));
      run = <DateTime>[];
    }
    current = lodging;
    run.add(night);
  }
  stages.add(TripLodgingStage(lodging: current, nights: run));
  return stages;
}

/// The stage holding [day]'s night, else the first one.
int tripLodgingStageIndexForDay(List<TripLodgingStage> stages, DateTime day) {
  final index = stages.indexWhere((stage) => stage.containsNight(day));
  return index < 0 ? 0 : index;
}

/// [lodgings] once the stage made of [previousNightKeys] at [previous] (null
/// for nights not filled in) is set to [place] for [nightKeys].
///
/// [place] carries the id of the lodging it stands for, or an empty id for
/// a new one. The nights chosen are taken from any other lodging. A lodging
/// changed keeps its id when it has no other nights; otherwise the stage
/// gets a lodging of its own and the other nights keep the former place.
/// Without [tripNightKeys] (no dates), [place] becomes the only lodging.
List<TripLodging> applyTripLodgingStage({
  required List<TripLodging> lodgings,
  required List<String> tripNightKeys,
  required TripLodging? previous,
  required List<String> previousNightKeys,
  required List<String> nightKeys,
  required TripLodging place,
}) {
  if (tripNightKeys.isEmpty) {
    final id = place.id.isNotEmpty
        ? place.id
        : (previous?.id ?? _newLodgingId(lodgings));
    return [place.copyWith(id: id, nightKeys: const [], allNights: true)];
  }

  final wasAllNights = lodgings.any((l) => l.allNights);
  var next = _withoutNights(
    _explicitLodgings(lodgings, tripNightKeys),
    previous?.id,
    previousNightKeys.toSet(),
  );

  final existing =
      place.id.isEmpty ? null : next.where((l) => l.id == place.id).firstOrNull;
  final String targetId;
  if (existing != null &&
      (existing.samePlaceAs(place) || existing.nightKeys.isEmpty)) {
    targetId = existing.id;
    next = [
      for (final l in next)
        l.id == targetId
            ? place.copyWith(
                id: targetId,
                nightKeys: l.nightKeys,
                allNights: false,
              )
            : l,
    ];
  } else {
    targetId = _newLodgingId(next);
    next = [
      ...next,
      place.copyWith(
        id: targetId,
        nightKeys: const [],
        allNights: false,
        isLegacy: false,
      ),
    ];
  }

  final tripNightSet = tripNightKeys.toSet();
  final taken = nightKeys.where(tripNightSet.contains).toSet();
  next = [
    for (final l in next)
      l.id == targetId
          ? l.copyWith(nightKeys: {...l.nightKeys, ...taken}.toList())
          : l.copyWith(
              nightKeys: l.nightKeys.where((n) => !taken.contains(n)).toList(),
            ),
  ];
  return _tidyLodgings(next, tripNightKeys, keepAllNights: wasAllNights);
}

/// [lodgings] once the stage made of [previousNightKeys] at [previous] is
/// no longer filled in.
List<TripLodging> removeTripLodgingStage({
  required List<TripLodging> lodgings,
  required List<String> tripNightKeys,
  required TripLodging previous,
  required List<String> previousNightKeys,
}) {
  if (tripNightKeys.isEmpty) {
    return lodgings.where((l) => l.id != previous.id).toList();
  }
  final next = _withoutNights(
    _explicitLodgings(lodgings, tripNightKeys),
    previous.id,
    previousNightKeys.toSet(),
  );
  return _tidyLodgings(next, tripNightKeys, keepAllNights: false);
}

/// [lodgings] kept to the nights of [tripNightKeys], e.g. once the trip
/// dates changed. Kept as they are without dates.
List<TripLodging> tripLodgingsWithinNights(
  List<TripLodging> lodgings,
  List<String> tripNightKeys,
) {
  if (tripNightKeys.isEmpty) return lodgings;
  final tripNightSet = tripNightKeys.toSet();
  return [
    for (final l in lodgings)
      if (l.allNights)
        l
      else if (l.nightKeys.any(tripNightSet.contains))
        l.copyWith(
          nightKeys: l.nightKeys.where(tripNightSet.contains).toList(),
        ),
  ];
}

/// Every lodging with its nights listed: a lodging for every night gets the
/// nights no other one has.
List<TripLodging> _explicitLodgings(
  List<TripLodging> lodgings,
  List<String> tripNightKeys,
) {
  final tripNightSet = tripNightKeys.toSet();
  final assigned = {
    for (final l in lodgings)
      if (!l.allNights) ...l.nightKeys.where(tripNightSet.contains),
  };
  return [
    for (final l in lodgings)
      l.copyWith(
        allNights: false,
        nightKeys: l.allNights
            ? tripNightKeys.where((n) => !assigned.contains(n)).toList()
            : l.nightKeys.where(tripNightSet.contains).toList(),
      ),
  ];
}

List<TripLodging> _withoutNights(
  List<TripLodging> lodgings,
  String? lodgingId,
  Set<String> nightKeys,
) {
  if (lodgingId == null) return lodgings;
  return [
    for (final l in lodgings)
      l.id == lodgingId
          ? l.copyWith(
              nightKeys:
                  l.nightKeys.where((n) => !nightKeys.contains(n)).toList(),
            )
          : l,
  ];
}

/// Drops lodgings left without nights; a single lodging for every night
/// stays one for every night when [keepAllNights].
List<TripLodging> _tidyLodgings(
  List<TripLodging> lodgings,
  List<String> tripNightKeys, {
  required bool keepAllNights,
}) {
  final kept = lodgings.where((l) => l.nightKeys.isNotEmpty).toList();
  if (keepAllNights &&
      kept.length == 1 &&
      kept.single.nightKeys.toSet().containsAll(tripNightKeys)) {
    return [kept.single.copyWith(allNights: true, nightKeys: const [])];
  }
  return [
    for (final l in kept) l.copyWith(nightKeys: [...l.nightKeys]..sort()),
  ];
}

String _newLodgingId(List<TripLodging> lodgings) {
  final ids = {for (final l in lodgings) l.id};
  var n = 1;
  while (ids.contains('$tripNewLodgingIdPrefix$n')) {
    n++;
  }
  return '$tripNewLodgingIdPrefix$n';
}
