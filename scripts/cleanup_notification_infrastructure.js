'use strict';

/**
 * cleanup_notification_infrastructure.js
 *
 * Purge les collections techniques liées à l'ancienne idempotence des notifications
 * (`functionEventLocks` et `notificationQueue`). À lancer après déploiement des
 * Cloud Functions refactorées, quelques minutes plus tard et à un moment creux.
 *
 * Usage (depuis le dossier scripts/) :
 *   node cleanup_notification_infrastructure.js --key <service-account.json> [options]
 *
 * Options :
 *   --key <path>       Compte de service Firebase (obligatoire)
 *   --apply            Suppression réelle (par défaut : dry-run)
 *   --dry-run          Aperçu sans écriture (défaut)
 *   --verbose          Lister chaque document concerné
 *
 * Collections purgées :
 *   - functionEventLocks (tous les documents)
 *   - notificationQueue (tous les documents)
 *
 * Exemples :
 *   node cleanup_notification_infrastructure.js --key ./planerz-PREVIEW.json
 *   node cleanup_notification_infrastructure.js --key ./planerz-PREVIEW.json --apply
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

const DELETE_BATCH_SIZE = 500;
const TARGET_COLLECTIONS = ['functionEventLocks', 'notificationQueue'];

function parseCliArguments(argv) {
  const parsed = {
    keyPath: '',
    apply: false,
    dryRun: true,
    verbose: false,
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
    if (token === '--verbose') {
      parsed.verbose = true;
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
    }
  }

  return parsed;
}

function printUsageAndExit() {
  console.log(`
Usage (depuis le dossier scripts/) :
  node cleanup_notification_infrastructure.js --key <service-account.json> [options]

Required:
  --key <path>           Chemin vers le JSON du compte de service Firebase

Optional:
  --apply                Supprime réellement (par défaut : dry-run)
  --dry-run              Aperçu sans écriture (par défaut)
  --verbose              Lister chaque document supprimé

Collections purgées:
  - functionEventLocks (tous les documents)
  - notificationQueue (tous les documents)

Examples:
  node cleanup_notification_infrastructure.js --key ./planerz-PREVIEW.json
  node cleanup_notification_infrastructure.js --key ./planerz-PREVIEW.json --apply
`);
  process.exit(1);
}

function loadServiceAccountJson(keyPath) {
  const resolvedPath = path.resolve(process.cwd(), keyPath);
  const rawJson = fs.readFileSync(resolvedPath, 'utf8');
  return JSON.parse(rawJson);
}

async function forEachDocumentInCollection(collectionRef, visitor) {
  let lastDocument = null;

  while (true) {
    let query = collectionRef
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(DELETE_BATCH_SIZE);
    if (lastDocument) {
      query = query.startAfter(lastDocument);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      return;
    }

    for (const document of snapshot.docs) {
      await visitor(document);
      lastDocument = document;
    }

    if (snapshot.size < DELETE_BATCH_SIZE) {
      return;
    }
  }
}

async function countDocumentsInCollection(collectionRef) {
  let count = 0;
  await forEachDocumentInCollection(collectionRef, () => {
    count += 1;
  });
  return count;
}

async function deleteDocumentsInCollection(firestore, collectionId, options) {
  const collectionRef = firestore.collection(collectionId);
  let deletedCount = 0;
  let batch = firestore.batch();
  let batchOps = 0;

  await forEachDocumentInCollection(collectionRef, async (document) => {
    if (options.verbose) {
      console.log(`  delete ${document.ref.path}`);
    }
    if (options.dryRun) {
      deletedCount += 1;
      return;
    }

    batch.delete(document.ref);
    batchOps += 1;
    deletedCount += 1;

    if (batchOps >= DELETE_BATCH_SIZE) {
      await batch.commit();
      batch = firestore.batch();
      batchOps = 0;
    }
  });

  if (!options.dryRun && batchOps > 0) {
    await batch.commit();
  }

  return deletedCount;
}

async function run() {
  const options = parseCliArguments(process.argv);
  if (!options.keyPath) {
    printUsageAndExit();
  }

  const serviceAccount = loadServiceAccountJson(options.keyPath);
  const app = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  const firestore = app.firestore();

  console.log(
    `Mode: ${options.dryRun ? 'DRY-RUN (lecture seule)' : 'APPLY (suppression)'}`
  );
  console.log(`Projet: ${serviceAccount.project_id}`);
  console.log(`Collections: ${TARGET_COLLECTIONS.join(', ')}`);

  const summary = {};

  for (const collectionId of TARGET_COLLECTIONS) {
    const collectionRef = firestore.collection(collectionId);
    const total = await countDocumentsInCollection(collectionRef);
    console.log(`\n${collectionId}: ${total} document(s) trouvé(s)`);

    const processed = await deleteDocumentsInCollection(firestore, collectionId, options);
    summary[collectionId] = { total, processed };
  }

  console.log('\nRésumé:');
  for (const collectionId of TARGET_COLLECTIONS) {
    const { total, processed } = summary[collectionId];
    const action = options.dryRun ? 'à supprimer' : 'supprimés';
    console.log(`  ${collectionId}: ${processed}/${total} ${action}`);
  }

  if (options.dryRun) {
    console.log('\nDry-run terminé. Relancer avec --apply pour supprimer.');
  }
}

run().catch((error) => {
  console.error(error);
  process.exit(1);
});
