import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_lodging.dart';
import 'package:planerz/features/trips/data/trip_lodging_plan.dart';

Trip _trip({
  Map<String, dynamic> extra = const {},
  bool isDayTrip = false,
}) =>
    Trip.fromMap('t1', {
      'title': 'Sicile',
      'startDate': Timestamp.fromDate(DateTime(2026, 7, 10)),
      'endDate': Timestamp.fromDate(DateTime(2026, 7, 16)),
      if (isDayTrip) 'isDayTrip': true,
      ...extra,
    });

/// 10 to 15 July: six nights.
final _nights = tripNights(_trip());
final _keys = [for (final n in _nights) tripNightKey(n)];

TripLodging _hotel(
  String id, {
  String name = '',
  List<String> nights = const [],
  bool allNights = false,
}) =>
    TripLodging(
      id: id,
      name: name.isEmpty ? id : name,
      nightKeys: nights,
      allNights: allNights,
    );

List<String> _stageSummary(List<TripLodging> lodgings) => [
      for (final stage in tripLodgingStages(_nights, lodgings))
        '${stage.lodging?.name ?? '-'}:${stage.nights.length}',
    ];

void main() {
  test('nights run from the first evening to the eve of the last day', () {
    expect(_keys, [
      '2026-07-10',
      '2026-07-11',
      '2026-07-12',
      '2026-07-13',
      '2026-07-14',
      '2026-07-15',
    ]);
    expect(tripNights(_trip(isDayTrip: true)), isEmpty);
  });

  test('consecutive nights at the same lodging or not filled in share a stage',
      () {
    final lodgings = [
      _hotel('a', nights: ['2026-07-10', '2026-07-11']),
      _hotel('b', nights: ['2026-07-14']),
      _hotel('a2', name: 'a', nights: ['2026-07-15']),
    ];
    expect(_stageSummary(lodgings), ['a:2', '-:2', 'b:1', 'a:1']);
    expect(_stageSummary(const []), ['-:6']);
    expect(_stageSummary([_hotel('a', allNights: true)]), ['a:6']);
  });

  test('a lodging for every night yields to nights set elsewhere', () {
    final lodgings = [
      _hotel('a', allNights: true),
      _hotel('b', nights: ['2026-07-12']),
    ];
    expect(_stageSummary(lodgings), ['a:2', 'b:1', 'a:3']);
  });

  test('the stage of a day is the one holding its night, else the first', () {
    final stages = tripLodgingStages(_nights, [
      _hotel('a', nights: ['2026-07-10', '2026-07-11']),
      _hotel('b', nights: ['2026-07-12', '2026-07-13']),
    ]);
    expect(tripLodgingStageIndexForDay(stages, DateTime(2026, 7, 13)), 1);
    expect(tripLodgingStageIndexForDay(stages, DateTime(2026, 7, 14)), 2);
    expect(tripLodgingStageIndexForDay(stages, DateTime(2026, 8, 1)), 0);
  });

  test('filling in nights not filled in creates a lodging for them', () {
    final next = applyTripLodgingStage(
      lodgings: const [],
      tripNightKeys: _keys,
      previous: null,
      previousNightKeys: _keys,
      nightKeys: ['2026-07-10', '2026-07-11'],
      place: const TripLodging(id: '', name: 'Hôtel A'),
    );
    expect(next, hasLength(1));
    expect(next.single.id, startsWith(tripNewLodgingIdPrefix));
    expect(next.single.nightKeys, ['2026-07-10', '2026-07-11']);
    expect(next.single.allNights, isFalse);
  });

  test('shortening an all-nights lodging leaves the other nights to fill in',
      () {
    final all = _hotel('a', name: 'Hôtel A', allNights: true);
    final next = applyTripLodgingStage(
      lodgings: [all],
      tripNightKeys: _keys,
      previous: all,
      previousNightKeys: _keys,
      nightKeys: ['2026-07-10', '2026-07-11', '2026-07-12'],
      place: all,
    );
    expect(next.single.id, 'a');
    expect(next.single.allNights, isFalse);
    expect(_stageSummary(next), ['Hôtel A:3', '-:3']);
  });

  test('an all-nights lodging edited for every night stays one', () {
    final all = _hotel('a', name: 'Hôtel A', allNights: true);
    final next = applyTripLodgingStage(
      lodgings: [all],
      tripNightKeys: _keys,
      previous: all,
      previousNightKeys: _keys,
      nightKeys: _keys,
      place: all.copyWith(name: 'Hôtel B'),
    );
    expect(next.single.id, 'a');
    expect(next.single.allNights, isTrue);
    expect(next.single.name, 'Hôtel B');
  });

  test('nights set at another lodging are taken from the one having them', () {
    final a = _hotel('a', name: 'Hôtel A', allNights: true);
    final next = applyTripLodgingStage(
      lodgings: [a],
      tripNightKeys: _keys,
      previous: null,
      previousNightKeys: const [],
      nightKeys: ['2026-07-12', '2026-07-13'],
      place: const TripLodging(id: '', name: 'Gîte B'),
    );
    expect(_stageSummary(next), ['Hôtel A:2', 'Gîte B:2', 'Hôtel A:2']);
    expect(next.firstWhere((l) => l.id == 'a').nightKeys, [
      '2026-07-10',
      '2026-07-11',
      '2026-07-14',
      '2026-07-15',
    ]);
  });

  test('a lodging of the trip picked again gets the nights as they are', () {
    final a = _hotel('a', name: 'Hôtel A', nights: ['2026-07-10']);
    final next = applyTripLodgingStage(
      lodgings: [a],
      tripNightKeys: _keys,
      previous: null,
      previousNightKeys: ['2026-07-15'],
      nightKeys: ['2026-07-15'],
      place: a,
    );
    expect(next.single.id, 'a');
    expect(next.single.nightKeys, ['2026-07-10', '2026-07-15']);
  });

  test('changing the place of one stage of a shared lodging splits it', () {
    final a =
        _hotel('a', name: 'Hôtel A', nights: ['2026-07-10', '2026-07-15']);
    final next = applyTripLodgingStage(
      lodgings: [a],
      tripNightKeys: _keys,
      previous: a,
      previousNightKeys: ['2026-07-15'],
      nightKeys: ['2026-07-15'],
      place: a.copyWith(name: 'Hôtel C'),
    );
    expect(next, hasLength(2));
    expect(next.firstWhere((l) => l.id == 'a').nightKeys, ['2026-07-10']);
    final other = next.firstWhere((l) => l.id != 'a');
    expect(other.name, 'Hôtel C');
    expect(other.nightKeys, ['2026-07-15']);
  });

  test('changing the place of a lodging used by one stage keeps its id', () {
    final a = _hotel('a', name: 'Hôtel A', nights: ['2026-07-10']);
    final next = applyTripLodgingStage(
      lodgings: [a],
      tripNightKeys: _keys,
      previous: a,
      previousNightKeys: ['2026-07-10'],
      nightKeys: ['2026-07-10', '2026-07-11'],
      place: a.copyWith(name: 'Hôtel A bis'),
    );
    expect(next.single.id, 'a');
    expect(next.single.name, 'Hôtel A bis');
    expect(next.single.nightKeys, ['2026-07-10', '2026-07-11']);
  });

  test('a lodging left without nights is dropped', () {
    final a = _hotel('a', nights: ['2026-07-10']);
    final b = _hotel('b', nights: ['2026-07-11']);
    final next = applyTripLodgingStage(
      lodgings: [a, b],
      tripNightKeys: _keys,
      previous: a,
      previousNightKeys: ['2026-07-10'],
      nightKeys: ['2026-07-10'],
      place: b,
    );
    expect(next.single.id, 'b');
    expect(next.single.nightKeys, ['2026-07-10', '2026-07-11']);
  });

  test('removing a stage leaves its nights to fill in', () {
    final a = _hotel('a', nights: ['2026-07-10', '2026-07-11']);
    final b = _hotel('b', nights: ['2026-07-12']);
    final next = removeTripLodgingStage(
      lodgings: [a, b],
      tripNightKeys: _keys,
      previous: a,
      previousNightKeys: ['2026-07-10', '2026-07-11'],
    );
    expect(next.single.id, 'b');
    final all = _hotel('c', allNights: true);
    expect(
      removeTripLodgingStage(
        lodgings: [all],
        tripNightKeys: _keys,
        previous: all,
        previousNightKeys: _keys,
      ),
      isEmpty,
    );
  });

  test('without dates the place becomes the only lodging, for every night', () {
    final next = applyTripLodgingStage(
      lodgings: const [],
      tripNightKeys: const [],
      previous: null,
      previousNightKeys: const [],
      nightKeys: const [],
      place: const TripLodging(id: '', name: 'Hôtel A'),
    );
    expect(next.single.allNights, isTrue);
  });

  test('nights outside new trip dates are dropped', () {
    final next = tripLodgingsWithinNights(
      [
        _hotel('a', nights: ['2026-07-09', '2026-07-10']),
        _hotel('b', nights: ['2026-07-20']),
        _hotel('c', allNights: true),
      ],
      _keys,
    );
    expect(next.map((l) => l.id), ['a', 'c']);
    expect(next.first.nightKeys, ['2026-07-10']);
  });

  test('the former single link stands for every night until lodgings are set',
      () {
    final legacy = _trip(extra: {
      'linkUrl': 'https://example.com/villa',
      'address': '1 rue des Oliviers',
    });
    final lodgings = effectiveTripLodgings(legacy, const []);
    expect(lodgings.single.id, tripLegacyLodgingId);
    expect(lodgings.single.isLegacy, isTrue);
    expect(lodgings.single.allNights, isTrue);
    expect(lodgings.single.address, '1 rue des Oliviers');

    final migrated = _trip(extra: {
      'linkUrl': 'https://example.com/villa',
      'lodgingsByNight': true,
    });
    expect(effectiveTripLodgings(migrated, const []), isEmpty);

    final stored = [_hotel('a', allNights: true)];
    expect(effectiveTripLodgings(legacy, stored), stored);
    expect(effectiveTripLodgings(_trip(isDayTrip: true), stored), isEmpty);
  });

  test('the title falls back on the preview title, the address, the link', () {
    expect(const TripLodging(id: 'a', name: 'Hôtel').displayTitle, 'Hôtel');
    expect(
      const TripLodging(
        id: 'a',
        linkUrl: 'https://x.y',
        linkPreview: {'title': 'Villa'},
      ).displayTitle,
      'Villa',
    );
    expect(
      const TripLodging(id: 'a', address: '1 rue', linkUrl: 'https://x.y')
          .displayTitle,
      '1 rue',
    );
    expect(
      const TripLodging(id: 'a', linkUrl: 'https://x.y').displayTitle,
      'https://x.y',
    );
  });
}
