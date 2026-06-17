const test = require('node:test');
const assert = require('node:assert/strict');
const { defaultStayForTrip } = require('./trip_stay_defaults');

function timestamp(date) {
  return {
    toDate: () => date,
  };
}

test('preparation trips do not receive generated stay fields', () => {
  const stayFields = defaultStayForTrip({
    lifecycleStatus: 'preparation',
  });

  assert.deepEqual(stayFields, {});
});

test('planned trips still receive default stay fields from trip dates', () => {
  const stayFields = defaultStayForTrip({
    lifecycleStatus: 'planned',
    startDate: timestamp(new Date('2026-07-01T00:00:00.000Z')),
    endDate: timestamp(new Date('2026-07-05T00:00:00.000Z')),
  });

  assert.deepEqual(stayFields, {
    stayStartDateKey: '2026-07-01',
    stayStartDayPart: 'evening',
    stayEndDateKey: '2026-07-05',
    stayEndDayPart: 'morning',
  });
});
