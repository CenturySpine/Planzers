'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  activityPlaceKey,
  parsePhotonPoint,
  parseOsrmResponse,
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
