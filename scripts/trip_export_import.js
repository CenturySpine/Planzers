'use strict';

/**
 * trip_export_import.js
 *
 * Exporte un voyage Firestore complet (document + sous-collections récursives)
 * et les documents users/{uid} nécessaires, ou importe un export JSON.
 *
 * Usage :
 *   node trip_export_import.js --key <service-account.json> export [options]
 *   node trip_export_import.js --key <service-account.json> import --file <export.json> [options]
 *
 * Export :
 *   Liste les voyages (sauf --trip) ; après sélection, écrit un fichier JSON.
 *   --trip <tripId>     Exporter ce voyage sans menu interactif
 *   --out <path>        Fichier de sortie (défaut : trip-export-<id>-<horodatage>.json)
 *
 * Import :
 *   --file <path>       Fichier JSON produit par export (obligatoire)
 *   --apply             Écriture réelle (défaut : dry-run)
 *   --dry-run           Aperçu sans écriture (défaut)
 *
 * Exemples :
 *   node trip_export_import.js --key ./planerz-PROD.json export
 *   node trip_export_import.js --key ./planerz-PROD.json export --trip abc123 --out ./backup.json
 *   node trip_export_import.js --key ./planerz-PROD.json import --file ./backup.json
 *   node trip_export_import.js --key ./planerz-PROD.json import --file ./backup.json --apply
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');

const EXPORT_FORMAT_VERSION = 1;
const BATCH_SIZE = 400;

function loadFirebaseAdmin() {
  try {
    return require('firebase-admin');
  } catch {
    return require(path.join(__dirname, 'migration', 'node_modules', 'firebase-admin'));
  }
}

const admin = loadFirebaseAdmin();

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const opts = {
    keyPath: '',
    command: '',
    tripId: '',
    outPath: '',
    filePath: '',
    apply: false,
    dryRun: true,
    force: false,
  };

  for (let i = 2; i < argv.length; i++) {
    const token = argv[i];
    if (token === 'export' || token === 'import') {
      opts.command = token;
      continue;
    }
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
    if (token === '--force') {
      opts.force = true;
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
    } else if (flag === '--out') {
      opts.outPath = (nextVal || '').trim();
      consume();
    } else if (flag === '--file') {
      opts.filePath = (nextVal || '').trim();
      consume();
    }
  }

  return opts;
}

function printUsageAndExit() {
  console.log(`
Usage:
  node trip_export_import.js --key <service-account.json> export [options]
  node trip_export_import.js --key <service-account.json> import --file <export.json> [options]

Required:
  --key <path>              Compte de service Firebase

Export:
  export                    Mode export (liste interactive ou --trip)
  --trip <tripId>           Voyage à exporter sans menu
  --out <path>              Fichier JSON de sortie

Import:
  import                    Mode import
  --file <path>             Fichier JSON à importer (obligatoire)
  --apply                   Écriture Firestore
  --dry-run                 Aperçu (défaut)

Exemples:
  node trip_export_import.js --key ./planerz-PROD.json export
  node trip_export_import.js --key ./planerz-PROD.json export --trip abc123 --out ./voyage.json
  node trip_export_import.js --key ./planerz-PROD.json import --file ./voyage.json --apply
`);
  process.exit(1);
}

function prompt(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

// ---------------------------------------------------------------------------
// Sérialisation Firestore ↔ JSON
// ---------------------------------------------------------------------------

function serializeValue(value) {
  if (value === null || value === undefined) return value;
  if (value instanceof admin.firestore.Timestamp) {
    return {
      __type: 'Timestamp',
      seconds: value.seconds,
      nanoseconds: value.nanoseconds,
    };
  }
  if (value instanceof admin.firestore.GeoPoint) {
    return {
      __type: 'GeoPoint',
      latitude: value.latitude,
      longitude: value.longitude,
    };
  }
  if (value instanceof admin.firestore.DocumentReference) {
    return { __type: 'DocumentReference', path: value.path };
  }
  if (Array.isArray(value)) {
    return value.map(serializeValue);
  }
  if (typeof value === 'object' && value.constructor === Object) {
    const out = {};
    for (const [key, entry] of Object.entries(value)) {
      out[key] = serializeValue(entry);
    }
    return out;
  }
  return value;
}

function deserializeValue(value) {
  if (value === null || value === undefined) return value;
  if (Array.isArray(value)) {
    return value.map(deserializeValue);
  }
  if (typeof value === 'object' && value.__type === 'Timestamp') {
    return new admin.firestore.Timestamp(value.seconds, value.nanoseconds);
  }
  if (typeof value === 'object' && value.__type === 'GeoPoint') {
    return new admin.firestore.GeoPoint(value.latitude, value.longitude);
  }
  if (typeof value === 'object' && value.__type === 'DocumentReference') {
    return admin.firestore().doc(value.path);
  }
  if (typeof value === 'object' && value.constructor === Object) {
    const out = {};
    for (const [key, entry] of Object.entries(value)) {
      out[key] = deserializeValue(entry);
    }
    return out;
  }
  return value;
}

// ---------------------------------------------------------------------------
// Export récursif
// ---------------------------------------------------------------------------

function tripDisplayTitle(data) {
  return String(data?.title ?? '').trim() || '(sans titre)';
}

async function exportDocumentTree(docRef) {
  const snap = await docRef.get();
  if (!snap.exists) return null;

  const node = {
    path: docRef.path,
    data: serializeValue(snap.data()),
    subcollections: {},
  };

  const subcollections = await docRef.listCollections();
  for (const collRef of subcollections) {
    const docsSnap = await collRef.get();
    node.subcollections[collRef.id] = {};
    for (const doc of docsSnap.docs) {
      node.subcollections[collRef.id][doc.id] = await exportDocumentTree(doc.ref);
    }
  }

  return node;
}

const USER_ID_ARRAY_FIELDS = new Set([
  'memberUserIds',
  'adminMemberIds',
  'passengerIds',
  'visibleToMemberIds',
  'participantIds',
  'assignedParticipantIds',
]);

const USER_ID_STRING_FIELDS = new Set([
  'userId',
  'ownerId',
  'createdBy',
  'paidBy',
  'assignedTo',
  'authorId',
  'senderId',
  'driverId',
  'driverUserId',
  'fromUserId',
  'toUserId',
  'claimedBy',
]);

function collectUserIdsFromRaw(value, ids) {
  if (value === null || value === undefined) return;
  if (value instanceof admin.firestore.Timestamp) return;
  if (value instanceof admin.firestore.GeoPoint) return;
  if (value instanceof admin.firestore.DocumentReference) return;

  if (Array.isArray(value)) {
    for (const item of value) collectUserIdsFromRaw(item, ids);
    return;
  }

  if (typeof value !== 'object') return;

  for (const [key, entry] of Object.entries(value)) {
    if (USER_ID_ARRAY_FIELDS.has(key) && Array.isArray(entry)) {
      for (const item of entry) {
        if (typeof item === 'string' && item.trim()) ids.add(item.trim());
      }
      continue;
    }
    if (
      (USER_ID_STRING_FIELDS.has(key) || key.endsWith('UserId')) &&
      typeof entry === 'string' &&
      entry.trim()
    ) {
      ids.add(entry.trim());
      continue;
    }
    collectUserIdsFromRaw(entry, ids);
  }
}

function collectUserIdsFromSerializedNode(node, ids) {
  if (!node) return;
  collectUserIdsFromRaw(deserializeValue(node.data), ids);
  for (const coll of Object.values(node.subcollections || {})) {
    for (const child of Object.values(coll)) {
      collectUserIdsFromSerializedNode(child, ids);
    }
  }
}

function countTreeDocs(node) {
  if (!node) return 0;
  let total = 1;
  for (const coll of Object.values(node.subcollections || {})) {
    for (const child of Object.values(coll)) {
      total += countTreeDocs(child);
    }
  }
  return total;
}

function listSubcollectionNames(node, names = new Set()) {
  if (!node) return names;
  for (const [collName, docs] of Object.entries(node.subcollections || {})) {
    names.add(collName);
    for (const child of Object.values(docs)) {
      listSubcollectionNames(child, names);
    }
  }
  return names;
}

async function loadUsersForExport(db, userIds) {
  const users = {};
  const ids = [...userIds].filter(Boolean);
  if (ids.length === 0) return users;

  const chunkSize = 100;
  for (let offset = 0; offset < ids.length; offset += chunkSize) {
    const chunk = ids.slice(offset, offset + chunkSize);
    const refs = chunk.map((uid) => db.collection('users').doc(uid));
    const snaps = await db.getAll(...refs);
    for (const snap of snaps) {
      if (!snap.exists) continue;
      users[snap.id] = {
        path: snap.ref.path,
        data: serializeValue(snap.data()),
      };
    }
  }
  return users;
}

// ---------------------------------------------------------------------------
// Liste / sélection des voyages
// ---------------------------------------------------------------------------

async function listTrips(db) {
  const snap = await db.collection('trips').get();
  const trips = snap.docs.map((doc) => ({
    id: doc.id,
    data: doc.data(),
    title: tripDisplayTitle(doc.data()),
    destination: String(doc.data()?.destination ?? '').trim(),
    createdAt: doc.data()?.createdAt,
  }));

  trips.sort((a, b) => {
    const ta =
      a.createdAt && typeof a.createdAt.toMillis === 'function'
        ? a.createdAt.toMillis()
        : 0;
    const tb =
      b.createdAt && typeof b.createdAt.toMillis === 'function'
        ? b.createdAt.toMillis()
        : 0;
    return tb - ta;
  });

  return trips;
}

function printTripList(trips) {
  console.log(`\n${trips.length} voyage(s) :\n`);
  trips.forEach((trip, index) => {
    const dest = trip.destination ? ` — ${trip.destination}` : '';
    console.log(`  [${index + 1}] ${trip.title}${dest}  (${trip.id})`);
  });
  console.log('');
}

async function selectTripInteractive(trips) {
  if (trips.length === 0) {
    throw new Error('Aucun voyage trouvé dans Firestore.');
  }
  printTripList(trips);
  const answer = await prompt(
    `Numéro du voyage à exporter (1-${trips.length}), ou "q" pour annuler : `,
  );
  if (answer.toLowerCase() === 'q') {
    throw new Error('Export annulé.');
  }
  const index = Number.parseInt(answer, 10);
  if (!Number.isFinite(index) || index < 1 || index > trips.length) {
    throw new Error(`Sélection invalide : "${answer}".`);
  }
  return trips[index - 1];
}

function defaultExportPath(tripId) {
  const stamp = new Date()
    .toISOString()
    .replace(/[:.]/g, '-')
    .replace('T', '_')
    .slice(0, 19);
  return path.resolve(process.cwd(), `trip-export-${tripId}-${stamp}.json`);
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

async function runExport(db, serviceAccount, opts) {
  let tripId = opts.tripId;

  if (!tripId) {
    console.log('Chargement des voyages…');
    const trips = await listTrips(db);
    const selected = await selectTripInteractive(trips);
    tripId = selected.id;
  }

  const tripRef = db.collection('trips').doc(tripId);
  const tripSnap = await tripRef.get();
  if (!tripSnap.exists) {
    throw new Error(`Voyage introuvable : trips/${tripId}`);
  }

  console.log(`\nExport de trips/${tripId} (« ${tripDisplayTitle(tripSnap.data())} »)…`);
  console.log('Lecture récursive des sous-collections…');

  const tripTree = await exportDocumentTree(tripRef);
  const userIds = new Set();
  collectUserIdsFromRaw(tripSnap.data(), userIds);
  collectUserIdsFromSerializedNode(tripTree, userIds);

  console.log(`Chargement de ${userIds.size} utilisateur(s) lié(s)…`);
  const users = await loadUsersForExport(db, userIds);

  const missingUserIds = [...userIds].filter((uid) => !users[uid]);
  if (missingUserIds.length > 0) {
    console.warn(
      `Attention : ${missingUserIds.length} UID(s) référencé(s) sans document users/{uid} :`,
    );
    for (const uid of missingUserIds) {
      console.warn(`  • ${uid}`);
    }
  }

  const subcollNames = [...listSubcollectionNames(tripTree)].sort();
  const docCount = countTreeDocs(tripTree);

  const payload = {
    formatVersion: EXPORT_FORMAT_VERSION,
    exportedAt: new Date().toISOString(),
    sourceProjectId: serviceAccount.project_id || '',
    tripId,
    trip: tripTree,
    users,
    stats: {
      tripDocumentCount: docCount,
      subcollectionNames: subcollNames,
      userCount: Object.keys(users).length,
      referencedUserCount: userIds.size,
    },
  };

  const outPath = opts.outPath
    ? path.resolve(process.cwd(), opts.outPath)
    : defaultExportPath(tripId);

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(payload, null, 2), 'utf8');

  console.log('\nExport terminé.');
  console.log(`  Fichier              : ${outPath}`);
  console.log(`  Documents (voyage)   : ${docCount}`);
  console.log(`  Sous-collections     : ${subcollNames.length > 0 ? subcollNames.join(', ') : '(aucune)'}`);
  console.log(`  Utilisateurs exportés: ${Object.keys(users).length} / ${userIds.size} référencé(s)`);
}

// ---------------------------------------------------------------------------
// Import
// ---------------------------------------------------------------------------

function validateExportPayload(payload) {
  if (!payload || typeof payload !== 'object') {
    throw new Error('Fichier JSON invalide.');
  }
  if (payload.formatVersion !== EXPORT_FORMAT_VERSION) {
    throw new Error(
      `Version d'export non supportée : ${payload.formatVersion} (attendu : ${EXPORT_FORMAT_VERSION}).`,
    );
  }
  if (!payload.trip || !payload.trip.path || !payload.tripId) {
    throw new Error('Structure d\'export incomplète (trip / tripId manquant).');
  }
  if (!payload.trip.path.startsWith('trips/')) {
    throw new Error(`Chemin de voyage inattendu : ${payload.trip.path}`);
  }
}

function flattenTreeWrites(node, writes) {
  if (!node) return;
  writes.push({
    path: node.path,
    data: deserializeValue(node.data),
  });
  for (const coll of Object.values(node.subcollections || {})) {
    for (const child of Object.values(coll)) {
      flattenTreeWrites(child, writes);
    }
  }
}

async function commitWrites(db, writes, apply) {
  if (!apply) return;

  for (let offset = 0; offset < writes.length; offset += BATCH_SIZE) {
    const chunk = writes.slice(offset, offset + BATCH_SIZE);
    const batch = db.batch();
    for (const entry of chunk) {
      batch.set(db.doc(entry.path), entry.data, { merge: false });
    }
    await batch.commit();
  }
}

async function partitionUserWritesByExistence(db, userWrites) {
  const missingWrites = [];
  const existingWrites = [];

  for (let offset = 0; offset < userWrites.length; offset += BATCH_SIZE) {
    const chunk = userWrites.slice(offset, offset + BATCH_SIZE);
    const refs = chunk.map((entry) => db.doc(entry.path));
    const snaps = await db.getAll(...refs);
    for (let index = 0; index < chunk.length; index++) {
      if (snaps[index]?.exists) {
        existingWrites.push(chunk[index]);
      } else {
        missingWrites.push(chunk[index]);
      }
    }
  }

  return { missingWrites, existingWrites };
}

async function runImport(db, opts) {
  if (!opts.filePath) {
    throw new Error('Import : --file <export.json> est obligatoire.');
  }

  const filePath = path.resolve(process.cwd(), opts.filePath);
  if (!fs.existsSync(filePath)) {
    throw new Error(`Fichier introuvable : ${filePath}`);
  }

  const payload = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  validateExportPayload(payload);

  const tripWrites = [];
  flattenTreeWrites(payload.trip, tripWrites);

  const userWrites = [];
  for (const [uid, userNode] of Object.entries(payload.users || {})) {
    if (!userNode?.path || !userNode?.data) continue;
    userWrites.push({
      path: userNode.path || `users/${uid}`,
      data: deserializeValue(userNode.data),
    });
  }

  const tripId = payload.tripId;
  const existingTrip = await db.collection('trips').doc(tripId).get();

  console.log(`\nFichier    : ${filePath}`);
  console.log(`  Exporté le : ${payload.exportedAt || '?'}`);
  console.log(`  Projet src.: ${payload.sourceProjectId || '?'}`);
  console.log(`  Voyage     : trips/${tripId}`);
  console.log(`  Documents  : ${tripWrites.length} (arbre voyage)`);
  console.log(`  Utilisateurs: ${userWrites.length}`);
  console.log(
    `  Mode       : ${opts.dryRun ? 'DRY-RUN (aucune écriture)' : 'APPLY (écriture Firestore)'}`,
  );

  if (existingTrip.exists) {
    console.log(`\nLe voyage trips/${tripId} existe déjà dans ce projet.`);
    if (opts.apply) {
      throw new Error(
        `Import refusé : trips/${tripId} existe déjà. Supprimez le voyage cible avant de relancer l'import.`
      );
    } else if (!opts.apply) {
      console.log('(dry-run : --apply serait refusé tant que le voyage existe déjà)');
    }
  }

  if (!opts.apply) {
    console.log('\nDry-run : aucune écriture. Relancez avec --apply pour importer.');
    return;
  }

  const userPlan = await partitionUserWritesByExistence(db, userWrites);

  console.log('\nCréation des utilisateurs manquants…');
  await commitWrites(db, userPlan.missingWrites, true);
  console.log(`  ${userPlan.missingWrites.length} document(s) users/* créé(s).`);
  if (userPlan.existingWrites.length > 0) {
    console.log(
      `  ${userPlan.existingWrites.length} document(s) users/* existant(s) conservé(s).`
    );
  }

  console.log('Écriture du voyage et des sous-collections…');
  await commitWrites(db, tripWrites, true);
  console.log(`  ${tripWrites.length} document(s) écrit(s).`);

  console.log('\nImport terminé.');
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const opts = parseArgs(process.argv);

  if (!opts.keyPath) {
    console.error('Erreur : --key requis.');
    printUsageAndExit();
  }
  if (!opts.command) {
    console.error('Erreur : sous-commande "export" ou "import" requise.');
    printUsageAndExit();
  }

  const resolvedKey = path.resolve(process.cwd(), opts.keyPath);
  if (!fs.existsSync(resolvedKey)) {
    console.error(`Erreur : fichier introuvable : ${resolvedKey}`);
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(resolvedKey, 'utf8'));
  const app = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  const db = app.firestore();

  console.log(`Projet : ${serviceAccount.project_id}`);

  try {
    if (opts.command === 'export') {
      await runExport(db, serviceAccount, opts);
    } else if (opts.command === 'import') {
      await runImport(db, opts);
    } else {
      throw new Error(`Sous-commande inconnue : ${opts.command}`);
    }
  } finally {
    await app.delete();
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('Erreur fatale :', err.message ?? err);
    process.exit(1);
  });
}

module.exports = {
  parseArgs,
  partitionUserWritesByExistence,
  runImport,
  validateExportPayload,
};
