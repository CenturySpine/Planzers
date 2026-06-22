'use strict';

/**
 * migrate_invite_tokens.js (v0.4.3)
 *
 * Normalise le champ inviteToken des voyages vers le format XXX-XXX
 * (6 caractères alphanumériques majuscules, tiret au milieu).
 *
 * Usage :
 *   node migrate_invite_tokens.js --key <service-account.json> [options]
 *
 * Options :
 *   --apply          Écriture réelle (par défaut : dry-run)
 *   --dry-run        Aperçu sans écriture (défaut)
 *   --verbose        Détail par voyage migré
 *   --trip <tripId>  Limiter au voyage indiqué
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

function loadFirebaseAdmin() {
  try {
    return require('firebase-admin');
  } catch {
    return require(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));
  }
}

const admin = loadFirebaseAdmin();

const BATCH_SIZE = 400;
const INVITE_CODE_CHAR_COUNT = 6;
const INVITE_CODE_SEGMENT_SIZE = 3;
const INVITE_TOKEN_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const TARGET_TOKEN_RE = /^[A-Z0-9]{3}-[A-Z0-9]{3}$/;
const HYPHENATED_TOKEN_RE = /^[A-Za-z0-9]{3}-[A-Za-z0-9]{3}$/;

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
  node migrate_invite_tokens.js --key <service-account.json> [options]

Required:
  --key <path>    Chemin vers le JSON du compte de service Firebase

Optional:
  --apply         Écriture réelle (par défaut : dry-run)
  --dry-run       Aperçu sans écriture
  --verbose       Afficher chaque migration prévue
  --trip <id>     Limiter à trips/{tripId}

Exemples:
  node migrate_invite_tokens.js --key ../planerz-PREVIEW.json
  node migrate_invite_tokens.js --key ../planerz-PREVIEW.json --trip abc123 --verbose
  node migrate_invite_tokens.js --key ../planerz-PROD.json --apply
`);
  process.exit(1);
}

function cleanString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function sanitizeInviteCodeInput(raw) {
  const cleaned = cleanString(raw).toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (cleaned.length <= INVITE_CODE_CHAR_COUNT) return cleaned;
  return cleaned.slice(0, INVITE_CODE_CHAR_COUNT);
}

function formatInviteCodeToken(code) {
  if (code.length !== INVITE_CODE_CHAR_COUNT) return code;
  return `${code.slice(0, INVITE_CODE_SEGMENT_SIZE)}-${code.slice(INVITE_CODE_SEGMENT_SIZE)}`;
}

function randomSegment(rng = crypto.randomInt) {
  let segment = '';
  for (let i = 0; i < INVITE_CODE_SEGMENT_SIZE; i++) {
    segment += INVITE_TOKEN_CHARS[rng(INVITE_TOKEN_CHARS.length)];
  }
  return segment;
}

function generateInviteToken(rng = crypto.randomInt) {
  const token = `${randomSegment(rng)}-${randomSegment(rng)}`;
  if (!TARGET_TOKEN_RE.test(token)) {
    throw new Error(`Generated invite token has unexpected shape: ${token}`);
  }
  return token;
}

function allocateUniqueToken(usedTokens, rng = crypto.randomInt) {
  for (let attempt = 0; attempt < 10_000; attempt++) {
    const candidate = generateInviteToken(rng);
    if (!usedTokens.has(candidate)) {
      return candidate;
    }
  }
  throw new Error('Unable to allocate a unique invite token after many attempts');
}

/**
 * @param {string} raw
 * @param {string} tripId
 * @param {Map<string, string>} usedTokens token -> tripId
 * @param {(max: number) => number} [rng]
 * @returns {{ newToken: string, reason: string } | null}
 */
function planTripInviteTokenMigration(raw, tripId, usedTokens, rng = crypto.randomInt) {
  const current = cleanString(raw);

  if (TARGET_TOKEN_RE.test(current)) {
    return null;
  }

  if (HYPHENATED_TOKEN_RE.test(current)) {
    const upper = current.toUpperCase();
    if (TARGET_TOKEN_RE.test(upper)) {
      if (usedTokens.has(upper) && usedTokens.get(upper) !== tripId) {
        const newToken = allocateUniqueToken(usedTokens, rng);
        return { newToken, reason: 'collision-case-normalize' };
      }
      return { newToken: upper, reason: 'case-normalize' };
    }
  }

  const sanitized = sanitizeInviteCodeInput(current);
  if (sanitized.length >= INVITE_CODE_CHAR_COUNT) {
    const candidate = formatInviteCodeToken(sanitized);
    if (TARGET_TOKEN_RE.test(candidate)) {
      if (usedTokens.has(candidate) && usedTokens.get(candidate) !== tripId) {
        const newToken = allocateUniqueToken(usedTokens, rng);
        return { newToken, reason: 'collision-derived' };
      }
      return { newToken: candidate, reason: 'derived' };
    }
  }

  if (!current) {
    return { newToken: allocateUniqueToken(usedTokens, rng), reason: 'empty' };
  }

  return { newToken: allocateUniqueToken(usedTokens, rng), reason: 'regenerated' };
}

/**
 * @param {Array<{ id: string, inviteToken: string }>} trips
 * @param {(max: number) => number} [rng]
 */
function planInviteTokenMigrations(trips, rng = crypto.randomInt) {
  const usedTokens = new Map();
  for (const trip of trips) {
    const token = cleanString(trip.inviteToken);
    if (TARGET_TOKEN_RE.test(token)) {
      usedTokens.set(token, trip.id);
    }
  }

  const actions = [];
  for (const trip of trips) {
    const plan = planTripInviteTokenMigration(trip.inviteToken, trip.id, usedTokens, rng);
    if (!plan) continue;
    usedTokens.set(plan.newToken, trip.id);
    actions.push({
      tripId: trip.id,
      oldToken: cleanString(trip.inviteToken),
      newToken: plan.newToken,
      reason: plan.reason,
    });
  }
  return actions;
}

async function loadTripDocs(db, tripId) {
  if (tripId) {
    const doc = await db.collection('trips').doc(tripId).get();
    return doc.exists ? [doc] : [];
  }
  const snap = await db.collection('trips').get();
  return snap.docs;
}

async function commitUpdates(db, actions) {
  let committed = 0;
  for (let offset = 0; offset < actions.length; offset += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = actions.slice(offset, offset + BATCH_SIZE);
    for (const action of chunk) {
      batch.update(db.collection('trips').doc(action.tripId), {
        inviteToken: action.newToken,
      });
    }
    try {
      await batch.commit();
      committed += chunk.length;
    } catch (err) {
      const paths = chunk.map((a) => `trips/${a.tripId}`).join('\n  ');
      console.error(`\nErreur sur le batch [${offset}–${offset + chunk.length - 1}] :\n  ${paths}`);
      console.error(err);
      throw err;
    }
  }
  return committed;
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
  if (opts.tripId) console.log(`Filtre   : trips/${opts.tripId}`);
  console.log('');
  console.log('Scan des voyages...');

  const docs = await loadTripDocs(db, opts.tripId);
  const trips = docs.map((doc) => ({
    id: doc.id,
    inviteToken: cleanString((doc.data() || {}).inviteToken),
  }));

  const actions = planInviteTokenMigrations(trips);
  const reasonCounts = {};
  for (const action of actions) {
    reasonCounts[action.reason] = (reasonCounts[action.reason] || 0) + 1;
  }

  console.log(`Voyages scannés              : ${trips.length}`);
  console.log(`Voyages déjà au format       : ${trips.length - actions.length}`);
  console.log(`Voyages à migrer             : ${actions.length}`);
  for (const [reason, count] of Object.entries(reasonCounts).sort()) {
    console.log(`  - ${reason.padEnd(24)} : ${count}`);
  }

  if (opts.verbose) {
    for (const action of actions) {
      const oldLabel = action.oldToken || '(vide)';
      console.log(
        `  trips/${action.tripId}  [${action.reason}]  ${oldLabel}  ->  ${action.newToken}`,
      );
    }
  }

  if (actions.length === 0) {
    await app.delete();
    return;
  }

  if (opts.dryRun) {
    console.log(
      '\nMode dry-run : aucune écriture. Relancer avec --apply pour appliquer les migrations.',
    );
    await app.delete();
    return;
  }

  const committed = await commitUpdates(db, actions);
  console.log(`\nVoyages migrés               : ${committed}`);
  await app.delete();
}

if (require.main === module) {
  run().catch((err) => {
    console.error('Erreur fatale :', err);
    process.exit(1);
  });
}

module.exports = {
  TARGET_TOKEN_RE,
  sanitizeInviteCodeInput,
  formatInviteCodeToken,
  generateInviteToken,
  planTripInviteTokenMigration,
  planInviteTokenMigrations,
};
