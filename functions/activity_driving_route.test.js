'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  activityPlaceKey,
  parsePhotonPoint,
  parseOsrmResponse,
  parisDateKey,
  tripNightKeys,
  lodgingOf,
  originLodgingForActivity,
  originKeyOf,
  routeStartsFrom,
  lodgingRouteKey,
  tripLodgingNightsKey,
} = require('./activity_driving_route');

describe('parseOsrmResponse', () => {
  it('returns distance and duration when a route exists', () => {
    const result = parseOsrmResponse({
      code: 'Ok',
      routes: [{ distance: 12500.4, duration: 899.6 }],
    });
    assert.deepEqual(result, {
      distanceMeters: 12500,
      durationSeconds: 900,
      distanceText: '13 km',
      durationText: '15 min',
    });
  });

  it('returns elementStatus when no road links the points', () => {
    assert.deepEqual(parseOsrmResponse({ code: 'NoRoute' }), { elementStatus: 'NoRoute' });
    assert.deepEqual(parseOsrmResponse({ code: 'NoSegment' }), { elementStatus: 'NoSegment' });
    assert.deepEqual(parseOsrmResponse({ code: 'Ok', routes: [] }), { elementStatus: 'NoRoute' });
  });

  it('throws on an error or an invalid route', () => {
    assert.throws(
      () => parseOsrmResponse({ code: 'InvalidQuery', message: 'Query string malformed' }),
      /malformed/
    );
    assert.throws(
      () => parseOsrmResponse({ code: 'Ok', routes: [{ distance: 'x', duration: 10 }] }),
      /invalid distance\/duration/
    );
  });
});

describe('parsePhotonPoint', () => {
  it('reads the first result as latitude and longitude', () => {
    const point = parsePhotonPoint({
      features: [{ geometry: { coordinates: [15.087, 37.502] } }],
    });
    assert.deepEqual(point, { latitude: 37.502, longitude: 15.087 });
  });

  it('returns null without a result', () => {
    assert.equal(parsePhotonPoint({ features: [] }), null);
    assert.equal(parsePhotonPoint(null), null);
  });
});

describe('activityPlaceKey', () => {
  it('changes with the address or the point only', () => {
    const base = { address: 'Via Crociferi', location: { latitude: 37.5, longitude: 15.08 } };
    assert.equal(activityPlaceKey(base), activityPlaceKey({ ...base, label: 'Autre' }));
    assert.notEqual(activityPlaceKey(base), activityPlaceKey({ ...base, address: 'Via Etnea' }));
    assert.notEqual(
      activityPlaceKey(base),
      activityPlaceKey({ ...base, location: { latitude: 37.6, longitude: 15.08 } })
    );
  });
});

/** A Firestore Timestamp stand-in, at [iso] (Paris time in summer). */
function at(iso) {
  return { toDate: () => new Date(iso) };
}

// 10 to 13 July: nights of the 10th, 11th and 12th.
const trip = {
  startDate: at('2026-07-10T00:00:00+02:00'),
  endDate: at('2026-07-13T00:00:00+02:00'),
  lodgingsByNight: true,
};
const borgo = lodgingOf('borgo', {
  name: 'Borgo degli Ulivi',
  address: 'Contrada Busulmone, Noto',
  nights: ['2026-07-10', '2026-07-11'],
});
const masseria = lodgingOf('masseria', {
  name: 'Masseria',
  location: { latitude: 36.9, longitude: 15.07 },
  nights: ['2026-07-12'],
});

function originId(activity, lodgings = [borgo, masseria], tripData = trip) {
  const origin = originLodgingForActivity(tripData, lodgings, activity);
  return origin.lodging ? origin.lodging.id : origin.status;
}

describe('parisDateKey and tripNightKeys', () => {
  it('reads calendar days in Paris', () => {
    assert.equal(parisDateKey(at('2026-07-10T23:30:00+02:00')), '2026-07-10');
    assert.equal(parisDateKey(at('2026-07-10T22:30:00Z')), '2026-07-11');
    assert.equal(parisDateKey(null), '');
  });

  it('lists the evenings from the first day to the eve of the last one', () => {
    assert.deepEqual(tripNightKeys(trip), ['2026-07-10', '2026-07-11', '2026-07-12']);
    assert.deepEqual(tripNightKeys({ ...trip, isDayTrip: true }), []);
    assert.deepEqual(tripNightKeys({ startDate: trip.startDate }), []);
  });
});

describe('originLodgingForActivity', () => {
  it('starts from the lodging of the night before the activity', () => {
    assert.equal(originId({ plannedAt: at('2026-07-11T10:00:00+02:00') }), 'borgo');
    assert.equal(originId({ plannedAt: at('2026-07-12T21:00:00+02:00') }), 'borgo');
    assert.equal(originId({ plannedAt: at('2026-07-13T09:00:00+02:00') }), 'masseria');
  });

  it('starts from the first night on the arrival day', () => {
    assert.equal(originId({ plannedAt: at('2026-07-10T16:00:00+02:00') }), 'borgo');
  });

  it('reads as missing for a night not filled in', () => {
    assert.equal(
      originId({ plannedAt: at('2026-07-13T09:00:00+02:00') }, [borgo]),
      'missing_lodging'
    );
  });

  it('falls back on the lodging of every night', () => {
    const everyNight = lodgingOf('all', { address: 'Ortigia', allNights: true });
    assert.equal(originId({ plannedAt: at('2026-07-12T10:00:00+02:00') }, [everyNight]), 'all');
    assert.equal(originId({ plannedAt: at('2026-08-01T10:00:00+02:00') }, [everyNight]), 'all');
    assert.equal(
      originId({ plannedAt: at('2026-07-11T10:00:00+02:00') }, [everyNight, borgo]),
      'borgo'
    );
  });

  it('takes the only lodging for an activity without date, else asks for one', () => {
    assert.equal(originId({}, [borgo]), 'borgo');
    assert.equal(originId({}, [borgo, masseria]), 'missing_activity_date');
    assert.equal(originId({}, []), 'missing_lodging');
  });

  it('starts from the former trip address until lodgings are set', () => {
    const legacy = { ...trip, lodgingsByNight: false, address: '1 via Roma' };
    const origin = originLodgingForActivity(legacy, [], {
      plannedAt: at('2026-07-11T10:00:00+02:00'),
    });
    assert.equal(origin.lodging.id, 'legacy');
    assert.equal(origin.lodging.address, '1 via Roma');
    assert.equal(originId({}, [], { ...trip, address: '1 via Roma' }), 'missing_lodging');
  });
});

describe('routeStartsFrom', () => {
  it('keeps a route already computed from the same lodging and place', () => {
    const origin = { lodging: borgo };
    const route = { status: 'ok', originKey: originKeyOf(origin) };
    assert.equal(routeStartsFrom({ tripDrivingRoute: route }, origin), true);
    assert.equal(
      routeStartsFrom({ tripDrivingRoute: { ...route, status: 'error' } }, origin),
      false
    );
    assert.equal(routeStartsFrom({ tripDrivingRoute: route }, { lodging: masseria }), false);
    assert.equal(
      routeStartsFrom({ tripDrivingRoute: route }, { lodging: { ...borgo, name: 'Borgo' } }),
      false
    );
    assert.equal(routeStartsFrom({}, origin), false);
  });
});

describe('change keys', () => {
  it('ignore what leaves the routes as they are', () => {
    const data = { name: 'Borgo', address: 'Noto', nights: ['2026-07-11', '2026-07-10'] };
    assert.equal(
      lodgingRouteKey(data),
      lodgingRouteKey({ ...data, linkPreview: { title: 'x' }, nights: ['2026-07-10', '2026-07-11'] })
    );
    assert.notEqual(lodgingRouteKey(data), lodgingRouteKey({ ...data, address: 'Siracusa' }));
    assert.notEqual(lodgingRouteKey(data), lodgingRouteKey(undefined));
    assert.equal(tripLodgingNightsKey(trip), tripLodgingNightsKey({ ...trip, title: 'Sicile' }));
    assert.notEqual(
      tripLodgingNightsKey(trip),
      tripLodgingNightsKey({ ...trip, endDate: at('2026-07-14T00:00:00+02:00') })
    );
  });
});
