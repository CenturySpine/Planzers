'use strict';

/**
 * Carpool rules per trip direction.
 *
 * A carpool is either an outbound ride (to the trip) or a return ride (back
 * home). A participant may be in at most one car per direction, so the same
 * person can drive or ride both ways. Cars saved before directions existed
 * have no `direction` field and count as outbound.
 */

const CARPOOL_DIRECTION_OUTBOUND = 'outbound';
const CARPOOL_DIRECTION_RETURN = 'return';

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

/** 'return' when explicitly set, 'outbound' otherwise (legacy cars included). */
function normalizeCarpoolDirection(raw) {
  return normalizeString(raw) === CARPOOL_DIRECTION_RETURN
    ? CARPOOL_DIRECTION_RETURN
    : CARPOOL_DIRECTION_OUTBOUND;
}

function carDirection(car) {
  return normalizeCarpoolDirection(car && car.direction);
}

function carAssignedIds(car) {
  const raw = car && Array.isArray(car.assignedParticipantIds)
    ? car.assignedParticipantIds
    : [];
  return raw.map((x) => String(x).trim()).filter(Boolean);
}

/**
 * Participant ids seated in cars of [direction], the car [excludedCarId]
 * apart. Drivers count as seated.
 */
function participantIdsSeatedInDirection(cars, direction, excludedCarId = '') {
  const seated = new Set();
  for (const car of cars) {
    if (carDirection(car) !== direction) continue;
    if (excludedCarId && normalizeString(car.id) === excludedCarId) continue;
    for (const id of carAssignedIds(car)) seated.add(id);
    const driverId = normalizeString(car.driverParticipantId);
    if (driverId) seated.add(driverId);
  }
  return seated;
}

function isDriverInDirection(cars, participantId, direction) {
  return cars.some(
    (car) =>
      carDirection(car) === direction &&
      normalizeString(car.driverParticipantId) === participantId
  );
}

function isDriverOfAnyCar(cars, participantId) {
  return cars.some(
    (car) => normalizeString(car.driverParticipantId) === participantId
  );
}

/** Copy of [cars] where [participantId] is no longer a passenger of [direction]. */
function removePassengerFromDirection(cars, participantId, direction) {
  return cars.map((car) => {
    if (carDirection(car) !== direction) return { ...car };
    return {
      ...car,
      assignedParticipantIds: carAssignedIds(car).filter((id) => id !== participantId),
    };
  });
}

/**
 * Frees the seats of a participant leaving the trip. Returns the cars and
 * whether any of them changed. Their own cars are not touched: a driver
 * cannot leave the trip (see the removal checks).
 */
function removePassengerFromAllCars(cars, participantId) {
  let changed = false;
  const nextCars = cars.map((car) => {
    const assigned = carAssignedIds(car);
    if (!assigned.includes(participantId)) return { ...car };
    changed = true;
    return {
      ...car,
      assignedParticipantIds: assigned.filter((id) => id !== participantId),
    };
  });
  return { cars: nextCars, changed };
}

module.exports = {
  CARPOOL_DIRECTION_OUTBOUND,
  CARPOOL_DIRECTION_RETURN,
  normalizeCarpoolDirection,
  carDirection,
  participantIdsSeatedInDirection,
  isDriverInDirection,
  isDriverOfAnyCar,
  removePassengerFromDirection,
  removePassengerFromAllCars,
};
