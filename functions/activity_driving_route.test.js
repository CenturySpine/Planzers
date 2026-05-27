'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { parseRoutesApiResponse } = require('./activity_driving_route');

describe('parseRoutesApiResponse', () => {
  it('returns distance and duration when a route exists', () => {
    const result = parseRoutesApiResponse({
      routes: [{ distanceMeters: 12500, duration: '900s' }],
    });
    assert.deepEqual(result, {
      distanceMeters: 12500,
      durationSeconds: 900,
      distanceText: '13 km',
      durationText: '15 min',
    });
  });

  it('returns elementStatus when no route exists', () => {
    const result = parseRoutesApiResponse({ routes: [] });
    assert.deepEqual(result, { elementStatus: 'ZERO_RESULTS' });
  });

  it('throws when route payload has invalid duration', () => {
    assert.throws(
      () => parseRoutesApiResponse({ routes: [{ distanceMeters: 1200, duration: 'oops' }] }),
      /invalid distance\/duration/
    );
  });
});
