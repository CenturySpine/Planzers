import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/rooms/data/trip_room.dart';
import 'package:planerz/features/rooms/data/trip_room_lodgings.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_lodging.dart';
import 'package:planerz/features/trips/data/trip_lodging_plan.dart';

/// 10 to 14 July: nights of the 10th to the 13th.
Trip _trip({Map<String, dynamic> extra = const {}}) => Trip.fromMap('t1', {
      'title': 'Sicile',
      'startDate': Timestamp.fromDate(DateTime(2026, 7, 10)),
      'endDate': Timestamp.fromDate(DateTime(2026, 7, 14)),
      'lodgingsByNight': true,
      ...extra,
    });

TripRoom _room(String id, {String? lodgingId, String? nightKey}) => TripRoom(
      id: id,
      name: id,
      beds: const [],
      createdAt: DateTime(2026, 1, 1),
      lodgingId: lodgingId,
      nightKey: nightKey,
    );

const _borgo = TripLodging(
  id: 'borgo',
  name: 'Borgo',
  nightKeys: ['2026-07-10', '2026-07-11', '2026-07-13'],
);
const _masseria = TripLodging(
  id: 'masseria',
  name: 'Masseria',
  nightKeys: ['2026-07-12'],
);

List<String> _ids(List<TripRoom> rooms) => [for (final r in rooms) r.id];

void main() {
  final split = TripRoomLodgings.forTrip(_trip(), [_masseria, _borgo]);

  test('lodgings come in night order, with all the nights spent there', () {
    expect(split.lodgings.map((l) => l.id), ['borgo', 'masseria']);
    expect(split.lodgings.first.nightKeys, [
      '2026-07-10',
      '2026-07-11',
      '2026-07-13',
    ]);
  });

  test('rooms of a lodging gone, or set before, go with the first lodging', () {
    expect(split.lodgingIdOf(_room('a', lodgingId: 'masseria')), 'masseria');
    expect(split.lodgingIdOf(_room('b')), 'borgo');
    expect(split.lodgingIdOf(_room('c', lodgingId: 'gone')), 'borgo');
  });

  test('a night uses the shared rooms until it has rooms of its own', () {
    final rooms = [
      _room('shared', lodgingId: 'borgo'),
      _room('night', lodgingId: 'borgo', nightKey: '2026-07-11'),
      _room('other', lodgingId: 'masseria'),
    ];
    expect(_ids(split.commonRooms(rooms, 'borgo')), ['shared']);
    expect(_ids(split.roomsForNight(rooms, 'borgo', '2026-07-10')), ['shared']);
    expect(_ids(split.roomsForNight(rooms, 'borgo', '2026-07-11')), ['night']);
    expect(_ids(split.nightRooms(rooms, 'borgo', '2026-07-10')), isEmpty);
  });

  test("a day's rooms are those of its night, else of the first night", () {
    final rooms = [
      _room('shared', lodgingId: 'borgo'),
      _room('night', lodgingId: 'borgo', nightKey: '2026-07-11'),
      _room('other', lodgingId: 'masseria'),
    ];
    expect(_ids(split.roomsForDay(rooms, DateTime(2026, 7, 12))), ['other']);
    expect(_ids(split.roomsForDay(rooms, DateTime(2026, 7, 11))), ['night']);
    expect(_ids(split.roomsForDay(rooms, DateTime(2026, 6, 1))), ['shared']);
  });

  test('without lodgings, every room stands for every night', () {
    final none = TripRoomLodgings.forTrip(_trip(), const []);
    expect(none.lodgings.single.id, isNull);
    expect(none.lodgings.single.nights, hasLength(4));
    final rooms = [_room('a'), _room('b', lodgingId: 'gone')];
    expect(_ids(none.commonRooms(rooms, null)), ['a', 'b']);
  });

  test('the former single link stands for one lodging, stored as none', () {
    final legacy = _trip(extra: {
      'lodgingsByNight': false,
      'linkUrl': 'https://example.com/villa',
    });
    final legacySplit =
        TripRoomLodgings.forTrip(legacy, effectiveTripLodgings(legacy, []));
    expect(legacySplit.lodgings.single.lodging?.id, tripLegacyLodgingId);
    expect(legacySplit.lodgings.single.id, isNull);
    expect(_ids(legacySplit.commonRooms([_room('a')], null)), ['a']);
  });
}
