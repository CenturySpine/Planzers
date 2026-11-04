'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeCarpoolDirection,
  carDirection,
  participantIdsSeatedInDirection,
  isDriverInDirection,
  isDriverOfAnyCar,
  removePassengerFromDirection,
  removePassengerFromAllCars,
} = require('./carpool_legs');

const outboundCar = {
  id: 'out1',
  direction: 'outbound',
  driverParticipantId: 'd1',
  assignedParticipantIds: ['d1', 'p1', 'p2'],
};
const legacyCar = {
  id: 'legacy',
  driverParticipantId: 'd2',
  assignedParticipantIds: ['d2', 'p3'],
};
const returnCar = {
  id: 'ret1',
  direction: 'return',
  driverParticipantId: 'd1',
  assignedParticipantIds: ['d1', ' p1 '],
};
const cars = [outboundCar, legacyCar, returnCar];

describe('normalizeCarpoolDirection', () => {
  it('keeps return and treats anything else as outbound', () => {
    assert.equal(normalizeCarpoolDirection(' return '), 'return');
    assert.equal(normalizeCarpoolDirection('outbound'), 'outbound');
    assert.equal(normalizeCarpoolDirection(undefined), 'outbound');
    assert.equal(normalizeCarpoolDirection('sideways'), 'outbound');
  });

  it('reads cars saved before directions existed as outbound', () => {
    assert.equal(carDirection(legacyCar), 'outbound');
    assert.equal(carDirection(returnCar), 'return');
  });
});

describe('participantIdsSeatedInDirection', () => {
  it('lists drivers and passengers of that direction only', () => {
    assert.deepEqual(
      [...participantIdsSeatedInDirection(cars, 'outbound')].sort(),
      ['d1', 'd2', 'p1', 'p2', 'p3']
    );
    assert.deepEqual(
      [...participantIdsSeatedInDirection(cars, 'return')].sort(),
      ['d1', 'p1']
    );
  });

  it('leaves out the car being edited', () => {
    assert.deepEqual(
      [...participantIdsSeatedInDirection(cars, 'return', 'ret1')],
      []
    );
  });
});

describe('drivers', () => {
  it('knows who drives in which direction', () => {
    assert.equal(isDriverInDirection(cars, 'd1', 'return'), true);
    assert.equal(isDriverInDirection(cars, 'd2', 'return'), false);
    assert.equal(isDriverInDirection(cars, 'd2', 'outbound'), true);
    assert.equal(isDriverOfAnyCar(cars, 'd2'), true);
    assert.equal(isDriverOfAnyCar(cars, 'p1'), false);
  });
});

describe('removePassengerFromDirection', () => {
  it('frees the seat of that direction and keeps the other one', () => {
    const next = removePassengerFromDirection(cars, 'p1', 'outbound');
    assert.deepEqual(next[0].assignedParticipantIds, ['d1', 'p2']);
    assert.deepEqual(next[2].assignedParticipantIds, ['d1', ' p1 ']);
    assert.deepEqual(outboundCar.assignedParticipantIds, ['d1', 'p1', 'p2']);
  });
});

describe('removePassengerFromAllCars', () => {
  it('frees every seat of a participant leaving the trip', () => {
    const { cars: next, changed } = removePassengerFromAllCars(cars, 'p1');
    assert.equal(changed, true);
    assert.deepEqual(next[0].assignedParticipantIds, ['d1', 'p2']);
    assert.deepEqual(next[2].assignedParticipantIds, ['d1']);
  });

  it('reports no change when they had no seat', () => {
    const { changed } = removePassengerFromAllCars(cars, 'nobody');
    assert.equal(changed, false);
  });
});
