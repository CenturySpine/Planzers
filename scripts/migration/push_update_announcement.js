const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

function parseCliArguments(argv) {
  const parsed = {
    keyPath: '',
    authorId: '',
    message: '',
    apply: false,
    dryRun: true,
    tripLimit: 0,
    includeArchived: false,
    tag: '[IMPORTANT]',
  };

  for (let index = 2; index < argv.length; index++) {
    const token = argv[index];
    if (token === '--apply') {
      parsed.apply = true;
      parsed.dryRun = false;
      continue;
    }
    if (token === '--dry-run') {
      parsed.dryRun = true;
      parsed.apply = false;
      continue;
    }
    if (token === '--include-archived') {
      parsed.includeArchived = true;
      continue;
    }
    if (!token.startsWith('--')) {
      continue;
    }

    const [flag, inlineValue] = token.split('=');
    const nextValue = inlineValue ?? argv[index + 1];
    const hasInlineValue = inlineValue !== undefined;

    const consumeNext = () => {
      if (!hasInlineValue) {
        index += 1;
      }
    };

    if (flag === '--key') {
      parsed.keyPath = (nextValue || '').trim();
      consumeNext();
      continue;
    }
    if (flag === '--author-id') {
      parsed.authorId = (nextValue || '').trim();
      consumeNext();
      continue;
    }
    if (flag === '--message') {
      parsed.message = (nextValue || '').trim();
      consumeNext();
      continue;
    }
    if (flag === '--trip-limit') {
      const parsedValue = Number.parseInt((nextValue || '').trim(), 10);
      parsed.tripLimit = Number.isFinite(parsedValue) && parsedValue > 0
        ? parsedValue
        : 0;
      consumeNext();
      continue;
    }
    if (flag === '--tag') {
      parsed.tag = (nextValue || '').trim();
      consumeNext();
    }
  }

  return parsed;
}

function printUsageAndExit() {
  console.log(`
Usage:
  node push_update_announcement.js --key ./preview-key.json --author-id <uid> --message "<text>" [options]

Required:
  --key <path>           Service account JSON path
  --author-id <uid>      UID used in announcements.authorId
  --message "<text>"     Announcement text

Optional:
  --apply                Actually write announcements (default is dry-run)
  --dry-run              Read-only preview mode (default)
  --trip-limit <n>       Limit number of trips to process
  --include-archived     Include archived trips (default: excluded when possible)
  --tag "<prefix>"       Idempotency tag searched in existing announcements

Examples:
  node push_update_announcement.js --key ./preview-key.json --author-id abc123 --message "[Administrateur de l’application] [IMPORTANT] La version minimale requise est la bêta 1. Si vous avez une version antérieure, merci de faire la mise à jour immédiatement."
  node push_update_announcement.js --key ./preview-key.json --author-id abc123 --message "..." --apply
`);
  process.exit(1);
}

function loadServiceAccountJson(keyPath) {
  const resolvedPath = path.resolve(process.cwd(), keyPath);
  const rawJson = fs.readFileSync(resolvedPath, 'utf8');
  return JSON.parse(rawJson);
}

function announcementHasTag(announcementData, expectedTag) {
  if (!announcementData || typeof announcementData !== 'object') return false;
  const messageText = typeof announcementData.text === 'string'
    ? announcementData.text.trim()
    : '';
  if (!messageText) return false;
  return messageText.includes(expectedTag);
}

async function tripAlreadyHasTaggedAnnouncement(tripRef, tag) {
  const snapshot = await tripRef
    .collection('announcements')
    .orderBy('createdAt', 'desc')
    .limit(25)
    .get();
  for (const document of snapshot.docs) {
    if (announcementHasTag(document.data(), tag)) {
      return true;
    }
  }
  return false;
}

function tripIsArchived(tripData) {
  if (!tripData || typeof tripData !== 'object') return false;
  return tripData.archived === true || tripData.isArchived === true;
}

async function run() {
  const options = parseCliArguments(process.argv);
  if (!options.keyPath || !options.authorId || !options.message) {
    printUsageAndExit();
  }

  const serviceAccount = loadServiceAccountJson(options.keyPath);
  const app = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  const firestore = app.firestore();

  console.log(`Mode: ${options.dryRun ? 'DRY-RUN (read-only)' : 'APPLY (write enabled)'}`);
  console.log(`Tag anti-doublon: ${options.tag}`);

  const tripsSnapshot = await firestore.collection('trips').get();
  const allTripDocuments = tripsSnapshot.docs;
  const eligibleTrips = [];

  for (const tripDocument of allTripDocuments) {
    const tripData = tripDocument.data() || {};
    if (!options.includeArchived && tripIsArchived(tripData)) {
      continue;
    }
    eligibleTrips.push(tripDocument);
  }

  const tripsToProcess = options.tripLimit > 0
    ? eligibleTrips.slice(0, options.tripLimit)
    : eligibleTrips;

  let skippedBecauseExistingTag = 0;
  let wouldCreateCount = 0;
  let createdCount = 0;
  let errorCount = 0;

  for (const tripDocument of tripsToProcess) {
    const tripRef = tripDocument.ref;
    const tripId = tripDocument.id;
    const tripTitle = typeof tripDocument.data()?.title === 'string'
      ? tripDocument.data().title.trim()
      : '';

    try {
      const alreadyHasTaggedAnnouncement = await tripAlreadyHasTaggedAnnouncement(
        tripRef,
        options.tag
      );

      if (alreadyHasTaggedAnnouncement) {
        skippedBecauseExistingTag += 1;
        console.log(`SKIP ${tripId} (${tripTitle || 'Sans titre'}) -> annonce taggée déjà présente`);
        continue;
      }

      if (options.dryRun) {
        wouldCreateCount += 1;
        console.log(`DRY  ${tripId} (${tripTitle || 'Sans titre'}) -> annonce à créer`);
        continue;
      }

      await tripRef.collection('announcements').add({
        text: options.message,
        authorId: options.authorId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      createdCount += 1;
      console.log(`DONE ${tripId} (${tripTitle || 'Sans titre'}) -> annonce créée`);
    } catch (error) {
      errorCount += 1;
      console.error(`ERR  ${tripId} (${tripTitle || 'Sans titre'}) -> ${error.message}`);
    }
  }

  console.log('\n--- Résultat ---');
  console.log(`Trips trouvés: ${allTripDocuments.length}`);
  console.log(`Trips éligibles: ${eligibleTrips.length}`);
  console.log(`Trips traités: ${tripsToProcess.length}`);
  console.log(`Ignorés (tag déjà présent): ${skippedBecauseExistingTag}`);
  console.log(`Annonces ${options.dryRun ? 'prévisualisées' : 'créées'}: ${options.dryRun ? wouldCreateCount : createdCount}`);
  console.log(`Erreurs: ${errorCount}`);

  await app.delete();
}

run().catch((error) => {
  console.error('Erreur fatale:', error);
  process.exit(1);
});
