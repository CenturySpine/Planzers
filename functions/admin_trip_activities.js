'use strict';

/**
 * Administration: deletes every activity of a trip (e.g. after tests of the
 * AI imports) and clears the links that pointed to them, like
 * scripts/delete_trip_activities.js but without any service account key:
 *   - travel documents of every traveler (`activityIds` / legacy
 *     `activityId` on `travelerModules/{uid}/walletDocuments`)
 *   - meals using a deleted restaurant (`restaurantActivityId`)
 *
 * Restricted to application owners (`users/{uid}.isApplicationOwner`).
 */

const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

const SAFE_SEGMENT = /^[A-Za-z0-9_-]+$/;
const BATCH_SIZE = 400;

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

async function requireApplicationOwner(uid) {
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }
  const snap = await admin.firestore().collection('users').doc(uid).get();
  if (!snap.exists || snap.data()?.isApplicationOwner !== true) {
    throw new HttpsError('permission-denied', 'Accès réservé aux administrateurs');
  }
}

/** `YYYY-MM-DD` from a stored trip date (ISO string or Timestamp), else ''. */
function tripDateOnly(raw) {
  if (raw && typeof raw.toDate === 'function') {
    // Stored as midnight in the device time zone: round to the nearest day.
    return new Date(raw.toDate().getTime() + 12 * 60 * 60 * 1000).toISOString().slice(0, 10);
  }
  const s = normalizeString(raw).slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : '';
}

/** Most recent start first, undated trips last. */
function compareTripsByStartDesc(a, b) {
  if (a.startDate !== b.startDate) {
    if (!a.startDate) return 1;
    if (!b.startDate) return -1;
    return a.startDate < b.startDate ? 1 : -1;
  }
  return a.title.localeCompare(b.title);
}

/**
 * Update removing the deleted activities from a travel document, or null when
 * it links none of them.
 * @param {object} data travel document
 * @param {Set<string>} deletedIds
 */
function walletLinksUpdate(data, deletedIds) {
  const ids = Array.isArray(data?.activityIds) ? data.activityIds.map(String) : [];
  const legacy = normalizeString(data?.activityId);
  const kept = ids.filter((id) => !deletedIds.has(id));
  const legacyDeleted = legacy !== '' && deletedIds.has(legacy);
  if (kept.length === ids.length && !legacyDeleted) return null;
  return {
    activityIds: kept.length === 0 ? FieldValue.delete() : kept,
    ...(legacyDeleted ? { activityId: FieldValue.delete() } : {}),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Whether the meal's restaurant is one of the deleted activities. */
function usesDeletedRestaurant(data, deletedIds) {
  const restaurantId = normalizeString(data?.restaurantActivityId);
  return restaurantId !== '' && deletedIds.has(restaurantId);
}

/**
 * Request: {}
 * Response: { trips: Array<{ tripId, title, startDate, endDate,
 *   activityCount }> } — most recent start first.
 */
const adminListTripActivityCounts = onCall(
  { timeoutSeconds: 120, memory: '256MiB' },
  async (request) => {
    await requireApplicationOwner(request.auth?.uid);
    const db = admin.firestore();
    const tripsSnap = await db.collection('trips').select('title', 'startDate', 'endDate').get();
    const trips = await Promise.all(
      tripsSnap.docs.map(async (doc) => {
        const data = doc.data() || {};
        const countSnap = await doc.ref.collection('activities').count().get();
        return {
          tripId: doc.id,
          title: normalizeString(data.title),
          startDate: tripDateOnly(data.startDate),
          endDate: tripDateOnly(data.endDate),
          activityCount: countSnap.data().count,
        };
      })
    );
    trips.sort(compareTripsByStartDesc);
    return { trips };
  }
);

/**
 * Request: { tripId: string, expectedActivityCount: number } — the count the
 * administrator confirmed; refused when activities were added or removed
 * since.
 * Response: { deletedCount, walletDocumentCount, mealCount }
 */
const adminDeleteTripActivities = onCall(
  { timeoutSeconds: 300, memory: '512MiB' },
  async (request) => {
    await requireApplicationOwner(request.auth?.uid);
    const tripId = normalizeString(request.data?.tripId);
    if (!SAFE_SEGMENT.test(tripId)) {
      throw new HttpsError('invalid-argument', 'tripId requis');
    }
    const expectedActivityCount = Number(request.data?.expectedActivityCount);

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const activitiesSnap = await tripRef.collection('activities').get();
    if (activitiesSnap.size !== expectedActivityCount) {
      throw new HttpsError(
        'failed-precondition',
        'Le nombre d’activités a changé : rafraîchis la liste et recommence.'
      );
    }
    const deletedIds = new Set(activitiesSnap.docs.map((d) => d.id));

    const linkUpdates = [];
    const travelerRefs = await tripRef.collection('travelerModules').listDocuments();
    for (const travelerRef of travelerRefs) {
      const walletSnap = await travelerRef.collection('walletDocuments').get();
      for (const doc of walletSnap.docs) {
        const update = walletLinksUpdate(doc.data(), deletedIds);
        if (update) linkUpdates.push({ ref: doc.ref, data: update });
      }
    }
    const walletDocumentCount = linkUpdates.length;
    const mealsSnap = await tripRef.collection('meals').get();
    for (const doc of mealsSnap.docs) {
      if (usesDeletedRestaurant(doc.data(), deletedIds)) {
        linkUpdates.push({ ref: doc.ref, data: { restaurantActivityId: '' } });
      }
    }
    const mealCount = linkUpdates.length - walletDocumentCount;

    // Links first, so an interrupted run never leaves links to missing
    // activities.
    const operations = [
      ...linkUpdates.map((u) => (batch) => batch.update(u.ref, u.data)),
      ...activitiesSnap.docs.map((doc) => (batch) => batch.delete(doc.ref)),
    ];
    for (let start = 0; start < operations.length; start += BATCH_SIZE) {
      const batch = db.batch();
      operations.slice(start, start + BATCH_SIZE).forEach((op) => op(batch));
      await batch.commit();
    }

    return { deletedCount: deletedIds.size, walletDocumentCount, mealCount };
  }
);

module.exports = {
  adminListTripActivityCounts,
  adminDeleteTripActivities,
  // Exposed for tests.
  tripDateOnly,
  compareTripsByStartDesc,
  walletLinksUpdate,
  usesDeletedRestaurant,
};
