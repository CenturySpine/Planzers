'use strict';

// Migrate legacy chat image Storage objects to include authorId custom metadata.
//
// For each image message in Firestore that has an imageStoragePath, this script
// reads the corresponding Storage object and patches its custom metadata with
// the authorId from the message document — enabling the Storage delete rule
// introduced in fix(storage): protect chat image storage objects.
//
// Usage:
//   node migrate_chat_image_metadata.js <service-account-key.json> [--apply]
//
// Dry-run by default. Pass --apply to write metadata updates.
// The script targets the bucket derived from the project_id in the key file.
// Override with: --bucket <name>   (e.g. planerz.appspot.com)

const admin = require('firebase-admin');
const fs = require('fs');

const args = process.argv.slice(2);
const applyMode = args.includes('--apply');
const bucketOverride = (() => {
  const idx = args.indexOf('--bucket');
  return idx !== -1 ? args[idx + 1] : null;
})();
const keyFilePath = args.find(a => !a.startsWith('--') && a !== bucketOverride);

if (!keyFilePath) {
  console.error('Usage: node migrate_chat_image_metadata.js <service-account-key.json> [--apply] [--bucket <name>]');
  process.exit(1);
}

const serviceAccount = JSON.parse(fs.readFileSync(keyFilePath, 'utf8'));
const projectId = serviceAccount.project_id;
const bucketName = bucketOverride || `${projectId}.firebasestorage.app`;

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: bucketName,
});

const db = admin.firestore();
const bucket = admin.storage().bucket();

async function run() {
  console.log(`Project : ${projectId}`);
  console.log(`Bucket  : ${bucketName}`);
  console.log(`Mode    : ${applyMode ? 'APPLY' : 'DRY-RUN'}`);
  console.log('');

  const tripsSnap = await db.collection('trips').get();
  console.log(`Trips found: ${tripsSnap.size}`);
  console.log('');

  let alreadyOk = 0;
  let updated = 0;
  let notFound = 0;
  let skipped = 0;
  let errored = 0;

  const docs = [];
  for (const tripDoc of tripsSnap.docs) {
    const msgSnap = await db
      .collection('trips')
      .doc(tripDoc.id)
      .collection('messages')
      .where('imageStoragePath', '>', '')
      .get();
    for (const m of msgSnap.docs) docs.push(m);
  }

  console.log(`Image messages with a storagePath: ${docs.length}`);
  console.log('');

  for (const doc of docs) {
    const data = doc.data();
    const storagePath = (data.imageStoragePath || '').trim();
    const authorId = (data.authorId || '').trim();

    if (!storagePath || !authorId) {
      console.warn(`[SKIP] ${doc.ref.path} — missing storagePath or authorId in Firestore`);
      skipped++;
      continue;
    }

    try {
      const file = bucket.file(storagePath);
      const [meta] = await file.getMetadata();
      const existing = meta.metadata && meta.metadata.authorId;

      if (existing === authorId) {
        alreadyOk++;
        continue;
      }

      if (existing && existing !== authorId) {
        console.warn(`[CONFLICT] ${storagePath} — storage authorId="${existing}" vs Firestore "${authorId}" — skipped`);
        skipped++;
        continue;
      }

      // No authorId in metadata yet.
      console.log(`[${applyMode ? 'UPDATE' : 'WOULD UPDATE'}] ${storagePath}  →  authorId=${authorId}`);
      if (applyMode) {
        await file.setMetadata({ metadata: { authorId } });
      }
      updated++;
    } catch (err) {
      if (err.code === 404) {
        console.warn(`[NOT FOUND] ${storagePath} (${doc.ref.path})`);
        notFound++;
      } else {
        console.error(`[ERROR] ${storagePath}: ${err.message}`);
        errored++;
      }
    }
  }

  console.log('');
  console.log('─── Summary ───────────────────────────────────────────');
  console.log(`Already had correct metadata : ${alreadyOk}`);
  console.log(`${applyMode ? 'Updated                     ' : 'Would update                '} : ${updated}`);
  console.log(`Storage object not found     : ${notFound}`);
  console.log(`Skipped (conflict / bad data): ${skipped}`);
  console.log(`Errors                       : ${errored}`);

  if (!applyMode && updated > 0) {
    console.log('');
    console.log('Re-run with --apply to write the updates.');
  }
}

run()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Fatal:', err);
    process.exit(1);
  });
