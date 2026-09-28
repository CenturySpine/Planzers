'use strict';

/**
 * delete_trip_activities.js
 *
 * Deletes every activity of one trip (`trips/{tripId}/activities`) and clears
 * the links that pointed to them:
 *   - travel documents of every traveler (`activityIds` / legacy `activityId`
 *     on `travelerModules/{uid}/walletDocuments`)
 *   - meals using a deleted restaurant (`restaurantActivityId`)
 *
 * Without --trip, lists the trips of the project and asks which one to clean.
 *
 * Usage (from the scripts/ folder):
 *   node delete_trip_activities.js --key <service-account.json> [options]
 *
 * Options:
 *   --key <path>    Firebase service account (required)
 *   --trip <id>     Trip id (optional: otherwise chosen from the list)
 *   --apply         Real deletion, after confirmation (default: dry-run)
 *   --yes           Skip the confirmation (non-interactive use, requires --trip)
 *   --dry-run       Preview without writing (default)
 *   --verbose       List every activity concerned
 *
 * Examples:
 *   node delete_trip_activities.js --key ./planerz-PREVIEW.json
 *   node delete_trip_activities.js --key ./planerz-PREVIEW.json --apply
 *   node delete_trip_activities.js --key ./planerz-PREVIEW.json --trip abc123 --apply
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline/promises');

function loadFirebaseAdmin() {
  try {
    return require('firebase-admin');
  } catch {
    try {
      return require(path.join(__dirname, 'migration', 'node_modules', 'firebase-admin'));
    } catch {
      return require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
    }
  }
}

const admin = loadFirebaseAdmin();

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { keyPath: null, tripId: null, apply: false, yes: false, verbose: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--key' && args[i + 1]) { opts.keyPath = args[++i]; }
    else if (args[i] === '--trip' && args[i + 1]) { opts.tripId = args[++i].trim(); }
    else if (args[i] === '--apply') { opts.apply = true; }
    else if (args[i] === '--dry-run') { opts.apply = false; }
    else if (args[i] === '--yes') { opts.yes = true; }
    else if (args[i] === '--verbose') { opts.verbose = true; }
  }
  return opts;
}

function formatPlannedAt(value) {
  if (value && typeof value.toDate === 'function') {
    return value.toDate().toISOString().slice(0, 16).replace('T', ' ');
  }
  return 'non planifiée';
}

function formatTripDate(value) {
  if (value && typeof value.toDate === 'function') {
    // Stored as midnight in the device time zone: round to the nearest day.
    return new Date(value.toDate().getTime() + 12 * 60 * 60 * 1000).toISOString().slice(0, 10);
  }
  return typeof value === 'string' ? value.slice(0, 10) : '';
}

/** Question that reads a closed input (end of a piped stdin) as an empty answer. */
async function ask(rl, question) {
  try {
    return (await rl.question(question)).trim();
  } catch (e) {
    if (e && e.code === 'ERR_USE_AFTER_CLOSE') return '';
    throw e;
  }
}

/** Lists the trips (most recent start first) and returns the chosen id. */
async function chooseTripId(db, rl) {
  const tripsSnap = await db.collection('trips').get();
  const trips = await Promise.all(
    tripsSnap.docs.map(async (doc) => {
      const data = doc.data() || {};
      const countSnap = await doc.ref.collection('activities').count().get();
      return {
        id: doc.id,
        title: String(data.title || '(sans titre)'),
        start: formatTripDate(data.startDate),
        end: formatTripDate(data.endDate),
        activityCount: countSnap.data().count,
      };
    })
  );
  trips.sort((a, b) => (b.start || '').localeCompare(a.start || ''));
  if (trips.length === 0) {
    console.error('Aucun voyage dans ce projet.');
    process.exit(1);
  }

  console.log('Voyages :');
  trips.forEach((t, index) => {
    const dates = t.start || t.end ? ` — ${t.start || '?'} → ${t.end || '?'}` : '';
    console.log(`  ${String(index + 1).padStart(3)}. ${t.title}${dates} (${t.activityCount} activité(s))  [${t.id}]`);
  });

  const answer = await ask(rl, '\nNuméro du voyage (vide pour annuler) : ');
  const index = Number(answer) - 1;
  if (!answer || !Number.isInteger(index) || index < 0 || index >= trips.length) {
    console.log('Annulé.');
    process.exit(0);
  }
  return trips[index].id;
}

async function run() {
  const opts = parseArgs();

  if (!opts.keyPath || (opts.tripId && !/^[A-Za-z0-9_-]+$/.test(opts.tripId))) {
    console.error('Usage: node delete_trip_activities.js --key <service-account.json> [--trip <tripId>] [--apply] [--verbose]');
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(path.resolve(opts.keyPath), 'utf8'));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

  try {
    await cleanTrip(db, rl, serviceAccount, opts);
  } finally {
    rl.close();
  }
}

async function cleanTrip(db, rl, serviceAccount, opts) {
  console.log(`Projet : ${serviceAccount.project_id}`);
  console.log(`Mode   : ${opts.apply ? 'APPLY (suppression réelle)' : 'DRY-RUN (aucune écriture)'}\n`);

  const tripId = opts.tripId || (await chooseTripId(db, rl));
  const tripRef = db.collection('trips').doc(tripId);
  const tripSnap = await tripRef.get();
  if (!tripSnap.exists) {
    console.error(`Voyage introuvable : ${tripId}`);
    process.exit(1);
  }
  const tripTitle = tripSnap.data()?.title || '(sans titre)';
  console.log(`\nVoyage : ${tripTitle} (${tripId})\n`);

  const activitiesSnap = await tripRef.collection('activities').get();
  const deletedIds = new Set(activitiesSnap.docs.map((d) => d.id));
  if (opts.verbose) {
    for (const doc of activitiesSnap.docs) {
      const data = doc.data() || {};
      console.log(`  [${data.category || '?'}] ${formatPlannedAt(data.plannedAt)}  ${data.label || '(sans libellé)'}  (${doc.id})`);
    }
  }

  // Travel documents of every traveler of the trip.
  const walletUpdates = [];
  const travelerRefs = await tripRef.collection('travelerModules').listDocuments();
  for (const travelerRef of travelerRefs) {
    const walletSnap = await travelerRef.collection('walletDocuments').get();
    for (const doc of walletSnap.docs) {
      const data = doc.data() || {};
      const ids = Array.isArray(data.activityIds) ? data.activityIds.map(String) : [];
      const legacy = typeof data.activityId === 'string' ? data.activityId.trim() : '';
      const kept = ids.filter((id) => !deletedIds.has(id));
      const legacyDeleted = legacy && deletedIds.has(legacy);
      if (kept.length === ids.length && !legacyDeleted) continue;
      walletUpdates.push({
        ref: doc.ref,
        data: {
          activityIds: kept.length === 0
            ? admin.firestore.FieldValue.delete()
            : kept,
          ...(legacyDeleted ? { activityId: admin.firestore.FieldValue.delete() } : {}),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
    }
  }

  // Meals whose restaurant is one of the deleted activities.
  const mealUpdates = [];
  const mealsSnap = await tripRef.collection('meals').get();
  for (const doc of mealsSnap.docs) {
    const restaurantId = String(doc.data()?.restaurantActivityId || '').trim();
    if (restaurantId && deletedIds.has(restaurantId)) {
      mealUpdates.push({ ref: doc.ref, data: { restaurantActivityId: '' } });
    }
  }

  console.log(`\nActivités à supprimer            : ${deletedIds.size}`);
  console.log(`Documents de voyage à délier      : ${walletUpdates.length}`);
  console.log(`Repas dont le restaurant est retiré : ${mealUpdates.length}`);

  if (!opts.apply) {
    console.log('\n(Dry-run — relancer avec --apply pour supprimer)');
    return;
  }
  if (deletedIds.size === 0) {
    console.log('\nRien à supprimer.');
    return;
  }
  const confirm = opts.yes && opts.tripId ? 'oui' : (await ask(
    rl,
    `\nSupprimer ${deletedIds.size} activité(s) de « ${tripTitle} » sur ${serviceAccount.project_id} ? (oui/non) : `
  )).toLowerCase();
  if (confirm !== 'oui') {
    console.log('Annulé.');
    return;
  }

  const BATCH_SIZE = 400;
  let batch = db.batch();
  let batchOps = 0;
  async function queue(op) {
    op(batch);
    batchOps++;
    if (batchOps >= BATCH_SIZE) {
      await batch.commit();
      batch = db.batch();
      batchOps = 0;
    }
  }

  // Links first, so an interrupted run never leaves links to missing activities.
  for (const u of walletUpdates) await queue((b) => b.update(u.ref, u.data));
  for (const u of mealUpdates) await queue((b) => b.update(u.ref, u.data));
  if (batchOps > 0) {
    await batch.commit();
    batch = db.batch();
    batchOps = 0;
  }
  for (const doc of activitiesSnap.docs) await queue((b) => b.delete(doc.ref));
  if (batchOps > 0) await batch.commit();

  console.log(`\nDone. ${deletedIds.size} activité(s) supprimée(s).`);
}

run().catch((e) => { console.error(e); process.exit(1); });
