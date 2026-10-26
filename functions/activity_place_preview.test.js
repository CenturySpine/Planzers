'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  activityPlaceQuery,
  activityPlaceQueryKey,
} = require('./activity_place_preview');

describe('activityPlaceQuery', () => {
  const location = { latitude: 37.5, longitude: 15.08 };

  it('looks up the address picked on OpenStreetMap near its point', () => {
    assert.deepEqual(
      activityPlaceQuery({
        category: 'restaurant',
        label: "dej' spaghetti",
        address: 'Spaghetti & Co., Via Crociferi, 95124 Catane',
        location,
      }),
      { query: 'Spaghetti & Co., Via Crociferi, 95124 Catane', lat: 37.5, lng: 15.08 }
    );
  });

  it('falls back to the label for a point without address', () => {
    assert.deepEqual(
      activityPlaceQuery({ category: 'visit', label: 'Duomo', address: '', location }),
      { query: 'Duomo', lat: 37.5, lng: 15.08 }
    );
  });

  it('ignores transports and activities without a place', () => {
    assert.equal(
      activityPlaceQuery({ category: 'transport', address: 'Gare', location }),
      null
    );
    assert.equal(activityPlaceQuery({ category: 'visit', label: 'Duomo' }), null);
  });
});

describe('activityPlaceQueryKey', () => {
  it('changes only when the place looked up changes', () => {
    const base = { category: 'visit', label: 'A', address: 'Via Etnea', location: null };
    assert.equal(activityPlaceQueryKey(base), activityPlaceQueryKey({ ...base, label: 'B' }));
    assert.notEqual(
      activityPlaceQueryKey(base),
      activityPlaceQueryKey({ ...base, address: 'Via Crociferi' })
    );
    assert.equal(activityPlaceQueryKey({ category: 'transport', address: 'Gare' }), '');
  });
});
