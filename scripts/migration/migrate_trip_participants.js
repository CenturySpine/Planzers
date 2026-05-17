/**
 * migrate_trip_participants.js
 *
 * Phase 1 de la migration des participants :
 *   1. Nettoie les anciennes permissions granulaires du sous-objet
 *      `permissions.participants` (createParticipant, deletePlaceholderParticipant,
 *      deleteRegisteredParticipant, editPlaceholderParticipant) et y injecte
 *      `manageParticipants: "owner"`.
 *   2. Pour chaque voyage portant encore `memberIds` + `memberPublicLabels`,
 *      crée les documents correspondants dans la sous-collection `participants`
 *      (si un doc avec le même userId / même label##ph_ n'existe pas déjà),
 *      puis supprime `memberIds` et `memberPublicLabels` du document voyage.
 *
 * Usage :
 *   node migrate_trip_participants.js --key <service-account.json> [options]
 *
 * Options :
 *   --apply          Écriture réelle (par défaut : dry-run)
 *   --dry-run        Aperçu sans écriture (défaut)
 *   --verbose        Afficher le détail de chaque participant créé
 *
 * Le script liste d'abord tous les voyages éligibles, te demande d'en choisir un,
 * puis applique la migration uniquement sur ce voyage (dry-run ou apply selon le flag).
 *
 * Exemples :
 *   node migrate_trip_participants.js --key ./planerz-preview.json --verbose
 *   node migrate_trip_participants.js --key ./planerz-preview.json --apply
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const PLACEHOLDER_PREFIX = 'ph_';
const LEGACY_PERMISSION_KEYS = [
  'createParticipant',
  'deletePlaceholderParticipant',
  'deleteRegisteredParticipant',
  'editPlaceholderParticipant',
];
const NEW_PERMISSION_KEY = 'manageParticipants';
const NEW_PERMISSION_DEFAULT = 'owner';
const BATCH_SIZE = 400;

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const opts = { keyPath: '', apply: false, dryRun: true, verbose: false };

  for (let i = 2; i < argv.length; i++) {
    const token = argv[i];
    if (token === '--apply') { opts.apply = true; opts.dryRun = false; continue; }
    if (token === '--dry-run') { opts.dryRun = true; opts.apply = false; continue; }
    if (token === '--verbose') { opts.verbose = true; continue; }
    if (!token.startsWith('--')) continue;

    const eqIdx = token.indexOf('=');
    const flag = eqIdx >= 0 ? token.slice(0, eqIdx) : token;
    const inlineVal = eqIdx >= 0 ? token.slice(eqIdx + 1) : null;
    const nextVal = inlineVal ?? argv[i + 1];
    const consume = () => { if (inlineVal === null) i++; };

    if (flag === '--key') { opts.keyPath = (nextVal || '').trim(); consume(); }
  }

  return opts;
}

function printUsageAndExit() {
  console.log(`
Usage:
  node migrate_trip_participants.js --key <service-account.json> [options]

Required:
  --key <path>    Chemin vers le JSON du compte de service Firebase

Optional:
  --apply         Écriture réelle (par défaut : dry-run)
  --dry-run       Aperçu sans écriture
  --verbose       Afficher le détail de chaque participant créé / permission modifiée
`);
  process.exit(1);
}

function prompt(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Critères doc-level uniquement (pas de lecture de sous-collections). */
function needsDocMigration(data) {
  const perms = (data.permissions && data.permissions.participants) || {};
  const hasLegacyPerms = LEGACY_PERMISSION_KEYS.some((k) => perms[k] !== undefined);
  // memberPublicLabels est supprimé après migration ; memberIds seul ne suffit pas
  const hasLegacyMembers = data.memberPublicLabels != null;
  return hasLegacyPerms || hasLegacyMembers;
}

/**
 * Construit le map { userId -> label } issu de memberIds + memberPublicLabels.
 * Pour les ph_ : le label dans la sous-collection sera "label##ph_xxx".
 */
function buildMembersToCreate(memberIds, memberPublicLabels) {
  const result = [];
  for (let i = 0; i < memberIds.length; i++) {
    const uid = memberIds[i];
    const label = (memberPublicLabels && memberPublicLabels[uid]) || '';

    if (uid.startsWith(PLACEHOLDER_PREFIX)) {
      result.push({ userId: null, participantName: label ? `${label}##${uid}` : uid });
    } else {
      result.push({ userId: uid, participantName: label || uid });
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Formate un Timestamp Firestore (ou Date JS) en clé 'YYYY-MM-DD'. */
function toDateKey(tsOrDate) {
  const d = tsOrDate && typeof tsOrDate.toDate === 'function'
    ? tsOrDate.toDate()
    : tsOrDate instanceof Date ? tsOrDate : null;
  if (!d) return null;
  const y = d.getFullYear().toString().padStart(4, '0');
  const m = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/**
 * Construit les champs de séjour par défaut à partir du document voyage.
 * Retourne null si le voyage n'a pas de dates (pas de séjour à injecter).
 */
function buildDefaultStayFields(tripData) {
  const startKey = toDateKey(tripData.startDate);
  if (!startKey) return null;

  const endKey = toDateKey(tripData.endDate) || startKey;
  const startPart = tripData.tripStartDayPart || 'evening';
  const endPart   = tripData.tripEndDayPart   || 'morning';

  return {
    stayStartDateKey: startKey,
    stayStartDayPart: startPart,
    stayEndDateKey: endKey,
    stayEndDayPart: endPart,
  };
}

// ---------------------------------------------------------------------------
// Core migration — single trip
// ---------------------------------------------------------------------------

async function migrateTripDoc(tripRef, data, opts, stats) {
  const tripId = tripRef.id;
  const perms = (data.permissions && data.permissions.participants) || {};

  // --- 1. Permissions ---
  const legacyPresent = LEGACY_PERMISSION_KEYS.filter((k) => perms[k] !== undefined);
  const needsPermUpdate = legacyPresent.length > 0;

  if (needsPermUpdate) {
    stats.tripsWithLegacyPerms++;
    if (opts.verbose) {
      console.log(`  PERMS  ${tripId}: supprime [${legacyPresent.join(', ')}], injecte ${NEW_PERMISSION_KEY}=owner`);
    }
  }

  // --- 2. Members ---
  const memberIds = Array.isArray(data.memberIds) ? data.memberIds : [];
  const memberPublicLabels = data.memberPublicLabels || {};
  const membersToCreate = memberIds.length > 0
    ? buildMembersToCreate(memberIds, memberPublicLabels)
    : [];

  if (membersToCreate.length > 0) {
    stats.tripsWithLegacyMembers++;
    if (opts.verbose) {
      console.log(`  MEMBERS ${tripId}: ${membersToCreate.length} participant(s) à créer`);
      for (const m of membersToCreate) {
        console.log(`    -> participantName="${m.participantName}" userId=${m.userId ?? '(ph_)'}`);
      }
      const realUserIds = memberIds.filter((uid) => !uid.startsWith(PLACEHOLDER_PREFIX));
      console.log(`  memberIds rebuilt: [${realUserIds.join(', ')}]`);
    }
  }

  // --- 3. members subcollection preview (dry-run) ---
  const membersSubSnap = await tripRef.collection('members').get();
  if (!membersSubSnap.empty) {
    stats.tripsWithMembersSubcoll++;
    if (opts.verbose) {
      console.log(`  MEMBERS_SUBCOLL ${tripId}: ${membersSubSnap.size} doc(s) à fusionner dans participants`);
      for (const mDoc of membersSubSnap.docs) {
        const fields = Object.keys(mDoc.data()).join(', ');
        console.log(`    members/${mDoc.id} -> [${fields}]`);
      }
    }
  }

  if (opts.dryRun) {
    // Aperçu étape 4 : participants claimed sans doc members
    const previewParticipants = await tripRef.collection('participants').get();
    const memberUids = new Set(membersSubSnap.docs.map((d) => d.id));
    const defaultStayPreview = buildDefaultStayFields(data);
    let defaultCount = 0;
    for (const pDoc of previewParticipants.docs) {
      const pData = pDoc.data();
      const uid = pData.userId;
      if (!uid || memberUids.has(uid)) continue;
      const alreadyHasProfile = pData.cupidonEnabled !== undefined
        || pData.phoneVisibility !== undefined
        || pData.stayStartDateKey !== undefined;
      if (alreadyHasProfile) continue;
      defaultCount++;
      if (opts.verbose) {
        const stayInfo = defaultStayPreview
          ? `${defaultStayPreview.stayStartDateKey} ${defaultStayPreview.stayStartDayPart} → ${defaultStayPreview.stayEndDateKey} ${defaultStayPreview.stayEndDayPart}`
          : '(pas de dates voyage)';
        console.log(`  DEFAULT participant/${pDoc.id} userId=${uid} -> cupidon=false, phone=nobody, séjour: ${stayInfo}`);
      }
    }
    if (defaultCount > 0) {
      console.log(`  ${defaultCount} participant(s) recevront les valeurs par défaut`);
    }
    stats.tripsProcessed++;
    return;
  }

  // --- Apply ---
  const db = tripRef.firestore;

  // 2a. Vérifier les participants déjà présents (pour éviter les doublons)
  const existingSnapshot = await tripRef.collection('participants').get();
  const existingUserIds = new Set();
  const existingPhLabels = new Set();
  for (const doc of existingSnapshot.docs) {
    const d = doc.data();
    if (d.userId) existingUserIds.add(d.userId);
    else if (d.participantName) existingPhLabels.add(d.participantName);
  }

  // 2b. Créer les participants manquants
  let participantBatch = db.batch();
  let batchCount = 0;

  for (const member of membersToCreate) {
    const isDuplicate = member.userId
      ? existingUserIds.has(member.userId)
      : existingPhLabels.has(member.participantName);

    if (isDuplicate) {
      stats.participantsSkipped++;
      if (opts.verbose) {
        console.log(`    SKIP (déjà présent): "${member.participantName}"`);
      }
      continue;
    }

    const newRef = tripRef.collection('participants').doc();
    const docData = { participantName: member.participantName };
    if (member.userId) docData.userId = member.userId;

    participantBatch.set(newRef, docData);
    batchCount++;
    stats.participantsCreated++;

    if (batchCount === BATCH_SIZE) {
      await participantBatch.commit();
      participantBatch = db.batch();
      batchCount = 0;
    }
  }
  if (batchCount > 0) {
    await participantBatch.commit();
  }

  // 2c. Mise à jour du document voyage (permissions + suppression des legacy fields)
  const tripUpdate = {};

  if (needsPermUpdate) {
    for (const k of legacyPresent) {
      tripUpdate[`permissions.participants.${k}`] = admin.firestore.FieldValue.delete();
    }
    // N'écrase que si la clé n'existe pas encore
    if (perms[NEW_PERMISSION_KEY] === undefined) {
      tripUpdate[`permissions.participants.${NEW_PERMISSION_KEY}`] = NEW_PERMISSION_DEFAULT;
    }
  }

  if (membersToCreate.length > 0) {
    // Garde uniquement les UIDs réels (hors ph_) dans memberIds
    const realUserIds = memberIds.filter((uid) => !uid.startsWith(PLACEHOLDER_PREFIX));
    tripUpdate['memberIds'] = realUserIds;
    tripUpdate['memberPublicLabels'] = admin.firestore.FieldValue.delete();
    if (opts.verbose) {
      console.log(`  memberIds rebuilt: [${realUserIds.join(', ')}]`);
    }
  }

  if (Object.keys(tripUpdate).length > 0) {
    await tripRef.update(tripUpdate);
  }

  // --- 3. members subcollection → participants ---
  if (!membersSubSnap.empty) {
    // Relit les participants après l'étape 2 pour avoir les docs fraîchement créés
    const participantsSnap = await tripRef.collection('participants').get();
    const userIdToParticipantRef = new Map();
    for (const doc of participantsSnap.docs) {
      const uid = doc.data().userId;
      if (uid) userIdToParticipantRef.set(uid, doc.ref);
    }

    const MEMBER_FIELDS = [
      'stayStartDateKey', 'stayStartDayPart',
      'stayEndDateKey', 'stayEndDayPart',
      'cupidonEnabled', 'cupidonUpdatedAt',
      'phoneVisibility', 'updatedAt',
    ];

    let batch = db.batch();
    let opCount = 0;

    const flushIfNeeded = async () => {
      if (opCount >= BATCH_SIZE - 2) {
        await batch.commit();
        batch = db.batch();
        opCount = 0;
      }
    };

    for (const memberDoc of membersSubSnap.docs) {
      const uid = memberDoc.id;
      const memberData = memberDoc.data();
      const participantRef = userIdToParticipantRef.get(uid);

      if (!participantRef) {
        stats.membersMissingParticipant++;
        console.warn(`  WARN  members/${uid} -> aucun participant avec userId=${uid}, doc ignoré`);
        // Supprime quand même le doc members orphelin
        await flushIfNeeded();
        batch.delete(memberDoc.ref);
        opCount++;
        stats.membersDeleted++;
        continue;
      }

      const fieldsToMerge = {};
      for (const field of MEMBER_FIELDS) {
        if (memberData[field] !== undefined) fieldsToMerge[field] = memberData[field];
      }

      await flushIfNeeded();

      if (Object.keys(fieldsToMerge).length > 0) {
        batch.update(participantRef, fieldsToMerge);
        opCount++;
        stats.membersTransferred++;
        if (opts.verbose) {
          console.log(`  MERGE members/${uid} -> participant/${participantRef.id} [${Object.keys(fieldsToMerge).join(', ')}]`);
        }
      }

      batch.delete(memberDoc.ref);
      opCount++;
      stats.membersDeleted++;
    }

    if (opCount > 0) await batch.commit();
  }

  // --- 4. Participants avec userId mais sans doc members → defaults ---
  // Relit les participants (état final après étapes 2 et 3)
  const finalParticipantsSnap = await tripRef.collection('participants').get();
  // Reconstruit l'index userId → participantRef après les étapes précédentes
  const remainingMemberIds = new Set();
  // Récupère les UIDs encore présents dans members (déjà vidée à l'étape 3 si apply)
  // En dry-run membersSubSnap contient encore les docs
  for (const mDoc of membersSubSnap.docs) {
    remainingMemberIds.add(mDoc.id);
  }

  const defaultStay = buildDefaultStayFields(data);
  const defaultFields = {
    cupidonEnabled: false,
    phoneVisibility: 'nobody',
    ...(defaultStay || {}),
  };

  let defaultsBatch = db.batch();
  let defaultsOpCount = 0;

  for (const pDoc of finalParticipantsSnap.docs) {
    const pData = pDoc.data();
    const uid = pData.userId;
    if (!uid) continue; // ph_ ou unclaimed, on ignore

    // Déjà traité à l'étape 3 (avait un doc members) → skip
    if (remainingMemberIds.has(uid)) continue;

    // Vérifie si les champs de profil sont déjà présents (migration déjà faite)
    const alreadyHasProfile = pData.cupidonEnabled !== undefined
      || pData.phoneVisibility !== undefined
      || pData.stayStartDateKey !== undefined;
    if (alreadyHasProfile) continue;

    if (opts.verbose) {
      const stayInfo = defaultStay
        ? `${defaultStay.stayStartDateKey} ${defaultStay.stayStartDayPart} → ${defaultStay.stayEndDateKey} ${defaultStay.stayEndDayPart}`
        : '(pas de dates voyage)';
      console.log(`  DEFAULT participant/${pDoc.id} userId=${uid} -> cupidon=false, phone=nobody, séjour: ${stayInfo}`);
    }

    defaultsBatch.update(pDoc.ref, defaultFields);
    defaultsOpCount++;
    stats.participantsDefaulted++;

    if (defaultsOpCount >= BATCH_SIZE) {
      await defaultsBatch.commit();
      defaultsBatch = db.batch();
      defaultsOpCount = 0;
    }
  }

  if (defaultsOpCount > 0) await defaultsBatch.commit();

  stats.tripsProcessed++;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function discoverEligibleTrips(db) {
  // tripId -> { ref, data, hasMembersSubcoll }
  const byTripId = new Map();

  // Phase 1 : scan doc-level (permissions legacy + memberPublicLabels)
  let lastDoc = null;
  while (true) {
    let query = db.collection('trips')
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(BATCH_SIZE);
    if (lastDoc) query = query.startAfter(lastDoc);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      if (needsDocMigration(doc.data())) {
        byTripId.set(doc.id, { ref: doc.ref, data: doc.data(), hasMembersSubcoll: false });
      }
      lastDoc = doc;
    }

    if (snapshot.size < BATCH_SIZE) break;
  }

  // Phase 2 : collectionGroup 'members' → trips ayant encore cette sous-collection
  let lastMemberDoc = null;
  while (true) {
    let query = db.collectionGroup('members')
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(BATCH_SIZE);
    if (lastMemberDoc) query = query.startAfter(lastMemberDoc);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      // Chemin attendu : trips/{tripId}/members/{uid}
      const parts = doc.ref.path.split('/');
      if (parts.length !== 4 || parts[0] !== 'trips' || parts[2] !== 'members') continue;

      const tripId = parts[1];
      if (byTripId.has(tripId)) {
        byTripId.get(tripId).hasMembersSubcoll = true;
      } else {
        const tripRef = db.collection('trips').doc(tripId);
        const tripDoc = await tripRef.get();
        if (tripDoc.exists) {
          byTripId.set(tripId, { ref: tripRef, data: tripDoc.data(), hasMembersSubcoll: true });
        }
      }
      lastMemberDoc = doc;
    }

    if (snapshot.size < BATCH_SIZE) break;
  }

  return [...byTripId.values()];
}

async function run() {
  const opts = parseArgs(process.argv);
  if (!opts.keyPath) printUsageAndExit();

  const resolvedKey = path.resolve(process.cwd(), opts.keyPath);
  const serviceAccount = JSON.parse(fs.readFileSync(resolvedKey, 'utf8'));

  const app = admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = app.firestore();

  console.log(`Mode     : ${opts.dryRun ? 'DRY-RUN (lecture seule)' : 'APPLY (écriture Firestore)'}`);
  console.log(`Projet   : ${serviceAccount.project_id}`);
  console.log('');
  console.log('Scan des voyages éligibles...');

  const eligible = await discoverEligibleTrips(db);

  if (eligible.length === 0) {
    console.log('Aucun voyage à migrer.');
    await app.delete();
    return;
  }

  console.log(`\n${eligible.length} voyage(s) éligible(s) :\n`);
  eligible.forEach((entry, idx) => {
    const title = (entry.data.title || '').trim() || '(sans titre)';
    const perms = (entry.data.permissions && entry.data.permissions.participants) || {};
    const hasLegacyPerms = LEGACY_PERMISSION_KEYS.some((k) => perms[k] !== undefined);
    const hasLegacyMembers = entry.data.memberPublicLabels != null;
    const memberCount = Array.isArray(entry.data.memberIds) ? entry.data.memberIds.length : 0;
    const tags = [
      hasLegacyPerms ? 'perms' : null,
      hasLegacyMembers ? `${memberCount} membres` : null,
      entry.hasMembersSubcoll ? 'subcoll members' : null,
    ].filter(Boolean).join(', ');
    console.log(`  [${idx + 1}] ${title}  (${entry.ref.id})  [${tags}]`);
  });

  console.log('');
  const answer = await prompt('Numéro du voyage à migrer (ou "q" pour quitter) : ');

  if (answer.toLowerCase() === 'q' || answer === '') {
    console.log('Annulé.');
    await app.delete();
    return;
  }

  const choice = parseInt(answer, 10);
  if (!Number.isFinite(choice) || choice < 1 || choice > eligible.length) {
    console.error(`Choix invalide : "${answer}"`);
    await app.delete();
    process.exit(1);
  }

  const selected = eligible[choice - 1];
  const title = (selected.data.title || '').trim() || '(sans titre)';
  console.log(`\nVoyage sélectionné : "${title}" (${selected.ref.id})`);
  console.log('');

  const stats = {
    tripsProcessed: 0,
    tripsWithLegacyPerms: 0,
    tripsWithLegacyMembers: 0,
    tripsWithMembersSubcoll: 0,
    participantsCreated: 0,
    participantsSkipped: 0,
    membersTransferred: 0,
    membersDeleted: 0,
    membersMissingParticipant: 0,
    participantsDefaulted: 0,
    errors: 0,
  };

  try {
    await migrateTripDoc(selected.ref, selected.data, opts, stats);
  } catch (err) {
    stats.errors++;
    console.error(`ERR  trips/${selected.ref.id} -> ${err.message}`);
  }

  console.log('');
  console.log('--- Résultat ---');
  if (opts.dryRun) {
    console.log('(dry-run — aucune écriture effectuée)');
  }
  console.log(`Permissions legacy nettoyées  : ${stats.tripsWithLegacyPerms > 0 ? 'oui' : 'non'}`);
  console.log(`Membres legacy (memberIds)    : ${stats.tripsWithLegacyMembers > 0 ? 'oui' : 'non'}`);
  console.log(`Sous-collection members       : ${stats.tripsWithMembersSubcoll > 0 ? 'oui' : 'non'}`);
  if (!opts.dryRun) {
    console.log(`Participants créés            : ${stats.participantsCreated}`);
    console.log(`Participants ignorés (déjà présents) : ${stats.participantsSkipped}`);
    console.log(`Docs members fusionnés       : ${stats.membersTransferred}`);
    console.log(`Docs members supprimés       : ${stats.membersDeleted}`);
    if (stats.membersMissingParticipant > 0) {
      console.log(`WARN membres sans participant : ${stats.membersMissingParticipant}`);
    }
    console.log(`Participants defaults injectés : ${stats.participantsDefaulted}`);
  }
  console.log(`Erreurs                       : ${stats.errors}`);

  await app.delete();
}

run().catch((err) => {
  console.error('Erreur fatale :', err);
  process.exit(1);
});
