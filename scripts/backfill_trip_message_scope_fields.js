'use strict';

/**
 * backfill_trip_message_scope_fields.js
 *
 * Ajoute les champs threadType / visibilityType manquants sur les messages de
 * voyage existants pour permettre des requêtes Firestore filtrées par portée.
 *
 * Usage :
 *   node backfill_trip_message_scope_fields.js --key <service-account.json> [options]
 *
 * Options :
 *   --apply          Écriture réelle (par défaut : dry-run)
 *   --dry-run        Aperçu sans écriture (défaut)
 *   --verbose        Afficher les chemins des documents à corriger
 *   --trip <tripId>  Limiter au voyage indiqué
 */

const fs = require('fs');
const path = require('path');

function loadFirebaseAdmin() {
  try {
    return require('firebase-admin');
  } catch {
    return require(path.join(__dirname, 'migration', 'node_modules', 'firebase-admin'));
  }
}

const admin = loadFirebaseAdmin();

const BATCH_SIZE = 400;
const THREAD_TYPES = new Set(['main', 'admin', 'object']);
const VISIBILITY_TYPES = new Set(['trip_all', 'admins_only', 'object_participants']);

function parseArgs(argv) {
  const opts = {
    keyPath: '',
    apply: false,
    dryRun: true,
    verbose: false,
    tripId: '',
  };
  for (let i = 2; i < argv.length; i++) {
    const token = argv[i];
    if (token === '--apply') {
      opts.apply = true;
      opts.dryRun = false;
      continue;
    }
    if (token === '--dry-run') {
      opts.dryRun = true;
      opts.apply = false;
      continue;
    }
    if (token === '--verbose') {
      opts.verbose = true;
      continue;
    }
    if (!token.startsWith('--')) continue;

    const eqIdx = token.indexOf('=');
    const flag = eqIdx >= 0 ? token.slice(0, eqIdx) : token;
    const inlineVal = eqIdx >= 0 ? token.slice(eqIdx + 1) : null;
    const nextVal = inlineVal ?? argv[i + 1];
    const consume = () => {
      if (inlineVal === null) i++;
    };
    if (flag === '--key') {
      opts.keyPath = (nextVal || '').trim();
      consume();
    } else if (flag === '--trip') {
      opts.tripId = (nextVal || '').trim();
      consume();
    }
  }
  return opts;
}

function printUsageAndExit() {
  console.log(`
Usage:
  node backfill_trip_message_scope_fields.js --key <service-account.json> [options]

Required:
  --key <path>    Chemin vers le JSON du compte de service Firebase

Optional:
  --apply         Écriture réelle (par défaut : dry-run)
  --dry-run       Aperçu sans écriture
  --verbose       Afficher les documents à corriger
  --trip <id>     Limiter à trips/{tripId}/messages

Exemples:
  node backfill_trip_message_scope_fields.js --key ./planerz-PROD.json
  node backfill_trip_message_scope_fields.js --key ./planerz-PROD.json --trip abc123 --verbose
  node backfill_trip_message_scope_fields.js --key ./planerz-PROD.json --apply
`);
  process.exit(1);
}

function cleanString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function normalizedThreadType(data) {
  const threadType = cleanString(data.threadType);
  return THREAD_TYPES.has(threadType) ? threadType : 'main';
}

function defaultVisibilityForThread(threadType) {
  if (threadType === 'admin') return 'admins_only';
  if (threadType === 'object') return 'object_participants';
  return 'trip_all';
}

function missingScopeUpdates(data) {
  const updates = {};
  const threadType = normalizedThreadType(data);
  const visibilityType = cleanString(data.visibilityType);

  if (!THREAD_TYPES.has(cleanString(data.threadType))) {
    updates.threadType = threadType;
  }
  if (!VISIBILITY_TYPES.has(visibilityType)) {
    updates.visibilityType = defaultVisibilityForThread(threadType);
  }

  return updates;
}

async function loadMessageSnapshots(db, tripId) {
  if (tripId) {
    return db.collection('trips').doc(tripId).collection('messages').get();
  }
  return db.collectionGroup('messages').get();
}

async function commitUpdates(db, actions) {
  for (let offset = 0; offset < actions.length; offset += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = actions.slice(offset, offset + BATCH_SIZE);
    for (const action of chunk) {
      batch.update(action.ref, action.updates);
    }
    await batch.commit();
  }
}

async function run() {
  const opts = parseArgs(process.argv);
  if (!opts.keyPath) printUsageAndExit();

  const resolvedKey = path.resolve(process.cwd(), opts.keyPath);
  const serviceAccount = JSON.parse(fs.readFileSync(resolvedKey, 'utf8'));

  const app = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  const db = app.firestore();

  console.log(
    `Mode     : ${opts.dryRun ? 'DRY-RUN (aucune écriture)' : 'APPLY (écriture Firestore)'}`,
  );
  console.log(`Projet   : ${serviceAccount.project_id}`);
  if (opts.tripId) console.log(`Filtre   : trips/${opts.tripId}/messages`);
  console.log('');
  console.log('Scan des messages...');

  const snap = await loadMessageSnapshots(db, opts.tripId);
  const actions = [];
  snap.forEach((doc) => {
    const updates = missingScopeUpdates(doc.data() || {});
    if (Object.keys(updates).length === 0) return;
    actions.push({ ref: doc.ref, path: doc.ref.path, updates });
  });

  console.log(`Messages scannés            : ${snap.size}`);
  console.log(`Messages à corriger         : ${actions.length}`);
  if (opts.verbose) {
    for (const action of actions) {
      console.log(`  ${action.path} -> ${JSON.stringify(action.updates)}`);
    }
  }

  if (actions.length === 0) {
    await app.delete();
    return;
  }

  if (opts.dryRun) {
    console.log(
      '\nMode dry-run : aucune écriture. Relancer avec --apply pour appliquer les corrections.',
    );
    await app.delete();
    return;
  }

  await commitUpdates(db, actions);
  console.log(`\nMessages corrigés           : ${actions.length}`);
  await app.delete();
}

run().catch((err) => {
  console.error('Erreur fatale :', err);
  process.exit(1);
});
