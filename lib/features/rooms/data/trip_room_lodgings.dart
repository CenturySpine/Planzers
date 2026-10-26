import 'package:planerz/features/rooms/data/trip_room.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_lodging.dart';
import 'package:planerz/features/trips/data/trip_lodging_plan.dart';

/// A lodging rooms are set for, with the trip's nights spent there.
class TripRoomsLodging {
  const TripRoomsLodging({required this.lodging, required this.nights});

  /// Null when the trip has no lodging filled in: its rooms then stand for
  /// every night.
  final TripLodging? lodging;

  /// Evenings, first to last; empty without trip dates.
  final List<DateTime> nights;

  /// Stored on the rooms of this lodging; null for the lodging built from
  /// the trip's former single link, which has no document of its own.
  String? get id => lodging == null || lodging!.isLegacy ? null : lodging!.id;

  List<String> get nightKeys => [for (final n in nights) tripNightKey(n)];
}

/// How the trip's rooms split between its lodgings: rooms shared by every
/// night of a lodging, and rooms of a single night set apart from them.
class TripRoomLodgings {
  const TripRoomLodgings(this.lodgings);

  /// The lodgings of the trip in night order; never empty.
  final List<TripRoomsLodging> lodgings;

  /// For [trip] and its [lodgings] (see `effectiveTripLodgings`).
  factory TripRoomLodgings.forTrip(Trip trip, List<TripLodging> lodgings) {
    final nights = tripNights(trip);
    if (lodgings.isEmpty) {
      return TripRoomLodgings([
        TripRoomsLodging(lodging: null, nights: nights),
      ]);
    }
    final nightsById = <String, List<DateTime>>{};
    final byId = {for (final l in lodgings) l.id: l};
    for (final night in nights) {
      final lodging = tripLodgingForNight(lodgings, tripNightKey(night));
      if (lodging == null) continue;
      nightsById.putIfAbsent(lodging.id, () => []).add(night);
    }
    // Lodgings no night falls on (e.g. a trip without dates) come last.
    return TripRoomLodgings([
      for (final entry in nightsById.entries)
        TripRoomsLodging(lodging: byId[entry.key], nights: entry.value),
      for (final lodging in lodgings)
        if (!nightsById.containsKey(lodging.id))
          TripRoomsLodging(lodging: lodging, nights: const []),
    ]);
  }

  /// The lodging [room] is in: its own when still among the trip's, else the
  /// first one (rooms set before lodgings were set night by night, or in a
  /// lodging removed since).
  String? lodgingIdOf(TripRoom room) {
    final id = room.lodgingId;
    if (id != null && lodgings.any((l) => l.id == id)) return id;
    return lodgings.first.id;
  }

  /// The rooms shared by every night of [lodgingId].
  List<TripRoom> commonRooms(List<TripRoom> rooms, String? lodgingId) => [
        for (final room in rooms)
          if (room.nightKey == null && lodgingIdOf(room) == lodgingId) room,
      ];

  /// The rooms set apart for [nightKey] at [lodgingId]; empty while that
  /// night uses the shared rooms.
  List<TripRoom> nightRooms(
    List<TripRoom> rooms,
    String? lodgingId,
    String nightKey,
  ) =>
      [
        for (final room in rooms)
          if (room.nightKey == nightKey && lodgingIdOf(room) == lodgingId) room,
      ];

  /// The rooms used on [nightKey] at [lodgingId]: its own, else the shared
  /// ones.
  List<TripRoom> roomsForNight(
    List<TripRoom> rooms,
    String? lodgingId,
    String nightKey,
  ) {
    final own = nightRooms(rooms, lodgingId, nightKey);
    return own.isNotEmpty ? own : commonRooms(rooms, lodgingId);
  }

  /// The rooms of [day]'s night: those of its lodging, the night's own when
  /// set apart. A day out of the trip's nights falls back on the first
  /// night; without dates, on the shared rooms of the first lodging.
  List<TripRoom> roomsForDay(List<TripRoom> rooms, DateTime day) {
    final key = tripNightKey(day);
    for (final lodging in lodgings) {
      if (lodging.nightKeys.contains(key)) {
        return roomsForNight(rooms, lodging.id, key);
      }
    }
    final first = lodgings.first;
    if (first.nights.isEmpty) return commonRooms(rooms, first.id);
    return roomsForNight(rooms, first.id, first.nightKeys.first);
  }
}
