'use strict';

const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const { onDocumentWritten, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function asFiniteNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * @param {unknown} data
 * @returns {Promise<{ distanceMeters: number, durationSeconds: number, distanceText: string, durationText: string } | { elementStatus: string }>}
 */
function parseRoutesApiResponse(data) {
  const route = Array.isArray(data.routes) ? data.routes[0] : null;
  if (!route) {
    return { elementStatus: 'ZERO_RESULTS' };
  }
  const distanceMeters = Number(route.distanceMeters);
  const durationRaw = normalizeString(route.duration);
  const durationMatch = durationRaw.match(/^(\d+(?:\.\d+)?)s$/);
  const durationSeconds = durationMatch ? Math.round(Number(durationMatch[1])) : NaN;
  if (!Number.isFinite(distanceMeters) || !Number.isFinite(durationSeconds)) {
    throw new Error('Routes API returned invalid distance/duration');
  }
  return {
    distanceMeters,
    durationSeconds,
    distanceText: formatDistanceText(distanceMeters),
    durationText: formatDurationText(durationSeconds),
  };
}

/**
 * @param {{ address?: string, latitude?: number, longitude?: number }} origin
 * @param {string} destinationAddress
 * @param {string} apiKey
 */
async function fetchDrivingMatrix(origin, destinationAddress, apiKey) {
  const originAddress = normalizeString(origin?.address);
  const originLatitude = asFiniteNumber(origin?.latitude);
  const originLongitude = asFiniteNumber(origin?.longitude);
  const hasOriginAddress = originAddress.length > 0;
  const hasOriginLatLng = originLatitude != null && originLongitude != null;
  if (!hasOriginAddress && !hasOriginLatLng) {
    throw new Error('Origin is missing');
  }

  const originPayload = hasOriginAddress
    ? { address: originAddress }
    : {
        location: {
          latLng: {
            latitude: originLatitude,
            longitude: originLongitude,
          },
        },
      };

  const res = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration',
    },
    body: JSON.stringify({
      origin: originPayload,
      destination: { address: destinationAddress },
      travelMode: 'DRIVE',
      routingPreference: 'TRAFFIC_UNAWARE',
      units: 'METRIC',
      languageCode: 'fr-FR',
    }),
  });
  const data = await res.json();
  if (!res.ok) {
    const message = normalizeString(data?.error?.message) || `HTTP ${res.status}`;
    throw new Error(message);
  }
  return parseRoutesApiResponse(data);
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
 * @param {FirebaseFirestore.DocumentReference} docRef
 * @param {string} tripAddress
 * @param {string} activityAddress
 * @param {string} apiKey
 */
async function writeTripDrivingRouteForActivity(
  docRef,
  tripAddress,
  activityAddress,
  apiKey
) {
  if (!activityAddress) {
    await docRef.set({ tripDrivingRoute: FieldValue.delete() }, { merge: true });
    return;
  }

  if (!tripAddress) {
    await docRef.set(
      {
        tripDrivingRoute: {
          status: 'missing_trip_address',
          calculatedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );
    return;
  }

  try {
    const result = await fetchDrivingMatrix(
      { address: tripAddress },
      activityAddress,
      apiKey
    );
    if (result.elementStatus) {
      await docRef.set(
        {
          tripDrivingRoute: {
            status: 'no_result',
            detail: result.elementStatus,
            calculatedAt: FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
      return;
    }

    await docRef.set(
      {
        tripDrivingRoute: {
          status: 'ok',
          distanceMeters: result.distanceMeters,
          durationSeconds: result.durationSeconds,
          distanceText: result.distanceText,
          durationText: result.durationText,
          calculatedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );
  } catch (e) {
    await docRef.set(
      {
        tripDrivingRoute: {
          status: 'error',
          errorMessage: String(e),
          calculatedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );
  }
}

const computeActivityDrivingRouteFromTrip = onDocumentWritten(
  {
    document: 'trips/{tripId}/activities/{activityId}',
    timeoutSeconds: 60,
    memory: '256MiB',
    secrets: ['GOOGLE_PLACES_API_KEY'],
  },
  async (event) => {
    if (!event.data.after.exists) {
      return;
    }

    const before = event.data.before.exists ? event.data.before.data() || {} : {};
    const after = event.data.after.data() || {};
    const beforeAddr = normalizeString(before.address);
    const afterAddr = normalizeString(after.address);

    if (event.data.before.exists && beforeAddr === afterAddr) {
      return;
    }

    const apiKey = process.env.GOOGLE_PLACES_API_KEY;
    if (!apiKey) {
      console.error('computeActivityDrivingRouteFromTrip: GOOGLE_PLACES_API_KEY missing');
      return;
    }

    const tripId = event.params.tripId;
    const tripSnap = await admin.firestore().collection('trips').doc(tripId).get();
    const tripAddress = normalizeString(tripSnap.data()?.address);

    await writeTripDrivingRouteForActivity(
      event.data.after.ref,
      tripAddress,
      afterAddr,
      apiKey
    );
  }
);

const recomputeActivityDrivingRoutesOnTripAddressChange = onDocumentUpdated(
  {
    document: 'trips/{tripId}',
    timeoutSeconds: 120,
    memory: '512MiB',
    secrets: ['GOOGLE_PLACES_API_KEY'],
  },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const beforeAddr = normalizeString(before.address);
    const afterAddr = normalizeString(after.address);
    if (beforeAddr === afterAddr) {
      return;
    }

    const apiKey = process.env.GOOGLE_PLACES_API_KEY;
    if (!apiKey) {
      console.error(
        'recomputeActivityDrivingRoutesOnTripAddressChange: GOOGLE_PLACES_API_KEY missing'
      );
      return;
    }

    const tripId = event.params.tripId;
    const activitiesSnap = await admin
      .firestore()
      .collection('trips')
      .doc(tripId)
      .collection('activities')
      .get();

    for (const doc of activitiesSnap.docs) {
      const activityAddress = normalizeString(doc.data()?.address);
      if (!activityAddress) continue;
      await writeTripDrivingRouteForActivity(doc.ref, afterAddr, activityAddress, apiKey);
    }
  }
);

const refreshActivityDrivingRoute = onCall(
  { secrets: ['GOOGLE_PLACES_API_KEY'], timeoutSeconds: 60, memory: '256MiB' },
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

    const apiKey = process.env.GOOGLE_PLACES_API_KEY;
    if (!apiKey) {
      throw new HttpsError('failed-precondition', 'Clé API Google indisponible');
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
    const activityAddress = normalizeString(activityData.address);
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
        activityAddress,
        apiKey
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
    if (!activityAddress) {
      return {
        ok: true,
        route: { status: 'missing_activity_address' },
      };
    }

    try {
      const result = await fetchDrivingMatrix(
        { latitude, longitude },
        activityAddress,
        apiKey
      );
      if (result.elementStatus) {
        return {
          ok: true,
          route: {
            status: 'no_result',
            detail: result.elementStatus,
          },
        };
      }
      return {
        ok: true,
        route: {
          status: 'ok',
          distanceMeters: result.distanceMeters,
          durationSeconds: result.durationSeconds,
          distanceText: result.distanceText,
          durationText: result.durationText,
        },
      };
    } catch (e) {
      return {
        ok: true,
        route: {
          status: 'error',
          errorMessage: String(e),
        },
      };
    }
  }
);

module.exports = {
  computeActivityDrivingRouteFromTrip,
  recomputeActivityDrivingRoutesOnTripAddressChange,
  refreshActivityDrivingRoute,
  normalizeString,
  parseRoutesApiResponse,
  fetchDrivingMatrix,
  writeTripDrivingRouteForActivity,
};
