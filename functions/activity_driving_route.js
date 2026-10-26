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
 * Stores the route from the trip address to the activity. [tripOrigin] is
 * the trip address placed by Photon (null when not found).
 * @param {FirebaseFirestore.DocumentReference} docRef
 * @param {string} tripAddress
 * @param {{ latitude: number, longitude: number } | null} tripOrigin
 * @param {FirebaseFirestore.DocumentData} activityData
 */
async function writeTripDrivingRouteForActivity(docRef, tripAddress, tripOrigin, activityData) {
  if (!normalizeString(activityData?.address) && !pointOf(activityData?.location)) {
    await docRef.set({ tripDrivingRoute: FieldValue.delete() }, { merge: true });
    return;
  }

  const route = !tripAddress
    ? { status: 'missing_trip_address' }
    : !tripOrigin
      ? { status: 'no_result', detail: 'TRIP_ADDRESS_NOT_FOUND' }
      : await drivingRouteToActivity(tripOrigin, activityData);

  await docRef.set(
    { tripDrivingRoute: { ...route, calculatedAt: FieldValue.serverTimestamp() } },
    { merge: true }
  );
}

/**
 * The trip address placed by Photon; null when empty, not found or Photon
 * fails (the route then reads as not found).
 * @param {string} tripAddress
 */
async function tripOriginOf(tripAddress) {
  if (!tripAddress) return null;
  try {
    return await geocodeAddress(tripAddress);
  } catch (e) {
    console.error('Trip address geocoding failed', String(e));
    return null;
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
    if (event.data.before.exists && activityPlaceKey(before) === activityPlaceKey(after)) {
      return;
    }

    const tripId = event.params.tripId;
    const tripSnap = await admin.firestore().collection('trips').doc(tripId).get();
    const tripAddress = normalizeString(tripSnap.data()?.address);

    await writeTripDrivingRouteForActivity(
      event.data.after.ref,
      tripAddress,
      await tripOriginOf(tripAddress),
      after
    );
  }
);

const recomputeActivityDrivingRoutesOnTripAddressChange = onDocumentUpdated(
  {
    document: 'trips/{tripId}',
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const beforeAddr = normalizeString(before.address);
    const afterAddr = normalizeString(after.address);
    if (beforeAddr === afterAddr) {
      return;
    }

    const tripId = event.params.tripId;
    const activitiesSnap = await admin
      .firestore()
      .collection('trips')
      .doc(tripId)
      .collection('activities')
      .get();

    const tripOrigin = await tripOriginOf(afterAddr);
    for (const doc of activitiesSnap.docs) {
      const data = doc.data() || {};
      if (!normalizeString(data.address) && !pointOf(data.location)) continue;
      await writeTripDrivingRouteForActivity(doc.ref, afterAddr, tripOrigin, data);
    }
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
    const tripAddress = normalizeString(tripData.address);

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
        tripAddress,
        await tripOriginOf(tripAddress),
        activityData
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
  refreshActivityDrivingRoute,
  normalizeString,
  activityPlaceKey,
  parsePhotonPoint,
  parseOsrmResponse,
  fetchDrivingRoute,
  writeTripDrivingRouteForActivity,
};
