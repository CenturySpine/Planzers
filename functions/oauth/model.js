// Firestore-backed model for @node-oauth/oauth2-server.
// Only the pieces needed for the `authorization_code` grant are implemented.
//
// Collections (Admin SDK only — closed to direct client access, see
// firestore.rules):
//   oauthClients/{clientId}            { displayName, iconUrl, redirectUris, clientSecretHash, scopesAllowed, createdAt }
//   oauthAuthorizationCodes/{code}      { authorizationCode, expiresAt, redirectUri, scope, clientId, uid }
//   oauthAccessTokens/{sha256(token)}   { accessToken, accessTokenExpiresAt, scope, clientId, uid }
//
// The library's "client" and "user" objects are kept intentionally thin —
// we only carry what the model functions themselves need.

const crypto = require('crypto');
const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const ACCESS_TOKEN_LIFETIME_SECONDS = 30 * 24 * 60 * 60; // 30 days (no refresh token in v1)
const AUTHORIZATION_CODE_LIFETIME_SECONDS = 60;

function db() {
  return admin.firestore();
}

function hashSecret(secret) {
  return crypto.createHash('sha256').update(secret, 'utf8').digest('hex');
}

function generateSecret(byteLength = 32) {
  return crypto.randomBytes(byteLength).toString('base64url');
}

/** oauth2-server calls this to validate a registered client + its redirect URI / secret. */
async function getClient(clientId, clientSecret) {
  const snap = await db().collection('oauthClients').doc(clientId).get();
  if (!snap.exists) return false;
  const data = snap.data();

  if (clientSecret != null && hashSecret(clientSecret) !== data.clientSecretHash) {
    return false;
  }

  return {
    id: clientId,
    grants: ['authorization_code'],
    redirectUris: data.redirectUris || [],
    scopesAllowed: data.scopesAllowed || [],
  };
}

/** Persists a freshly-issued authorization code (created after user consent). */
async function saveAuthorizationCode(code, client, user) {
  await db()
    .collection('oauthAuthorizationCodes')
    .doc(code.authorizationCode)
    .set({
      authorizationCode: code.authorizationCode,
      expiresAt: Timestamp.fromDate(code.expiresAt),
      redirectUri: code.redirectUri,
      scope: code.scope,
      clientId: client.id,
      uid: user.uid,
      used: false,
      createdAt: FieldValue.serverTimestamp(),
    });

  return {
    authorizationCode: code.authorizationCode,
    expiresAt: code.expiresAt,
    redirectUri: code.redirectUri,
    scope: code.scope,
    client: { id: client.id },
    user,
  };
}

/** Looks up a code for validation during the token exchange. */
async function getAuthorizationCode(authorizationCode) {
  const snap = await db()
    .collection('oauthAuthorizationCodes')
    .doc(authorizationCode)
    .get();
  if (!snap.exists) return false;
  const data = snap.data();
  if (data.used) return false;

  return {
    authorizationCode: data.authorizationCode,
    expiresAt: data.expiresAt.toDate(),
    redirectUri: data.redirectUri,
    scope: data.scope,
    client: { id: data.clientId },
    user: { uid: data.uid },
  };
}

/** Single-use enforcement: called right after a successful exchange. */
async function revokeAuthorizationCode(code) {
  await db()
    .collection('oauthAuthorizationCodes')
    .doc(code.authorizationCode)
    .set({ used: true }, { merge: true });
  return true;
}

/** Persists a freshly-minted access token and mirrors it to the user's connected-apps list. */
async function saveToken(token, client, user) {
  const tokenHash = hashSecret(token.accessToken);
  const batch = db().batch();

  batch.set(db().collection('oauthAccessTokens').doc(tokenHash), {
    accessTokenExpiresAt: Timestamp.fromDate(
      token.accessTokenExpiresAt,
    ),
    scope: token.scope,
    clientId: client.id,
    uid: user.uid,
    createdAt: FieldValue.serverTimestamp(),
    lastUsedAt: FieldValue.serverTimestamp(),
  });

  const clientSnap = await db().collection('oauthClients').doc(client.id).get();
  const clientData = clientSnap.exists ? clientSnap.data() : {};
  batch.set(
    db()
      .collection('users')
      .doc(user.uid)
      .collection('connectedApps')
      .doc(client.id),
    {
      clientDisplayName: clientData.displayName || client.id,
      clientIconUrl: clientData.iconUrl || '',
      scope: token.scope,
      connectedAt: FieldValue.serverTimestamp(),
      lastUsedAt: FieldValue.serverTimestamp(),
      tokenHashes: FieldValue.arrayUnion(tokenHash),
    },
    { merge: true },
  );

  await batch.commit();

  return {
    accessToken: token.accessToken,
    accessTokenExpiresAt: token.accessTokenExpiresAt,
    scope: token.scope,
    client: { id: client.id },
    user,
  };
}

/** Looks up an access token to authorize an incoming API request. */
async function getAccessToken(accessToken) {
  const tokenHash = hashSecret(accessToken);
  const snap = await db().collection('oauthAccessTokens').doc(tokenHash).get();
  if (!snap.exists) return false;
  const data = snap.data();

  return {
    accessToken,
    accessTokenExpiresAt: data.accessTokenExpiresAt.toDate(),
    scope: data.scope,
    client: { id: data.clientId },
    user: { uid: data.uid },
  };
}

function verifyScope(token, scope) {
  const granted = Array.isArray(token.scope)
    ? token.scope
    : (token.scope || '').split(' ').filter(Boolean);
  const requested = (scope || '').split(' ').filter(Boolean);
  return requested.every((s) => granted.includes(s));
}

module.exports = {
  ACCESS_TOKEN_LIFETIME_SECONDS,
  AUTHORIZATION_CODE_LIFETIME_SECONDS,
  hashSecret,
  generateSecret,
  getClient,
  saveAuthorizationCode,
  getAuthorizationCode,
  revokeAuthorizationCode,
  saveToken,
  getAccessToken,
  verifyScope,
};
