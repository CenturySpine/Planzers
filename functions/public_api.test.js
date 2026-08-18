const test = require('node:test');
const assert = require('node:assert/strict');
const { mapTripToApiShape } = require('./public_api');

function fakeTimestamp(dateString) {
  return { toDate: () => new Date(dateString) };
}

test('mapTripToApiShape: uses destination as location when present', () => {
  const result = mapTripToApiShape('trip-1', {
    title: 'Ski entre amis',
    destination: 'Chamonix',
    address: '',
    startDate: fakeTimestamp('2026-08-20'),
    endDate: fakeTimestamp('2026-08-25'),
  });

  assert.deepEqual(result, {
    id: 'trip-1',
    name: 'Ski entre amis',
    location: 'Chamonix',
    startDate: '2026-08-20',
    endDate: '2026-08-25',
  });
});

test('mapTripToApiShape: falls back to address for day trips without a destination', () => {
  const result = mapTripToApiShape('trip-2', {
    title: 'Journée à la mer',
    destination: '',
    address: 'Plage du Prado, Marseille',
    startDate: fakeTimestamp('2026-09-01'),
    endDate: fakeTimestamp('2026-09-01'),
  });

  assert.equal(result.location, 'Plage du Prado, Marseille');
});

test('mapTripToApiShape: missing dates map to null, not throw', () => {
  const result = mapTripToApiShape('trip-3', {
    title: 'Voyage sans dates',
    destination: 'Rome',
  });

  assert.equal(result.startDate, null);
  assert.equal(result.endDate, null);
});
