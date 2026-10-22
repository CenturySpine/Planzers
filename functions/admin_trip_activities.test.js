'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { FieldValue } = require('firebase-admin/firestore');
const {
  tripDateOnly,
  compareTripsByStartDesc,
  walletLinksUpdate,
  usesDeletedRestaurant,
} = require('./admin_trip_activities');

describe('walletLinksUpdate', () => {
  const deleted = new Set(['a1', 'a2']);

  it('keeps the links to other activities', () => {
    const update = walletLinksUpdate({ activityIds: ['a1', 'x9'] }, deleted);
    assert.deepEqual(update.activityIds, ['x9']);
    assert.equal('activityId' in update, false);
  });

  it('removes the list when no link is left', () => {
    const update = walletLinksUpdate({ activityIds: ['a1', 'a2'] }, deleted);
    assert.ok(update.activityIds.isEqual(FieldValue.delete()));
  });

  it('removes the former single link', () => {
    const update = walletLinksUpdate({ activityId: ' a2 ' }, deleted);
    assert.ok(update.activityId.isEqual(FieldValue.delete()));
  });

  it('leaves documents linking none of the activities untouched', () => {
    assert.equal(walletLinksUpdate({ activityIds: ['x9'], activityId: 'x8' }, deleted), null);
    assert.equal(walletLinksUpdate({}, deleted), null);
  });
});

describe('usesDeletedRestaurant', () => {
  it('detects a meal whose restaurant is deleted', () => {
    const deleted = new Set(['r1']);
    assert.equal(usesDeletedRestaurant({ restaurantActivityId: 'r1' }, deleted), true);
    assert.equal(usesDeletedRestaurant({ restaurantActivityId: 'r2' }, deleted), false);
    assert.equal(usesDeletedRestaurant({ restaurantActivityId: '' }, deleted), false);
  });
});

describe('tripDateOnly', () => {
  it('rounds a stored midnight to its day', () => {
    // Midnight in Paris (UTC+2) is 22:00 UTC the day before.
    const stored = { toDate: () => new Date('2026-07-09T22:00:00Z') };
    assert.equal(tripDateOnly(stored), '2026-07-10');
    assert.equal(tripDateOnly('2026-07-10T00:00:00.000'), '2026-07-10');
    assert.equal(tripDateOnly(undefined), '');
  });
});

describe('compareTripsByStartDesc', () => {
  it('lists the most recent trips first and undated ones last', () => {
    const trips = [
      { title: 'B', startDate: '' },
      { title: 'Old', startDate: '2025-05-01' },
      { title: 'New', startDate: '2026-07-10' },
    ];
    assert.deepEqual(trips.sort(compareTripsByStartDesc).map((t) => t.title), ['New', 'Old', 'B']);
  });
});
