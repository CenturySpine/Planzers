const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { generateSecret, hashSecret } = require('./oauth/model');

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

async function requireApplicationOwner(uid) {
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }
  const snap = await admin.firestore().collection('users').doc(uid).get();
  const userData = snap.exists ? snap.data() || {} : {};
  if (userData.isApplicationOwner !== true) {
    throw new HttpsError('permission-denied', 'Accès réservé aux administrateurs');
  }
}

/**
 * Public-safe lookup used by the Flutter consent screen before showing the
 * "Autoriser / Refuser" prompt. Never returns the client secret.
 */
exports.getOAuthClientPublicInfo = onCall(async (request) => {
  const clientId = normalizeString(request.data?.clientId);
  if (!clientId) {
    throw new HttpsError('invalid-argument', 'client_id manquant');
  }

  const snap = await admin.firestore().collection('oauthClients').doc(clientId).get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Application inconnue');
  }
  const data = snap.data();
  return {
    displayName: data.displayName || clientId,
    iconUrl: data.iconUrl || '',
    redirectUris: data.redirectUris || [],
    scopesAllowed: data.scopesAllowed || [],
  };
});

/**
 * Called by the Flutter consent screen once the signed-in user taps
 * "Autoriser". Creates a single-use, 60s-lived authorization code and
 * returns the full redirect URL for the Flutter app to navigate to.
 */
exports.authorizeOAuthClient = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }

  const clientId = normalizeString(request.data?.clientId);
  const redirectUri = normalizeString(request.data?.redirectUri);
  const scope = normalizeString(request.data?.scope) || 'trips.read';
  const state = normalizeString(request.data?.state);

  if (!clientId || !redirectUri) {
    throw new HttpsError('invalid-argument', 'Paramètres OAuth invalides');
  }

  const clientSnap = await admin.firestore().collection('oauthClients').doc(clientId).get();
  if (!clientSnap.exists) {
    throw new HttpsError('not-found', 'Application inconnue');
  }
  const client = clientSnap.data();
  if (!(client.redirectUris || []).includes(redirectUri)) {
    throw new HttpsError('invalid-argument', 'redirect_uri non autorisée pour cette application');
  }

  const code = generateSecret(24);
  await admin.firestore().collection('oauthAuthorizationCodes').doc(code).set({
    authorizationCode: code,
    expiresAt: Timestamp.fromMillis(Date.now() + 60_000),
    redirectUri,
    // @node-oauth/oauth2-server expects `scope` as a string array end-to-end
    // (it does `token.scope.join(' ')` when building its own responses).
    scope: scope.split(' ').filter(Boolean),
    clientId,
    uid,
    used: false,
    createdAt: FieldValue.serverTimestamp(),
  });

  const url = new URL(redirectUri);
  url.searchParams.set('code', code);
  if (state) {
    url.searchParams.set('state', state);
  }

  return { redirectUrl: url.toString() };
});

/**
 * Lets a Planerz user revoke a third-party app's access from their own
 * account (removes the access tokens too, not just the visible list entry).
 */
exports.revokeConnectedApp = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }
  const clientId = normalizeString(request.data?.clientId);
  if (!clientId) {
    throw new HttpsError('invalid-argument', 'client_id manquant');
  }

  const db = admin.firestore();
  const connectedRef = db
    .collection('users')
    .doc(uid)
    .collection('connectedApps')
    .doc(clientId);
  const connectedSnap = await connectedRef.get();
  if (!connectedSnap.exists) {
    return { revoked: false };
  }

  const tokenHashes = connectedSnap.data().tokenHashes || [];
  const batch = db.batch();
  for (const tokenHash of tokenHashes) {
    batch.delete(db.collection('oauthAccessTokens').doc(tokenHash));
  }
  batch.delete(connectedRef);
  await batch.commit();

  return { revoked: true };
});

/**
 * Administration-only: register a new OAuth client (e.g. Ridgegear) and
 * hand back its secret exactly once — it is never stored or shown again.
 */
exports.createOAuthClient = onCall(async (request) => {
  await requireApplicationOwner(request.auth?.uid);

  const clientId = normalizeString(request.data?.clientId);
  const displayName = normalizeString(request.data?.displayName);
  const iconUrl = normalizeString(request.data?.iconUrl);
  const redirectUris = Array.isArray(request.data?.redirectUris)
    ? request.data.redirectUris.map(normalizeString).filter(Boolean)
    : [];
  const scopesAllowed = Array.isArray(request.data?.scopesAllowed)
    ? request.data.scopesAllowed.map(normalizeString).filter(Boolean)
    : ['trips.read'];

  if (!clientId || !displayName || redirectUris.length === 0) {
    throw new HttpsError(
      'invalid-argument',
      'client_id, displayName et au moins une redirect URI sont requis',
    );
  }

  const clientRef = admin.firestore().collection('oauthClients').doc(clientId);
  if ((await clientRef.get()).exists) {
    throw new HttpsError('already-exists', 'Ce client_id existe déjà');
  }

  const clientSecret = generateSecret(32);
  await clientRef.set({
    displayName,
    iconUrl,
    redirectUris,
    scopesAllowed,
    clientSecretHash: hashSecret(clientSecret),
    createdAt: FieldValue.serverTimestamp(),
  });

  return { clientId, clientSecret };
});

/** Administration-only: list registered OAuth clients (no secrets). */
exports.listOAuthClients = onCall(async (request) => {
  await requireApplicationOwner(request.auth?.uid);

  const snap = await admin.firestore().collection('oauthClients').get();
  return {
    clients: snap.docs.map((doc) => {
      const data = doc.data();
      return {
        clientId: doc.id,
        displayName: data.displayName || doc.id,
        iconUrl: data.iconUrl || '',
        redirectUris: data.redirectUris || [],
        scopesAllowed: data.scopesAllowed || [],
      };
    }),
  };
});

/** Administration-only: deregister an OAuth client. */
exports.deleteOAuthClient = onCall(async (request) => {
  await requireApplicationOwner(request.auth?.uid);
  const clientId = normalizeString(request.data?.clientId);
  if (!clientId) {
    throw new HttpsError('invalid-argument', 'client_id manquant');
  }
  await admin.firestore().collection('oauthClients').doc(clientId).delete();
  return { deleted: true };
});
