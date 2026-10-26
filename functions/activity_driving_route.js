'use strict';

const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const { onDocumentWritten, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

// OpenStreetMap services, free and keyless: Photon (komoot) turns an address
// into a point, and the FOSSGIS OSRM server (the one openstreetmap.org uses)
// computes the car route. Both ask for a moderate use from an identified
// client.
const PHOTON_SEARCH_URL = 'https://photon.komoot.io/api/';
const OSRM_CAR_ROUTE_URL = 'https://routing.openstreetmap.de/routed-car/route/v1/driving/';
const USER_AGENT = 'Planerz (https://planerz.centuryspine.org)';

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function asFiniteNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * @param {unknown} value a Firestore GeoPoint
 * @returns {{ latitude: number, longitude: number } | null}
 */
function pointOf(value) {
  const latitude = asFiniteNumber(value?.latitude);
  const longitude = asFiniteNumber(value?.longitude);
  return latitude == null || longitude == null ? null : { latitude, longitude };
}

/**
 * The place of an activity, to compute its route again only when it moves.
 * @param {FirebaseFirestore.DocumentData} data
 */
function activityPlaceKey(data) {
  const point = pointOf(data?.location);
  return `${normalizeString(data?.address)}|${point ? `${point.latitude},${point.longitude}` : ''}`;
}

/**
 * The point of Photon's first result, or null.
 * @param {unknown} data Photon GeoJSON response
 */
function parsePhotonPoint(data) {
  const feature = Array.isArray(data?.features) ? data.features[0] : null;
  const coordinates = feature?.geometry?.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length < 2) return null;
  return pointOf({ latitude: coordinates[1], longitude: coordinates[0] });
}

/**
 * @param {string} address
 * @returns {Promise<{ latitude: number, longitude: number } | null>}
 */
async function geocodeAddress(address) {
  const query = normalizeString(address);
  if (!query) return null;
  const url = new URL(PHOTON_SEARCH_URL);
  url.searchParams.set('q', query);
  url.searchParams.set('limit', '1');
  const res = await fetch(url, { headers: { 'User-Agent': USER_AGENT } });
  if (!res.ok) throw new Error(`Photon HTTP ${res.status}`);
  return parsePhotonPoint(await res.json());
}

/**
 * @param {unknown} data OSRM route response
 * @returns {{ distanceMeters: number, durationSeconds: number, distanceText: string, durationText: string } | { elementStatus: string }}
 */
function parseOsrmResponse(data) {
  const code = normalizeString(data?.code);
  // No road reaches one of the points, or none links them.
  if (code === 'NoRoute' || code === 'NoSegment') {
    return { elementStatus: code };
  }
  if (code !== 'Ok') {
    throw new Error(normalizeString(data?.message) || `OSRM ${code || 'error'}`);
  }
  const route = Array.isArray(data.routes) ? data.routes[0] : null;
  if (!route) {
    return { elementStatus: 'NoRoute' };
  }
  const distanceMeters = Math.round(Number(route.distance));
  const durationSeconds = Math.round(Number(route.duration));
  if (!Number.isFinite(distanceMeters) || !Number.isFinite(durationSeconds)) {
    throw new Error('OSRM returned invalid distance/duration');
  }
  return {
    distanceMeters,
    durationSeconds,
    distanceText: formatDistanceText(distanceMeters),
    durationText: formatDurationText(durationSeconds),
  };
}

/**
 * @param {{ latitude: number, longitude: number }} origin
 * @param {{ latitude: number, longitude: number }} destination
 */
async function fetchDrivingRoute(origin, destination) {
  const coordinates = [origin, destination]
    .map((point) => `${point.longitude},${point.latitude}`)
    .join(';');
  const res = await fetch(`${OSRM_CAR_ROUTE_URL}${coordinates}?overview=false`, {
    headers: { 'User-Agent': USER_AGENT },
  });
  let data = null;
  try {
    data = await res.json();
  } catch {
    throw new Error(`OSRM HTTP ${res.status}`);
  }
  return parseOsrmResponse(data);
}

function formatDistanceText(distanceMeters) {
  if (distanceMeters < 1000) return `${distanceMeters} m`;
  const kilometers = distanceMeters / 1000;
  if (kilometers >= 10) return `${Math.round(kilometers)} km`;
  return `${kilometers.toFixed(1).replace('.', ',')} km`;
}

function formatDurationText(durationSeconds) {
  const totalMinutes = Math.max(1, Math.round(durationSeconds / 60));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours <= 0) return `${totalMinutes} min`;
  if (minutes === 0) return `${hours} h`;
  return `${hours} h ${minutes} min`;
}

const TIME_ZONE = 'Europe/Paris';

const parisDateFormat = new Intl.DateTimeFormat('en-CA', {
  timeZone: TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

/**
 * Calendar day of [value] in Europe/Paris, as `yyyy-mm-dd`; '' when none.
 * Night keys of lodgings are calendar days in the same form.
 * @param {unknown} value a Firestore Timestamp, a Date or an ISO string
 */
function parisDateKey(value) {
  let date = null;
  if (value && typeof value.toDate === 'function') date = value.toDate();
  else if (value instanceof Date) date = value;
  else if (typeof value === 'string' && value.trim()) date = new Date(value);
  if (!date || Number.isNaN(date.getTime())) return '';
  return parisDateFormat.format(date);
}

/**
 * @param {string} key `yyyy-mm-dd`
 * @param {number} days
 */
function shiftDateKey(key, days) {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/**
 * Evenings of the trip's nights (`yyyy-mm-dd`), first to last; none for a
 * day trip or without both dates.
 * @param {FirebaseFirestore.DocumentData} tripData
 */
function tripNightKeys(tripData) {
  if (tripData?.isDayTrip === true) return [];
  const start = parisDateKey(tripData?.startDate);
  const end = parisDateKey(tripData?.endDate);
  if (!start || !end) return [];
  const keys = [];
  for (let key = start; key < end; key = shiftDateKey(key, 1)) keys.push(key);
  return keys;
}

/**
 * A lodging document (`trips/{tripId}/lodgings/{lodgingId}`) as used here.
 * @param {string} id
 * @param {FirebaseFirestore.DocumentData} data
 */
function lodgingOf(id, data) {
  return {
    id,
    name: normalizeString(data?.name),
    address: normalizeString(data?.address),
    location: pointOf(data?.location),
    nights: Array.isArray(data?.nights)
      ? data.nights.map((n) => normalizeString(n)).filter(Boolean)
      : [],
    allNights: data?.allNights === true,
  };
}

/**
 * The trip's lodgings: those stored, or its former single address for
 * every night while none is stored (as `effectiveTripLodgings` in the app).
 * @param {FirebaseFirestore.DocumentData} tripData
 * @param {ReturnType<typeof lodgingOf>[]} lodgings
 */
function effectiveLodgings(tripData, lodgings) {
  if (tripData?.isDayTrip === true) return [];
  if (lodgings.length > 0 || tripData?.lodgingsByNight === true) return lodgings;
  const address = normalizeString(tripData?.address);
  if (!address) return [];
  return [lodgingOf('legacy', { address, allNights: true })];
}

/**
 * Where the night of [nightKey] is spent (as `tripLodgingForNight` in the
 * app): the lodging having this night, else the one for every night.
 * @param {ReturnType<typeof lodgingOf>[]} lodgings
 * @param {string} nightKey
 */
function lodgingForNight(lodgings, nightKey) {
  return (
    lodgings.find((l) => !l.allNights && l.nights.includes(nightKey)) ??
    lodgings.find((l) => l.allNights) ??
    null
  );
}

/**
 * The lodging an activity's route starts from: the one of the night before
 * its day, where that day starts, or of the first night on the arrival day.
 * Without a date, the lodging of every night, or the trip's only lodging.
 * @param {FirebaseFirestore.DocumentData} tripData
 * @param {ReturnType<typeof lodgingOf>[]} lodgings stored ones
 * @param {FirebaseFirestore.DocumentData} activityData
 * @returns {{ lodging: ReturnType<typeof lodgingOf> } | { status: 'missing_lodging' | 'missing_activity_date' }}
 */
function originLodgingForActivity(tripData, lodgings, activityData) {
  const effective = effectiveLodgings(tripData, lodgings);
  const day = parisDateKey(activityData?.plannedAt);
  if (!day) {
    const lodging =
      effective.find((l) => l.allNights) ?? (effective.length === 1 ? effective[0] : null);
    if (lodging) return { lodging };
    return { status: effective.length > 0 ? 'missing_activity_date' : 'missing_lodging' };
  }
  const nights = new Set(tripNightKeys(tripData));
  const previous = shiftDateKey(day, -1);
  const nightKey = !nights.has(previous) && nights.has(day) ? day : previous;
  const lodging = lodgingForNight(effective, nightKey);
  return lodging ? { lodging } : { status: 'missing_lodging' };
}

/**
 * What an activity's route starts from, to compute it again only when it
 * changes: the lodging, its name shown with the route and its place, or
 * why there is none.
 * @param {ReturnType<typeof originLodgingForActivity>} origin
 */
function originKeyOf(origin) {
  if (!origin.lodging) return origin.status;
  const { id, name, address, location } = origin.lodging;
  const point = location ? `${location.latitude},${location.longitude}` : '';
  return `${id}|${name}|${address}|${point}`;
}

/**
 * Whether the route stored on an activity already starts from [origin].
 * @param {FirebaseFirestore.DocumentData} activityData
 * @param {ReturnType<typeof originLodgingForActivity>} origin
 */
function routeStartsFrom(activityData, origin) {
  const stored = activityData?.tripDrivingRoute;
  return (
    stored != null &&
    stored.status !== 'error' &&
    stored.status !== 'calculating' &&
    stored.originKey === originKeyOf(origin)
  );
}

/**
 * The point of a lodging: its own, else its address placed by Photon, once
 * per run. Null when not found or Photon fails (the route then reads as not
 * found).
 */
function lodgingPointResolver() {
  const cache = new Map();
  return async (lodging) => {
    if (lodging.location) return lodging.location;
    if (!cache.has(lodging.address)) {
      cache.set(
        lodging.address,
        geocodeAddress(lodging.address).catch((e) => {
          console.error('Lodging address geocoding failed', String(e));
          return null;
        })
      );
    }
    return cache.get(lodging.address);
  };
}

/**
 * Where the route to an activity ends: its point, or else its address
 * placed by Photon. Null when it has neither or the address is not found.
 * @param {FirebaseFirestore.DocumentData} data
 */
async function activityDestination(data) {
  return pointOf(data?.location) ?? geocodeAddress(data?.address);
}

/**
 * The route from [origin] to the activity, as stored or returned.
 * @param {{ latitude: number, longitude: number }} origin
 * @param {FirebaseFirestore.DocumentData} activityData
 */
async function drivingRouteToActivity(origin, activityData) {
  try {
    const destination = await activityDestination(activityData);
    if (!destination) {
      return { status: 'no_result', detail: 'ACTIVITY_ADDRESS_NOT_FOUND' };
    }
    const result = await fetchDrivingRoute(origin, destination);
    if (result.elementStatus) {
      return { status: 'no_result', detail: result.elementStatus };
    }
    return { status: 'ok', ...result };
  } catch (e) {
    return { status: 'error', errorMessage: String(e) };
  }
}

/**
 * Stores on the activity the route from its lodging (see
 * [originLodgingForActivity]) to its place, or removes it when the activity
 * has no place.
 * @param {FirebaseFirestore.DocumentReference} docRef
 * @param {FirebaseFirestore.DocumentData} activityData
 * @param {{ tripData: FirebaseFirestore.DocumentData, lodgings: ReturnType<typeof lodgingOf>[] }} trip
 * @param {ReturnType<typeof lodgingPointResolver>} pointOfLodging
 */
async function writeTripDrivingRouteForActivity(docRef, activityData, trip, pointOfLodging) {
  if (!normalizeString(activityData?.address) && !pointOf(activityData?.location)) {
    await docRef.set({ tripDrivingRoute: FieldValue.delete() }, { merge: true });
    return;
  }

  const origin = originLodgingForActivity(trip.tripData, trip.lodgings, activityData);
  const lodging = origin.lodging;
  let route;
  if (!lodging) {
    route = { status: origin.status };
  } else if (!lodging.address && !lodging.location) {
    route = { status: 'missing_lodging' };
  } else {
    const point = await pointOfLodging(lodging);
    route = point
      ? await drivingRouteToActivity(point, activityData)
      : { status: 'no_result', detail: 'LODGING_ADDRESS_NOT_FOUND' };
  }

  await docRef.set(
    {
      tripDrivingRoute: {
        ...route,
        originKey: originKeyOf(origin),
        // What the group typed, never content found from the lodging's link.
        ...(lodging ? { originLabel: lodging.name || lodging.address } : {}),
        calculatedAt: FieldValue.serverTimestamp(),
      },
    },
    { merge: true }
  );
}

/**
 * The trip and its stored lodgings.
 * @param {string} tripId
 */
async function loadTripForRoutes(tripId) {
  const tripRef = admin.firestore().collection('trips').doc(tripId);
  const [tripSnap, lodgingsSnap] = await Promise.all([
    tripRef.get(),
    tripRef.collection('lodgings').get(),
  ]);
  return {
    tripData: tripSnap.data() || {},
    lodgings: lodgingsSnap.docs.map((doc) => lodgingOf(doc.id, doc.data())),
  };
}

/**
 * Computes again the routes of the trip's activities with a place whose
 * starting lodging changed, among those [onlyIf] keeps.
 * @param {string} tripId
 * @param {(activityData: FirebaseFirestore.DocumentData, origin: ReturnType<typeof originLodgingForActivity>) => boolean} [onlyIf]
 */
async function recomputeTripDrivingRoutes(tripId, onlyIf = () => true) {
  const trip = await loadTripForRoutes(tripId);
  const activitiesSnap = await admin
    .firestore()
    .collection('trips')
    .doc(tripId)
    .collection('activities')
    .get();
  const pointOfLodging = lodgingPointResolver();
  for (const doc of activitiesSnap.docs) {
    const data = doc.data() || {};
    if (!normalizeString(data.address) && !pointOf(data.location)) continue;
    const origin = originLodgingForActivity(trip.tripData, trip.lodgings, data);
    if (routeStartsFrom(data, origin) || !onlyIf(data, origin)) continue;
    await writeTripDrivingRouteForActivity(doc.ref, data, trip, pointOfLodging);
  }
}

const computeActivityDrivingRouteFromTrip = onDocumentWritten(
  {
    document: 'trips/{tripId}/activities/{activityId}',
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (event) => {
    if (!event.data.after.exists) {
      return;
    }

    const before = event.data.before.exists ? event.data.before.data() || {} : {};
    const after = event.data.after.data() || {};
    // The day sets the lodging the route starts from.
    if (
      event.data.before.exists &&
      activityPlaceKey(before) === activityPlaceKey(after) &&
      parisDateKey(before.plannedAt) === parisDateKey(after.plannedAt)
    ) {
      return;
    }

    await writeTripDrivingRouteForActivity(
      event.data.after.ref,
      after,
      await loadTripForRoutes(event.params.tripId),
      lodgingPointResolver()
    );
  }
);

/**
 * What of a trip sets the lodgings of its nights: its former single
 * address, its dates, and whether its lodgings are set night by night.
 * @param {FirebaseFirestore.DocumentData} data
 */
function tripLodgingNightsKey(data) {
  return JSON.stringify([
    normalizeString(data?.address),
    tripNightKeys(data),
    data?.lodgingsByNight === true,
  ]);
}

/**
 * What of a lodging sets the routes starting from it.
 * @param {FirebaseFirestore.DocumentData | undefined} data
 */
function lodgingRouteKey(data) {
  if (!data) return '';
  const lodging = lodgingOf('', data);
  return JSON.stringify([
    lodging.name,
    lodging.address,
    lodging.location,
    [...lodging.nights].sort(),
    lodging.allNights,
  ]);
}

// Kept under its former name, already deployed: now follows everything of
// the trip that sets the lodgings of its nights.
const recomputeActivityDrivingRoutesOnTripAddressChange = onDocumentUpdated(
  {
    document: 'trips/{tripId}',
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (tripLodgingNightsKey(before) === tripLodgingNightsKey(after)) {
      return;
    }
    await recomputeTripDrivingRoutes(event.params.tripId);
  }
);

const recomputeActivityDrivingRoutesOnLodgingChange = onDocumentWritten(
  {
    document: 'trips/{tripId}/lodgings/{lodgingId}',
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : undefined;
    const after = event.data.after.exists ? event.data.after.data() : undefined;
    // Its link preview, among others, leaves the routes as they are.
    if (lodgingRouteKey(before) === lodgingRouteKey(after)) {
      return;
    }
    const lodgingId = event.params.lodgingId;
    // Other lodgings saved along with this one see to their own activities.
    await recomputeTripDrivingRoutes(
      event.params.tripId,
      (activityData, origin) =>
        origin.lodging?.id === lodgingId ||
        normalizeString(activityData.tripDrivingRoute?.originKey).startsWith(`${lodgingId}|`)
    );
  }
);

const refreshActivityDrivingRoute = onCall(
  { timeoutSeconds: 60, memory: '256MiB' },
  async (request) => {
    const uid = normalizeString(request.auth?.uid);
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
    }

    const tripId = normalizeString(request.data?.tripId);
    const activityId = normalizeString(request.data?.activityId);
    if (!tripId || !activityId) {
      throw new HttpsError('invalid-argument', 'Paramètres invalides');
    }

    const originType = normalizeString(request.data?.originType) || 'trip_address';
    if (originType !== 'trip_address' && originType !== 'current_location') {
      throw new HttpsError('invalid-argument', 'Type d’origine invalide');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const tripData = tripSnap.data() || {};
    const memberUserIds = Array.isArray(tripData.memberUserIds)
      ? tripData.memberUserIds.map((v) => normalizeString(v)).filter(Boolean)
      : [];
    if (!memberUserIds.includes(uid)) {
      throw new HttpsError('permission-denied', 'Droits insuffisants');
    }

    const activityRef = tripRef.collection('activities').doc(activityId);
    const activitySnap = await activityRef.get();
    if (!activitySnap.exists) {
      throw new HttpsError('not-found', 'Activité introuvable');
    }

    const activityData = activitySnap.data() || {};

    // Kept under its former name: the route from the activity's lodging.
    if (originType === 'trip_address') {
      await activityRef.set(
        {
          tripDrivingRoute: {
            status: 'calculating',
            calculatedAt: FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );

      await writeTripDrivingRouteForActivity(
        activityRef,
        activityData,
        await loadTripForRoutes(tripId),
        lodgingPointResolver()
      );
      return { ok: true };
    }

    const latitude = asFiniteNumber(request.data?.latitude);
    const longitude = asFiniteNumber(request.data?.longitude);
    if (latitude == null || longitude == null) {
      throw new HttpsError('invalid-argument', 'Coordonnées invalides');
    }
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      throw new HttpsError('invalid-argument', 'Coordonnées hors limites');
    }
    if (!normalizeString(activityData.address) && !pointOf(activityData.location)) {
      return {
        ok: true,
        route: { status: 'missing_activity_address' },
      };
    }

    return {
      ok: true,
      route: await drivingRouteToActivity({ latitude, longitude }, activityData),
    };
  }
);

module.exports = {
  computeActivityDrivingRouteFromTrip,
  recomputeActivityDrivingRoutesOnTripAddressChange,
  recomputeActivityDrivingRoutesOnLodgingChange,
  refreshActivityDrivingRoute,
  normalizeString,
  activityPlaceKey,
  parsePhotonPoint,
  parseOsrmResponse,
  fetchDrivingRoute,
  writeTripDrivingRouteForActivity,
  parisDateKey,
  tripNightKeys,
  lodgingOf,
  originLodgingForActivity,
  originKeyOf,
  routeStartsFrom,
  lodgingRouteKey,
  tripLodgingNightsKey,
};
