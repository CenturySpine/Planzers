'use strict';

/**
 * test_oauth_flow.js
 *
 * Dérive automatiquement tout le flux OAuth de l'API publique Planerz
 * (enregistrement d'un client de test, connexion d'un utilisateur de test,
 * consentement, échange du code, appel à /v1/trips) contre les émulateurs
 * Firebase — aucune application partenaire (Ridgegear) requise.
 *
 * Prérequis : lancer les émulateurs dans un autre terminal, à la racine du
 * repo :
 *   firebase emulators:start --only auth,firestore,functions
 *
 * Usage :
 *   node test_oauth_flow.js [--project planerz] [--cleanup]
 *
 * Ce script ne parle jamais qu'aux émulateurs locaux (hosts codés en dur
 * ci-dessous) — il ne peut pas toucher un projet Firebase réel.
 */

const crypto = require('crypto');

const PROJECT_ID = argValue('--project') || 'planerz';
const CLEANUP = process.argv.includes('--cleanup');

const AUTH_EMULATOR_HOST = 'localhost:9099';
const FIRESTORE_EMULATOR_HOST = 'localhost:8080';
const FUNCTIONS_ORIGIN = `http://localhost:5001/${PROJECT_ID}/europe-west9`;

const TEST_CLIENT_ID = 'test-client';
const TEST_CLIENT_SECRET = 'test-secret-do-not-use-in-prod';
const TEST_REDIRECT_URI = 'https://example.com/callback';
const TEST_USER_EMAIL = 'oauth-flow-test@example.com';
const TEST_USER_PASSWORD = 'Test-Password-123!';

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

  if (CLEANUP) {
    log('cleanup', 'Suppression des données de test...');
    await tripRef.delete();
    await db.collection('oauthClients').doc(TEST_CLIENT_ID).delete();
  }

  console.log('\n✅ Flux OAuth complet validé de bout en bout.');
}

main().catch((error) => {
  console.error(`\n❌ ${error.message}`);
  process.exit(1);
});
