// Planerz as an OAuth 2.0 *client* of external ecosystem providers
// (Ridgegear, a future "Killer" party-game app, ...) — mirror image of
// oauth_authorize.js / public_api.js, where Planerz is the provider.
//
// Scope of this file: letting a user connect their account with a
// registered provider, and letting an admin manage the provider registry.
// What a connected token is later used for (e.g. showing trip modules) is
// explicitly out of scope here.

const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');
const { model } = require('./vendor/oauth-provider-core');
const { insertApplicationLog } = require('./application_logs');

const { generateSecret, hashSecret } = model;

const PENDING_CONNECTION_LIFETIME_MS = 10 * 60 * 1000; // 10 minutes

const secretClient = new SecretManagerServiceClient();

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

function getProjectId() {
  return (
    process.env.GCLOUD_PROJECT ||
    process.env.GCP_PROJECT ||
    admin.app().options.projectId
  );
}

// Google Cloud Secret Manager has no local emulator, and neither does an
// arbitrary external provider's HTTPS endpoint — the self-referential test
// setup (see scripts/test_oauth_flow.js) points `tokenUrl` at Planerz's own
// emulator, which is only reachable over plain http://localhost. When
// running under `firebase emulators:start` (FUNCTIONS_EMULATOR is set by
// the Functions emulator itself), relax both the Secret Manager calls and
// the https/localhost SSRF checks below — neither relaxation is reachable
// in a deployed environment.
function isEmulatorRuntime() {
  return process.env.FUNCTIONS_EMULATOR === 'true';
}

// --- SSRF hardening for admin-entered provider URLs -------------------

const DENIED_HOSTNAMES = new Set([
  'localhost',
  '127.0.0.1',
  '0.0.0.0',
  '169.254.169.254', // cloud metadata server
  '::1',
]);

function isPrivateIpv4(hostname) {
  const parts = hostname.split('.').map((p) => Number(p));
  if (parts.length !== 4 || parts.some((p) => !Number.isInteger(p))) {
    return false;
  }
  const [a, b] = parts;
  return a === 10 || a === 127 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
}

/** Throws if `rawUrl` isn't a well-formed https:// URL pointing outside the local/internal network. */
function assertSafeProviderUrl(rawUrl, fieldLabel) {
  const value = normalizeString(rawUrl);
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new HttpsError('invalid-argument', `${fieldLabel} invalide`);
  }
  if (isEmulatorRuntime()) {
    // Local testing only (see comment above isEmulatorRuntime): allow
    // plain http:// against localhost so a self-referential test provider
    // can point at Planerz's own emulator endpoints.
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      throw new HttpsError('invalid-argument', `${fieldLabel} invalide`);
    }
    return url;
  }
  if (url.protocol !== 'https:') {
    throw new HttpsError('invalid-argument', `${fieldLabel} doit être en https`);
  }
  const hostname = url.hostname.toLowerCase();
  if (DENIED_HOSTNAMES.has(hostname) || isPrivateIpv4(hostname)) {
    throw new HttpsError('invalid-argument', `${fieldLabel} pointe vers un hôte non autorisé`);
  }
  return url;
}

const PROVIDER_ID_PATTERN = /^[a-z][a-z0-9-]{1,63}$/;

function secretIdFor(providerId) {
  return `extprov-${providerId}-client-secret`;
}

/**
 * Writes (creating if necessary) the latest version of a provider's client
 * secret. `providerRef` is only used by the emulator fallback.
 */
async function writeProviderSecret({ providerRef, secretId, clientSecretValue }) {
  if (isEmulatorRuntime()) {
    await providerRef.set({ _emulatorOnlyClientSecret: clientSecretValue }, { merge: true });
    return;
  }

  const projectId = getProjectId();
  const parent = `projects/${projectId}`;
  const secretName = `${parent}/secrets/${secretId}`;

  try {
    await secretClient.getSecret({ name: secretName });
  } catch (error) {
    if (error.code !== 5 /* NOT_FOUND */) throw error;
    await secretClient.createSecret({
      parent,
      secretId,
      secret: { replication: { automatic: {} } },
    });
  }

  await secretClient.addSecretVersion({
    parent: secretName,
    payload: { data: Buffer.from(clientSecretValue, 'utf8') },
  });
}

/**
 * Reads a provider's client secret. `providerData` (the already-loaded
 * `externalProviders` doc) is only used by the emulator fallback.
 */
async function readProviderSecret({ providerData, secretId }) {
  if (isEmulatorRuntime()) {
    const value = providerData?._emulatorOnlyClientSecret;
    if (typeof value !== 'string' || !value) {
      throw new Error('Secret indisponible en mode émulateur pour ce fournisseur');
    }
    return value;
  }

  const projectId = getProjectId();
  const versionName = `projects/${projectId}/secrets/${secretId}/versions/latest`;
  const [version] = await secretClient.accessSecretVersion({ name: versionName });
  return version.payload.data.toString('utf8');
}

// --- User-facing: browse + connect -------------------------------------

/** Public-safe list of registered providers for the "connect" screen. */
exports.listExternalProviders = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }
  const snap = await admin.firestore().collection('externalProviders').get();
  return {
    providers: snap.docs.map((doc) => {
      const data = doc.data();
      return {
        providerId: doc.id,
        displayName: data.displayName || doc.id,
        iconUrl: data.iconUrl || '',
        scope: data.scope || '',
      };
    }),
  };
});

/**
 * Starts a connection to an external provider: creates a short-lived,
 * single-use anti-CSRF `state` and returns the full authorize URL to
 * navigate the browser to.
 */
exports.beginExternalConnection = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }

  const providerId = normalizeString(request.data?.providerId);
  const redirectUri = normalizeString(request.data?.redirectUri);
  if (!providerId || !redirectUri) {
    throw new HttpsError('invalid-argument', 'Paramètres de connexion invalides');
  }

  const providerSnap = await admin.firestore().collection('externalProviders').doc(providerId).get();
  if (!providerSnap.exists) {
    throw new HttpsError('not-found', 'Fournisseur inconnu');
  }
  const provider = providerSnap.data();
  const authorizeUrl = assertSafeProviderUrl(provider.authorizeUrl, "L'URL d'autorisation du fournisseur");

  const state = generateSecret(24);
  await admin.firestore().collection('pendingExternalConnections').doc(state).set({
    state,
    providerId,
    uid,
    redirectUri,
    expiresAt: Timestamp.fromMillis(Date.now() + PENDING_CONNECTION_LIFETIME_MS),
    used: false,
    createdAt: FieldValue.serverTimestamp(),
  });

  authorizeUrl.searchParams.set('client_id', provider.clientId);
  authorizeUrl.searchParams.set('redirect_uri', redirectUri);
  if (provider.scope) {
    authorizeUrl.searchParams.set('scope', provider.scope);
  }
  authorizeUrl.searchParams.set('state', state);

  return { authorizeUrl: authorizeUrl.toString() };
});

/**
 * Completes a connection once the provider has redirected the browser back
 * to Planerz: validates the pending state, exchanges the code for a token
 * server-to-server, and stores it.
 */
exports.completeExternalConnection = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }

  const providerId = normalizeString(request.data?.providerId);
  const code = normalizeString(request.data?.code);
  const state = normalizeString(request.data?.state);
  if (!providerId || !code || !state) {
    throw new HttpsError('invalid-argument', "Paramètres de retour d'autorisation invalides");
  }

  const db = admin.firestore();
  const pendingRef = db.collection('pendingExternalConnections').doc(state);
  const pendingSnap = await pendingRef.get();
  if (!pendingSnap.exists) {
    throw new HttpsError('failed-precondition', 'Requête de connexion inconnue ou expirée');
  }
  const pending = pendingSnap.data();
  if (
    pending.used ||
    pending.uid !== uid ||
    pending.providerId !== providerId ||
    pending.expiresAt.toMillis() < Date.now()
  ) {
    throw new HttpsError('failed-precondition', 'Requête de connexion invalide ou expirée');
  }
  // Single-use: mark consumed before doing anything else, even if the
  // exchange below fails.
  await pendingRef.set({ used: true }, { merge: true });

  const providerSnap = await db.collection('externalProviders').doc(providerId).get();
  if (!providerSnap.exists) {
    throw new HttpsError('not-found', 'Fournisseur inconnu');
  }
  const provider = providerSnap.data();
  const tokenUrl = assertSafeProviderUrl(provider.tokenUrl, "L'URL de jeton du fournisseur");

  let clientSecret;
  try {
    clientSecret = await readProviderSecret({
      providerData: provider,
      secretId: provider.clientSecretName,
    });
  } catch (error) {
    await insertApplicationLog(db, {
      level: 'error',
      source: 'external_providers',
      message: `Secret manquant pour le fournisseur ${providerId}`,
      details: { providerId, error: error.message },
    });
    throw new HttpsError('failed-precondition', 'Configuration du fournisseur incomplète');
  }

  let tokenJson;
  try {
    const res = await fetch(tokenUrl.toString(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        client_id: provider.clientId,
        client_secret: clientSecret,
        redirect_uri: pending.redirectUri,
      }).toString(),
    });
    tokenJson = await res.json();
    if (!res.ok) {
      throw new Error(tokenJson?.error_description || tokenJson?.error || `HTTP ${res.status}`);
    }
  } catch (error) {
    await insertApplicationLog(db, {
      level: 'error',
      source: 'external_providers',
      message: `Échange de jeton échoué pour ${providerId}`,
      details: { providerId, uid, error: error.message },
    });
    throw new HttpsError('internal', "Échec de la connexion au fournisseur");
  }

  const accessToken = normalizeString(tokenJson.access_token);
  if (!accessToken) {
    throw new HttpsError('internal', 'Réponse de jeton invalide du fournisseur');
  }
  const refreshToken = normalizeString(tokenJson.refresh_token) || null;
  const expiresInSeconds = Number(tokenJson.expires_in);
  const accessTokenExpiresAt = Number.isFinite(expiresInSeconds)
    ? Timestamp.fromMillis(Date.now() + expiresInSeconds * 1000)
    : null;
  const scope = normalizeString(tokenJson.scope) || provider.scope || '';

  const tokenId = hashSecret(`${providerId}:${uid}`);
  const batch = db.batch();
  batch.set(db.collection('externalProviderTokens').doc(tokenId), {
    providerId,
    uid,
    accessToken,
    accessTokenHash: hashSecret(accessToken),
    refreshToken,
    accessTokenExpiresAt,
    scope,
    createdAt: FieldValue.serverTimestamp(),
    lastUsedAt: FieldValue.serverTimestamp(),
  });
  batch.set(
    db.collection('users').doc(uid).collection('connectedExternalProviders').doc(providerId),
    {
      providerDisplayName: provider.displayName || providerId,
      providerIconUrl: provider.iconUrl || '',
      scope,
      connectedAt: FieldValue.serverTimestamp(),
      lastUsedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await batch.commit();

  return { connected: true };
});

/**
 * Disconnects a provider from the caller's account. Cannot force the
 * provider to invalidate the token on their end — that would require the
 * provider to also expose its own revocation endpoint, which is a known
 * limitation, not solved here.
 */
exports.revokeExternalConnection = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }
  const providerId = normalizeString(request.data?.providerId);
  if (!providerId) {
    throw new HttpsError('invalid-argument', 'providerId manquant');
  }

  const db = admin.firestore();
  const tokenId = hashSecret(`${providerId}:${uid}`);
  const batch = db.batch();
  batch.delete(db.collection('externalProviderTokens').doc(tokenId));
  batch.delete(db.collection('users').doc(uid).collection('connectedExternalProviders').doc(providerId));
  await batch.commit();

  return { revoked: true, providerRevokeSupported: false };
});

// --- Administration-only: provider registry -----------------------------

/**
 * Registers a new external provider. Writes the client secret straight
 * into Secret Manager (never into Firestore) — no CLI, no redeploy needed
 * to add a provider.
 */
exports.createExternalProvider = onCall(async (request) => {
  await requireApplicationOwner(request.auth?.uid);

  const providerId = normalizeString(request.data?.providerId).toLowerCase();
  const displayName = normalizeString(request.data?.displayName);
  const iconUrl = normalizeString(request.data?.iconUrl);
  const authorizeUrlRaw = normalizeString(request.data?.authorizeUrl);
  const tokenUrlRaw = normalizeString(request.data?.tokenUrl);
  const scope = normalizeString(request.data?.scope);
  const clientId = normalizeString(request.data?.clientId);
  const clientSecret = normalizeString(request.data?.clientSecret);

  if (!PROVIDER_ID_PATTERN.test(providerId)) {
    throw new HttpsError(
      'invalid-argument',
      'providerId doit être en minuscules, chiffres et tirets (ex. "ridgegear")',
    );
  }
  if (!displayName || !clientId || !clientSecret) {
    throw new HttpsError(
      'invalid-argument',
      'displayName, clientId et clientSecret sont requis',
    );
  }
  assertSafeProviderUrl(authorizeUrlRaw, "L'URL d'autorisation");
  assertSafeProviderUrl(tokenUrlRaw, "L'URL de jeton");

  const db = admin.firestore();
  const providerRef = db.collection('externalProviders').doc(providerId);
  if ((await providerRef.get()).exists) {
    throw new HttpsError('already-exists', 'Ce providerId existe déjà');
  }

  const secretId = secretIdFor(providerId);
  await providerRef.set({
    displayName,
    iconUrl,
    authorizeUrl: authorizeUrlRaw,
    tokenUrl: tokenUrlRaw,
    scope,
    clientId,
    clientSecretName: secretId,
    createdAt: FieldValue.serverTimestamp(),
  });
  await writeProviderSecret({ providerRef, secretId, clientSecretValue: clientSecret });

  return { providerId };
});

/** Administration-only: rotate a provider's client secret without recreating it. */
exports.updateExternalProviderSecret = onCall(async (request) => {
  await requireApplicationOwner(request.auth?.uid);

  const providerId = normalizeString(request.data?.providerId);
  const clientSecret = normalizeString(request.data?.clientSecret);
  if (!providerId || !clientSecret) {
    throw new HttpsError('invalid-argument', 'providerId et clientSecret sont requis');
  }

  const providerRef = admin.firestore().collection('externalProviders').doc(providerId);
  const providerSnap = await providerRef.get();
  if (!providerSnap.exists) {
    throw new HttpsError('not-found', 'Fournisseur inconnu');
  }
  const secretId = providerSnap.data().clientSecretName || secretIdFor(providerId);
  await writeProviderSecret({ providerRef, secretId, clientSecretValue: clientSecret });

  return { updated: true };
});

/** Administration-only: list registered external providers (no secrets). */
exports.listExternalProvidersAdmin = onCall(async (request) => {
  await requireApplicationOwner(request.auth?.uid);

  const snap = await admin.firestore().collection('externalProviders').get();
  return {
    providers: snap.docs.map((doc) => {
      const data = doc.data();
      return {
        providerId: doc.id,
        displayName: data.displayName || doc.id,
        iconUrl: data.iconUrl || '',
        authorizeUrl: data.authorizeUrl || '',
        tokenUrl: data.tokenUrl || '',
        scope: data.scope || '',
        clientId: data.clientId || '',
      };
    }),
  };
});

/** Administration-only: deregister an external provider. */
exports.deleteExternalProvider = onCall(async (request) => {
  await requireApplicationOwner(request.auth?.uid);
  const providerId = normalizeString(request.data?.providerId);
  if (!providerId) {
    throw new HttpsError('invalid-argument', 'providerId manquant');
  }

  const db = admin.firestore();
  const providerSnap = await db.collection('externalProviders').doc(providerId).get();
  const secretId = providerSnap.exists
    ? providerSnap.data().clientSecretName
    : null;

  await db.collection('externalProviders').doc(providerId).delete();

  if (secretId && !isEmulatorRuntime()) {
    try {
      const projectId = getProjectId();
      await secretClient.deleteSecret({ name: `projects/${projectId}/secrets/${secretId}` });
    } catch {
      // Best-effort cleanup; a leftover unused secret isn't a correctness
      // issue, never block the response on it.
    }
  }

  return { deleted: true };
});

exports._internal = {
  assertSafeProviderUrl,
  isPrivateIpv4,
  secretIdFor,
  PROVIDER_ID_PATTERN,
  PENDING_CONNECTION_LIFETIME_MS,
};
