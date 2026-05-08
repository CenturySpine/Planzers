const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const { HttpsError } = require('firebase-functions/v2/https');

// Per-feature quota limits.
// Mirrors lib/features/ai_quotas/data/ai_quota_config.dart — keep in sync.
const QUOTA_CONFIGS = {
  recipeIngredients: {
    perUserPerDay: 5,
    perTripPerDay: 10,
    perTripLifetime: 30,
    usesGrounding: true,
  },
  shoppingConsolidation: {
    perUserPerDay: 2,
    perTripPerDay: 3,
    perTripLifetime: 10,
    usesGrounding: false,
  },
};

const CIRCUIT_BREAKER_THRESHOLD = 50;

function todayUtcKey() {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Atomically checks and increments quota counters for the given feature,
 * user, and trip. Throws HttpsError('resource-exhausted', reason) if any
 * quota is exceeded:
 *   reason = 'quota-user' | 'quota-trip' | 'quota-trip-lifetime' | 'circuit-breaker'
 */
async function reserveQuota({ featureKey, tripId, uid }) {
  const config = QUOTA_CONFIGS[featureKey];
  if (!config) {
    throw new HttpsError('invalid-argument', `Unknown AI feature: ${featureKey}`);
  }

  const db = admin.firestore();
  const today = todayUtcKey();

  const userRef = db.collection('users').doc(uid).collection('aiQuotas').doc(featureKey);
  const tripRef = db.collection('trips').doc(tripId).collection('aiQuotas').doc(featureKey);
  const circuitRef = db.collection('system').doc('aiCircuitBreaker');

  await db.runTransaction(async (tx) => {
    const [userSnap, tripSnap, circuitSnap] = await Promise.all([
      tx.get(userRef),
      tx.get(tripRef),
      tx.get(circuitRef),
    ]);

    // --- Circuit breaker ---
    const circuitData = circuitSnap.exists ? circuitSnap.data() : {};
    const isCircuitTripped =
      circuitData.tripped === true && circuitData.manualOverride !== 'force_closed';
    if (isCircuitTripped) {
      throw new HttpsError('resource-exhausted', 'circuit-breaker');
    }

    // --- User quota (lazy daily reset) ---
    const userData = userSnap.exists ? userSnap.data() : {};
    const userDayKey = userData.currentDayKey || '';
    const userDayCount = userDayKey === today ? (userData.currentDayCount || 0) : 0;

    if (userDayCount >= config.perUserPerDay) {
      throw new HttpsError('resource-exhausted', 'quota-user');
    }

    // --- Trip quota (lazy daily reset + lifetime) ---
    const tripData = tripSnap.exists ? tripSnap.data() : {};
    const tripDayKey = tripData.currentDayKey || '';
    const tripDayCount = tripDayKey === today ? (tripData.currentDayCount || 0) : 0;
    const tripLifetimeCount = tripData.lifetimeCount || 0;

    if (tripDayCount >= config.perTripPerDay) {
      throw new HttpsError('resource-exhausted', 'quota-trip');
    }
    if (tripLifetimeCount >= config.perTripLifetime) {
      throw new HttpsError('resource-exhausted', 'quota-trip-lifetime');
    }

    // --- Increment user counters ---
    if (userDayKey !== today) {
      tx.set(userRef, {
        currentDayKey: today,
        currentDayCount: 1,
        lifetimeCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    } else {
      tx.set(userRef, {
        currentDayCount: FieldValue.increment(1),
        lifetimeCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    // --- Increment trip counters ---
    if (tripDayKey !== today) {
      tx.set(tripRef, {
        currentDayKey: today,
        currentDayCount: 1,
        lifetimeCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    } else {
      tx.set(tripRef, {
        currentDayCount: FieldValue.increment(1),
        lifetimeCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    // --- Circuit breaker: increment grounding counter (feature-specific) ---
    if (config.usesGrounding) {
      const circuitDayKey = circuitData.currentDayKey || '';
      const currentGrounding = circuitData.groundingCallsToday || 0;
      const newGrounding = (circuitDayKey === today ? currentGrounding : 0) + 1;
      const willTrip = newGrounding >= CIRCUIT_BREAKER_THRESHOLD;

      if (circuitDayKey !== today) {
        tx.set(circuitRef, {
          currentDayKey: today,
          groundingCallsToday: 1,
          tripped: willTrip,
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      } else {
        tx.set(circuitRef, {
          groundingCallsToday: FieldValue.increment(1),
          ...(willTrip ? { tripped: true } : {}),
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    }
  });
}

/**
 * Best-effort decrement of quota counters after an AI call failure.
 * Floors at 0. Does NOT decrement groundingCallsToday (conservative).
 */
async function refundQuota({ featureKey, tripId, uid }) {
  const db = admin.firestore();
  const today = todayUtcKey();

  const userRef = db.collection('users').doc(uid).collection('aiQuotas').doc(featureKey);
  const tripRef = db.collection('trips').doc(tripId).collection('aiQuotas').doc(featureKey);

  await db.runTransaction(async (tx) => {
    const [userSnap, tripSnap] = await Promise.all([
      tx.get(userRef),
      tx.get(tripRef),
    ]);

    const userData = userSnap.exists ? userSnap.data() : {};
    const tripData = tripSnap.exists ? tripSnap.data() : {};

    const userDayKey = userData.currentDayKey || '';
    const userDayCount = userDayKey === today ? (userData.currentDayCount || 0) : 0;
    const userLifetime = userData.lifetimeCount || 0;

    const tripDayKey = tripData.currentDayKey || '';
    const tripDayCount = tripDayKey === today ? (tripData.currentDayCount || 0) : 0;
    const tripLifetime = tripData.lifetimeCount || 0;

    tx.set(userRef, {
      currentDayCount: Math.max(0, userDayCount - 1),
      lifetimeCount: Math.max(0, userLifetime - 1),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    tx.set(tripRef, {
      currentDayCount: Math.max(0, tripDayCount - 1),
      lifetimeCount: Math.max(0, tripLifetime - 1),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

/**
 * Wraps an AI call with quota enforcement for CF-native features.
 * Application owners bypass all quota checks.
 *
 * Usage:
 *   const result = await withAiQuota(
 *     { featureKey: 'shoppingConsolidation', tripId, uid, isApplicationOwner },
 *     () => callTheAi()
 *   );
 */
async function withAiQuota({ featureKey, tripId, uid, isApplicationOwner }, callFn) {
  if (isApplicationOwner) return callFn();
  await reserveQuota({ featureKey, tripId, uid });
  try {
    return await callFn();
  } catch (e) {
    await refundQuota({ featureKey, tripId, uid }).catch(() => {});
    throw e;
  }
}

module.exports = { withAiQuota, reserveQuota, refundQuota, QUOTA_CONFIGS };
