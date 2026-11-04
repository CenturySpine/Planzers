'use strict';

/**
 * Trip membership guard for callables that act on a trip through the Admin
 * SDK (which bypasses Firestore rules). Mirrors `isTripMember` in
 * firestore.rules: the caller must be listed in `trips/{tripId}.memberUserIds`,
 * or be an application owner (`users/{uid}.isApplicationOwner`).
 */

const admin = require('firebase-admin');
const { HttpsError } = require('firebase-functions/v2/https');

const NOT_A_TRIP_MEMBER_MESSAGE = 'Tu ne fais pas partie de ce voyage';

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

/** True when `uid` is listed in the trip document's `memberUserIds`. */
function tripDataHasMember(tripData, uid) {
  const id = normalizeString(uid);
  if (!id || !tripData || !Array.isArray(tripData.memberUserIds)) return false;
  return tripData.memberUserIds.some((value) => normalizeString(value) === id);
}

/**
 * Throws `permission-denied` unless `uid` is a member of the trip or an
 * application owner. A missing trip is reported the same way as a trip the
 * caller does not belong to, so that trip ids cannot be probed.
 *
 * Reads the trip and the user profile in parallel, and returns
 * `isApplicationOwner` so callers do not have to read the profile again.
 *
 * @param {{ tripId: string, uid: string, db?: FirebaseFirestore.Firestore }} params
 * @returns {Promise<{ isApplicationOwner: boolean }>}
 */
async function assertTripMemberOrApplicationOwner({ tripId, uid, db = admin.firestore() }) {
  const [tripSnap, userSnap] = await Promise.all([
    db.collection('trips').doc(tripId).get(),
    db.collection('users').doc(uid).get(),
  ]);
  const isApplicationOwner = userSnap.exists && userSnap.data()?.isApplicationOwner === true;
  if (isApplicationOwner) {
    return { isApplicationOwner };
  }
  if (!tripSnap.exists || !tripDataHasMember(tripSnap.data(), uid)) {
    throw new HttpsError('permission-denied', NOT_A_TRIP_MEMBER_MESSAGE);
  }
  return { isApplicationOwner };
}

module.exports = {
  tripDataHasMember,
  assertTripMemberOrApplicationOwner,
  NOT_A_TRIP_MEMBER_MESSAGE,
};
