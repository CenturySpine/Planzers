// Planerz public API — v1.
//
// Two HTTP entry points served by a single Cloud Function (Gen2, region
// europe-west9, set via setGlobalOptions in index.js):
//   POST /oauth/token   — server-to-server code exchange (RFC 6749,
//                          authorization_code grant), delegated to the
//                          shared OAuth provider core (see
//                          functions/vendor/oauth-provider-core).
//   GET  /v1/trips       — returns the caller's non-archived trips
//                          (Planerz-specific business logic, stays here).
//
// Both are onRequest (plain HTTP), not onCall: this API is meant to be
// consumed by third-party backends (e.g. Ridgegear), not the Firebase
// client SDK.

const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const { onRequest } = require('firebase-functions/v2/https');
const { model, createTokenHandler } = require('./vendor/oauth-provider-core');

const { handleToken, setCors } = createTokenHandler(model);

/** `location` favors `destination`; falls back to `address` (day trips). */
function tripLocation(trip) {
  const destination = (trip.destination || '').trim();
  if (destination) return destination;
  return (trip.address || '').trim();
}

function isoDateOrNull(timestamp) {
  return timestamp && typeof timestamp.toDate === 'function'
    ? timestamp.toDate().toISOString().slice(0, 10)
    : null;
}

/** Pure mapping helper — kept separate from Firestore access for testability. */
function mapTripToApiShape(tripId, trip) {
  return {
    id: tripId,
    name: (trip.title || '').trim(),
    location: tripLocation(trip),
    startDate: isoDateOrNull(trip.startDate),
    endDate: isoDateOrNull(trip.endDate),
  };
}

async function handleTripsList(req, res) {
  const authHeader = req.get('Authorization') || '';
  const match = /^Bearer\s+(.+)$/i.exec(authHeader.trim());
  if (!match) {
    res.status(401).json({ error: 'unauthorized' });
    return;
  }

  const token = await model.getAccessToken(match[1].trim());
  if (!token || token.accessTokenExpiresAt.getTime() < Date.now()) {
    res.status(401).json({ error: 'unauthorized' });
    return;
  }
  if (!model.verifyScope(token, 'trips.read')) {
    res.status(403).json({ error: 'insufficient_scope' });
    return;
  }

  const db = admin.firestore();
  const uid = token.user.uid;

  const [tripsSnap, archivedSnap] = await Promise.all([
    db.collection('trips').where('memberUserIds', 'array-contains', uid).get(),
    db.collection('users').doc(uid).collection('archivedTrips').get(),
  ]);
  const archivedIds = new Set(archivedSnap.docs.map((doc) => doc.id));

  const trips = tripsSnap.docs
    .filter((doc) => !archivedIds.has(doc.id))
    .map((doc) => mapTripToApiShape(doc.id, doc.data()));

  const tokenHash = model.hashSecret(match[1].trim());
  Promise.all([
    db.collection('oauthAccessTokens').doc(tokenHash).set(
      { lastUsedAt: FieldValue.serverTimestamp() },
      { merge: true },
    ),
    db
      .collection('users')
      .doc(uid)
      .collection('connectedApps')
      .doc(token.client.id)
      .set({ lastUsedAt: FieldValue.serverTimestamp() }, { merge: true }),
  ]).catch(() => {
    // Best-effort bookkeeping; never block the response on it.
  });

  res.status(200).json({ trips });
}

exports.publicApi = onRequest(async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  const path = req.path || '/';
  if (path === '/oauth/token' && req.method === 'POST') {
    await handleToken(req, res);
    return;
  }
  if (path === '/v1/trips' && req.method === 'GET') {
    await handleTripsList(req, res);
    return;
  }

  res.status(404).json({ error: 'not_found' });
});

exports.mapTripToApiShape = mapTripToApiShape;
