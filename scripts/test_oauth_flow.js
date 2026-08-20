'use strict';

/**
 * test_oauth_flow.js
 *
 * Dérive automatiquement tout le flux OAuth de l'API publique Planerz
 * (enregistrement d'un client de test, connexion d'un utilisateur de test,
 * consentement, échange du code, appel à /v1/trips) contre les émulateurs
 * Firebase — aucune application partenaire (Ridgegear) requise.
 *
 * Avec --self-referential-client, enchaîne une seconde passe qui valide
 * cette fois le sens inverse (Planerz agissant comme *client* OAuth d'un
 * fournisseur externe) en utilisant Planerz lui-même comme "fournisseur de
 * test" — même principe, toujours sans dépendance externe.
 *
 * Prérequis : lancer les émulateurs dans un autre terminal, à la racine du
 * repo :
 *   firebase emulators:start --only auth,firestore,functions
 *
 * Usage :
 *   node test_oauth_flow.js [--project planerz] [--cleanup] [--self-referential-client]
 *
 * Ce script ne parle jamais qu'aux émulateurs locaux (hosts codés en dur
 * ci-dessous) — il ne peut pas toucher un projet Firebase réel.
 */

const crypto = require('crypto');

const PROJECT_ID = argValue('--project') || 'planerz';
const CLEANUP = process.argv.includes('--cleanup');
const SELF_REFERENTIAL_CLIENT = process.argv.includes('--self-referential-client');

const AUTH_EMULATOR_HOST = 'localhost:9099';
const FIRESTORE_EMULATOR_HOST = 'localhost:8080';
const FUNCTIONS_ORIGIN = `http://localhost:5001/${PROJECT_ID}/europe-west9`;

const TEST_CLIENT_ID = 'test-client';
const TEST_CLIENT_SECRET = 'test-secret-do-not-use-in-prod';
const TEST_REDIRECT_URI = 'https://example.com/callback';
const TEST_USER_EMAIL = 'oauth-flow-test@example.com';
const TEST_USER_PASSWORD = 'Test-Password-123!';

// --self-referential-client: Planerz-as-client, tested against Planerz's
// own provider endpoints (see functions/external_providers.js and
// functions/oauth_authorize.js) — no external app needed.
const SELFTEST_PROVIDER_ID = 'planerz-selftest';
const SELFTEST_CLIENT_ID = 'planerz-selftest-client';
const SELFTEST_CLIENT_SECRET = 'selftest-secret-do-not-use-in-prod';
// Never actually fetched by beginExternalConnection (only used to build a
// URL this script deliberately doesn't follow — see step 8) — just needs to
// pass validation.
const SELFTEST_AUTHORIZE_URL = 'https://example.com/oauth/authorize';
const SELFTEST_TOKEN_URL = `${FUNCTIONS_ORIGIN}/publicApi/oauth/token`;
const SELFTEST_REDIRECT_URI = 'http://localhost:5960/external/callback';

function argValue(flag) {
  const idx = process.argv.indexOf(flag);
  return idx >= 0 ? process.argv[idx + 1] : null;
}

function hashSecret(secret) {
  return crypto.createHash('sha256').update(secret, 'utf8').digest('hex');
}

function log(step, message) {
  console.log(`\n[${step}] ${message}`);
}

async function ensureTestUser() {
  const base = `http://${AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts`;
  const body = {
    email: TEST_USER_EMAIL,
    password: TEST_USER_PASSWORD,
    returnSecureToken: true,
  };

  let res = await fetch(`${base}:signInWithPassword?key=fake-api-key`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    res = await fetch(`${base}:signUp?key=fake-api-key`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  }

  const data = await res.json();
  if (!res.ok) {
    throw new Error(`Échec connexion/création utilisateur de test : ${JSON.stringify(data)}`);
  }
  return { uid: data.localId, idToken: data.idToken };
}

async function callCallable(name, idToken, data) {
  const res = await fetch(`${FUNCTIONS_ORIGIN}/${name}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ data }),
  });
  const json = await res.json();
  if (!res.ok || json.error) {
    throw new Error(`Callable ${name} a échoué : ${JSON.stringify(json)}`);
  }
  return json.result;
}

async function main() {
  process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_EMULATOR_HOST;
  process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_EMULATOR_HOST;
  process.env.GCLOUD_PROJECT = PROJECT_ID;

  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: PROJECT_ID });
  }
  const db = admin.firestore();

  log('1/6', `Enregistrement du client OAuth de test "${TEST_CLIENT_ID}"...`);
  await db.collection('oauthClients').doc(TEST_CLIENT_ID).set({
    displayName: 'Client de test',
    iconUrl: '',
    redirectUris: [TEST_REDIRECT_URI],
    scopesAllowed: ['trips.read'],
    clientSecretHash: hashSecret(TEST_CLIENT_SECRET),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  log('2/6', `Connexion de l'utilisateur de test (${TEST_USER_EMAIL})...`);
  const { uid, idToken } = await ensureTestUser();
  console.log(`  uid = ${uid}`);

  log('3/6', 'Création d\'un voyage de test appartenant à cet utilisateur...');
  const tripRef = db.collection('trips').doc();
  await tripRef.set({
    title: 'Voyage de test OAuth',
    destination: 'Chamonix',
    address: '',
    ownerId: uid,
    memberUserIds: [uid],
    startDate: admin.firestore.Timestamp.fromDate(new Date('2026-08-20')),
    endDate: admin.firestore.Timestamp.fromDate(new Date('2026-08-25')),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`  tripId = ${tripRef.id}`);

  log('4/6', 'Simulation du clic "Autoriser" sur l\'écran de consentement...');
  const { redirectUrl } = await callCallable('authorizeOAuthClient', idToken, {
    clientId: TEST_CLIENT_ID,
    redirectUri: TEST_REDIRECT_URI,
    scope: 'trips.read',
    state: 'script-test',
  });
  const code = new URL(redirectUrl).searchParams.get('code');
  if (!code) {
    throw new Error(`Pas de code dans l'URL de redirection : ${redirectUrl}`);
  }
  console.log(`  redirectUrl = ${redirectUrl}`);
  console.log(`  code = ${code}`);

  log('5/6', 'Échange du code contre un jeton d\'accès (POST /oauth/token)...');
  const tokenRes = await fetch(`${FUNCTIONS_ORIGIN}/publicApi/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      client_id: TEST_CLIENT_ID,
      client_secret: TEST_CLIENT_SECRET,
      redirect_uri: TEST_REDIRECT_URI,
    }).toString(),
  });
  const tokenJson = await tokenRes.json();
  if (!tokenRes.ok) {
    throw new Error(`Échange du code échoué : ${JSON.stringify(tokenJson)}`);
  }
  console.log(`  access_token = ${tokenJson.access_token}`);
  console.log(`  expires_in = ${tokenJson.expires_in}s`);

  log('6/6', 'Appel de GET /v1/trips avec le jeton obtenu...');
  const tripsRes = await fetch(`${FUNCTIONS_ORIGIN}/publicApi/v1/trips`, {
    headers: { Authorization: `Bearer ${tokenJson.access_token}` },
  });
  const tripsJson = await tripsRes.json();
  if (!tripsRes.ok) {
    throw new Error(`Appel /v1/trips échoué : ${JSON.stringify(tripsJson)}`);
  }
  console.log(JSON.stringify(tripsJson, null, 2));

  const found = (tripsJson.trips || []).some((t) => t.id === tripRef.id);
  if (!found) {
    throw new Error('Le voyage de test créé n\'apparaît pas dans la réponse de l\'API.');
  }

  if (SELF_REFERENTIAL_CLIENT) {
    await runSelfReferentialClientFlow({ db, uid, idToken });
  }

  if (CLEANUP) {
    log('cleanup', 'Suppression des données de test...');
    await tripRef.delete();
    await db.collection('oauthClients').doc(TEST_CLIENT_ID).delete();
    if (SELF_REFERENTIAL_CLIENT) {
      await db.collection('oauthClients').doc(SELFTEST_CLIENT_ID).delete();
      await db.collection('externalProviders').doc(SELFTEST_PROVIDER_ID).delete();
    }
  }

  console.log('\n✅ Flux OAuth complet validé de bout en bout.');
}

/**
 * Validates the mirror-image flow — Planerz acting as an OAuth *client* —
 * using Planerz's own provider endpoints as a stand-in "external" provider.
 * Exercises: admin provider registration (incl. the Secret Manager
 * emulator fallback), beginExternalConnection's authorize-URL + `state`
 * construction, a simulated provider consent (Planerz's own
 * authorizeOAuthClient), completeExternalConnection's real fetch()-based
 * token exchange against Planerz's own /oauth/token, storage, and revoke.
 */
async function runSelfReferentialClientFlow({ db, uid, idToken }) {
  const admin = require('firebase-admin');

  log('7/13', 'Passage secondaire : Planerz comme client OAuth (--self-referential-client)');

  log('8/13', "Élévation temporaire de l'utilisateur de test en admin (isApplicationOwner)...");
  await db.collection('users').doc(uid).set({ isApplicationOwner: true }, { merge: true });

  log('9/13', `Enregistrement du client OAuth "${SELFTEST_CLIENT_ID}" côté fournisseur (Planerz lui-même)...`);
  await db.collection('oauthClients').doc(SELFTEST_CLIENT_ID).set({
    displayName: 'Client de test (auto-référentiel)',
    iconUrl: '',
    redirectUris: [SELFTEST_REDIRECT_URI],
    scopesAllowed: ['selftest.read'],
    clientSecretHash: hashSecret(SELFTEST_CLIENT_SECRET),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  log('10/13', `Enregistrement du fournisseur "${SELFTEST_PROVIDER_ID}" via l'écran admin (createExternalProvider)...`);
  await callCallable('createExternalProvider', idToken, {
    providerId: SELFTEST_PROVIDER_ID,
    displayName: 'Fournisseur de test (Planerz lui-même)',
    iconUrl: '',
    authorizeUrl: SELFTEST_AUTHORIZE_URL,
    tokenUrl: SELFTEST_TOKEN_URL,
    scope: 'selftest.read',
    clientId: SELFTEST_CLIENT_ID,
    clientSecret: SELFTEST_CLIENT_SECRET,
  });
  console.log('  (secret écrit via le repli émulateur — pas de vrai Secret Manager en local)');

  log('11/13', "Démarrage de la connexion (beginExternalConnection)...");
  const { authorizeUrl } = await callCallable('beginExternalConnection', idToken, {
    providerId: SELFTEST_PROVIDER_ID,
    redirectUri: SELFTEST_REDIRECT_URI,
  });
  const state = new URL(authorizeUrl).searchParams.get('state');
  if (!state) {
    throw new Error(`Pas de state dans l'URL d'autorisation renvoyée : ${authorizeUrl}`);
  }
  console.log(`  authorizeUrl = ${authorizeUrl} (non suivie, cf. commentaire du script)`);
  console.log(`  state = ${state}`);

  log('12/13', "Simulation du consentement côté fournisseur (authorizeOAuthClient)...");
  const { redirectUrl } = await callCallable('authorizeOAuthClient', idToken, {
    clientId: SELFTEST_CLIENT_ID,
    redirectUri: SELFTEST_REDIRECT_URI,
    scope: 'selftest.read',
    state,
  });
  const code = new URL(redirectUrl).searchParams.get('code');
  if (!code) {
    throw new Error(`Pas de code dans l'URL de redirection : ${redirectUrl}`);
  }
  console.log(`  code = ${code}`);

  log('13/13', "Échange du code (completeExternalConnection, fetch() réel vers /oauth/token)...");
  await callCallable('completeExternalConnection', idToken, {
    providerId: SELFTEST_PROVIDER_ID,
    code,
    state,
  });

  const tokenId = hashSecret(`${SELFTEST_PROVIDER_ID}:${uid}`);
  const tokenSnap = await db.collection('externalProviderTokens').doc(tokenId).get();
  if (!tokenSnap.exists) {
    throw new Error('externalProviderTokens absent après completeExternalConnection.');
  }
  const mirrorSnap = await db
    .collection('users')
    .doc(uid)
    .collection('connectedExternalProviders')
    .doc(SELFTEST_PROVIDER_ID)
    .get();
  if (!mirrorSnap.exists) {
    throw new Error('connectedExternalProviders (miroir utilisateur) absent après completeExternalConnection.');
  }
  console.log('  jeton stocké + miroir utilisateur confirmés');

  await callCallable('revokeExternalConnection', idToken, { providerId: SELFTEST_PROVIDER_ID });
  const tokenAfterRevoke = await db.collection('externalProviderTokens').doc(tokenId).get();
  const mirrorAfterRevoke = await db
    .collection('users')
    .doc(uid)
    .collection('connectedExternalProviders')
    .doc(SELFTEST_PROVIDER_ID)
    .get();
  if (tokenAfterRevoke.exists || mirrorAfterRevoke.exists) {
    throw new Error('revokeExternalConnection n\'a pas nettoyé le jeton et/ou le miroir utilisateur.');
  }
  console.log('  révocation confirmée (jeton + miroir supprimés)');

  console.log('\n✅ Flux "Planerz comme client OAuth" validé de bout en bout.');
}

main().catch((error) => {
  console.error(`\n❌ ${error.message}`);
  process.exit(1);
});
