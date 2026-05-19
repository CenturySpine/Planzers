/**
 * migrate_trip_participants_phase2.js
 *
 * Phase 2 de la migration des participants :
 *   Remplace les UIDs Firebase Auth par les participant doc IDs dans toutes
 *   les sous-collections d'un voyage :
 *     - carpools    : driverUserId (rename → driverParticipantId) + assignedParticipantIds
 *     - rooms       : beds[].assignedMemberIds + assignedMemberIds root (supprimé)
 *     - expenseGroups : visibleToMemberIds
 *     - expenses    : participantIds, paidBy, participantShares (clés)
 *     - expenseSettledTransfers : fromUserId, toUserId + id document
 *       (même schéma que l'app : groupId__EUR__from__to__cents)
 *     - meals       : participantIds, chefParticipantId
 *
 * Prérequis : Phase 1 doit avoir été exécutée (sous-collection `participants`
 *   peuplée). Le script bloque si `participants` est vide ou absent.
 *
 * La map uid → participantDocId est construite depuis `participants` :
 *   - Participants réels  : doc.data().userId  → doc.id
 *   - Placeholders (ph_)  : parse "label##ph_xxx" dans participantName → "ph_xxx" → doc.id
 *
 * Avant toute écriture, le script vérifie que chaque ID trouvé dans les
 * champs à migrer est soit dans la map (sera remappé), soit déjà un
 * participant doc ID (déjà migré). Tout ID inconnu des deux sets provoque
 * un arrêt immédiat avec rapport détaillé.
 *
 * Usage :
 *   node migrate_trip_participants_phase2.js --key <service-account.json> [options]
 *
 * Options :
 *   --apply          Écriture réelle (par défaut : dry-run)
 *   --dry-run        Aperçu sans écriture (défaut)
 *   --verbose        Afficher le détail de chaque remplacement d'ID
 *
 * Exemples :
 *   node migrate_trip_participants_phase2.js --key ./planerz-preview.json --verbose
 *   node migrate_trip_participants_phase2.js --key ./planerz-preview.json --apply
 */

'use strict';

const admin = require('firebase-admin');
const fs    = require('fs');
const path  = require('path');
const readline = require('readline');

const PLACEHOLDER_PREFIX = 'ph_';
const BATCH_SIZE = 400;

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const opts = { keyPath: '', apply: false, dryRun: true, verbose: false };
  for (let i = 2; i < argv.length; i++) {
    const token = argv[i];
    if (token === '--apply')   { opts.apply = true; opts.dryRun = false; continue; }
    if (token === '--dry-run') { opts.dryRun = true; opts.apply = false; continue; }
    if (token === '--verbose') { opts.verbose = true; continue; }
    if (!token.startsWith('--')) continue;
    const eqIdx = token.indexOf('=');
    const flag  = eqIdx >= 0 ? token.slice(0, eqIdx) : token;
    const inlineVal = eqIdx >= 0 ? token.slice(eqIdx + 1) : null;
    const nextVal   = inlineVal ?? argv[i + 1];
    const consume   = () => { if (inlineVal === null) i++; };
    if (flag === '--key') { opts.keyPath = (nextVal || '').trim(); consume(); }
  }
  return opts;
}

function printUsageAndExit() {
  console.log(`
Usage:
  node migrate_trip_participants_phase2.js --key <service-account.json> [options]

Required:
  --key <path>    Chemin vers le JSON du compte de service Firebase

Optional:
  --apply         Écriture réelle (par défaut : dry-run)
  --dry-run       Aperçu sans écriture
  --verbose       Afficher le détail de chaque remplacement d'ID
`);
  process.exit(1);
}

function prompt(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => { rl.close(); resolve(answer.trim()); });
  });
}

// ---------------------------------------------------------------------------
// Maps : uid → participantDocId  +  set de tous les participant doc IDs
// ---------------------------------------------------------------------------

/**
 * Construit deux structures depuis la sous-collection `participants` :
 *   - uidMap       : Map<uid, participantDocId>  (pour remapper les UIDs)
 *   - allDocIds    : Set<participantDocId>        (pour valider les IDs déjà migrés)
 *
 * Retourne null si la sous-collection est vide (Phase 1 non faite).
 */
async function buildParticipantMaps(tripRef) {
  const snap = await tripRef.collection('participants').get();
  if (snap.empty) return null;

  const uidMap    = new Map();
  const allDocIds = new Set();
  let needsNameCleanup = false;

  for (const doc of snap.docs) {
    allDocIds.add(doc.id);
    const data = doc.data();

    if (data.userId) {
      uidMap.set(data.userId, doc.id);
    } else if (data.participantName) {
      // "label##ph_xxx"  ou  "ph_xxx"
      const name   = data.participantName;
      const sepIdx = name.lastIndexOf('##');
      const phPart = sepIdx >= 0 ? name.slice(sepIdx + 2) : name;
      if (phPart.startsWith(PLACEHOLDER_PREFIX)) {
        uidMap.set(phPart, doc.id);
      }
      if (sepIdx >= 0) needsNameCleanup = true;
    }
  }

  return { uidMap, allDocIds, needsNameCleanup };
}

// ---------------------------------------------------------------------------
// expenseSettledTransfers — doc id (aligné sur expenses_repository.dart)
// ---------------------------------------------------------------------------

/**
 * Parse un id du type groupId__EUR__fromUserId__toUserId__cents
 * (groupId sans "__" ; les UIDs non plus).
 */
function parseSettledTransferDocId(docId) {
  const parts = docId.split('__');
  if (parts.length < 5) return null;
  const cents = parts[parts.length - 1];
  if (!/^\d+$/.test(cents)) return null;
  const toUserId = parts[parts.length - 2];
  const fromUserId = parts[parts.length - 3];
  const currency = parts[parts.length - 4];
  const groupId = parts.slice(0, parts.length - 4).join('__');
  if (!groupId || !currency || !fromUserId || !toUserId) return null;
  return { groupId, currency, fromUserId, toUserId, cents };
}

function buildSettledTransferDocId(groupId, currency, fromUserId, toUserId, amount) {
  const cents = Math.round(Number(amount) * 100);
  return `${groupId.trim()}__${currency.trim().toUpperCase()}__${fromUserId.trim()}__${toUserId.trim()}__${cents}`;
}

/** Résout from/to (champs, sinon segments de l'id document). */
function resolveSettledTransferMemberIds(data, docId, uidMap) {
  const parsed = parseSettledTransferDocId(docId);
  const fromRaw = ((data.fromUserId || '') + '').trim() || parsed?.fromUserId || '';
  const toRaw = ((data.toUserId || '') + '').trim() || parsed?.toUserId || '';
  return {
    fromRaw,
    toRaw,
    fromResolved: remapOne(fromRaw, uidMap).newId,
    toResolved: remapOne(toRaw, uidMap).newId,
    parsed,
  };
}

// ---------------------------------------------------------------------------
// Remap helpers
// ---------------------------------------------------------------------------

/**
 * Remaps a single ID string.
 *   - In uidMap           → { newId: <mapped>, changed: <bool> }
 *   - Not in uidMap       → { newId: id, changed: false }
 */
function remapOne(id, uidMap) {
  if (!id || typeof id !== 'string') return { newId: id, changed: false };
  const mapped = uidMap.get(id);
  if (mapped !== undefined) return { newId: mapped, changed: mapped !== id };
  return { newId: id, changed: false };
}

/**
 * Remaps an array of ID strings (only entries present in uidMap).
 * Deduplicates after remapping (handles mixed UID + doc ID arrays).
 * Returns { newIds, changed }.
 */
function remapArray(ids, uidMap) {
  if (!Array.isArray(ids)) return { newIds: ids, changed: false };
  let changed = false;
  const seen = new Set();
  const newIds = [];
  for (const id of ids) {
    const r = remapOne(id, uidMap);
    if (r.changed) changed = true;
    if (seen.has(r.newId)) {
      changed = true; // doublon supprimé
    } else {
      seen.add(r.newId);
      newIds.push(r.newId);
    }
  }
  return { newIds, changed };
}

/**
 * Remaps the keys of a plain object (only keys present in uidMap).
 * In case of collision (UID remaps to a doc ID already present as key),
 * the already-migrated doc ID value is kept and the UID entry is discarded.
 * Returns { newMap, changed }.
 */
function remapMapKeys(map, uidMap) {
  if (!map || typeof map !== 'object' || Array.isArray(map)) {
    return { newMap: map, changed: false };
  }
  let changed = false;
  const newMap = {};

  // Premier passage : clés déjà migrées (pas dans uidMap)
  for (const [key, value] of Object.entries(map)) {
    if (!uidMap.has(key)) newMap[key] = value;
  }

  // Deuxième passage : clés UID à remapper
  for (const [key, value] of Object.entries(map)) {
    if (!uidMap.has(key)) continue;
    const newKey = uidMap.get(key);
    if (newKey !== key) changed = true;
    if (!(newKey in newMap)) {
      newMap[newKey] = value;
    }
    // Collision : la valeur associée au doc ID existant est conservée
  }

  return { newMap, changed };
}

// ---------------------------------------------------------------------------
// Pre-flight validation
// ---------------------------------------------------------------------------

/**
 * Classe de statut d'un ID par rapport aux deux maps :
 *   'remap'           → dans uidMap, sera remappé
 *   'already-migrated'→ dans allDocIds mais pas dans uidMap, déjà un participant doc ID
 *   'unresolvable'    → absent des deux, non identifiable
 */
function classifyId(id, uidMap, allDocIds) {
  if (!id || typeof id !== 'string') return 'already-migrated';
  if (uidMap.has(id)) return 'remap';
  if (allDocIds.has(id)) return 'already-migrated';
  return 'unresolvable';
}

/**
 * Scanne les champs à migrer de toutes les sous-collections d'un voyage.
 * Retourne :
 *   needsMigration   : true si au moins un ID sera remappé
 *   unresolvable     : Map<collectionPath, string[]> — IDs ni dans uidMap ni dans allDocIds
 */
async function preFlightScan(tripRef, uidMap, allDocIds) {
  let needsMigration = false;
  const unresolvable = new Map(); // path → string[]

  const addUnresolvable = (collPath, id) => {
    if (!unresolvable.has(collPath)) unresolvable.set(collPath, []);
    unresolvable.get(collPath).push(id);
  };

  const check = (id, collPath) => {
    const cls = classifyId(id, uidMap, allDocIds);
    if (cls === 'remap')          needsMigration = true;
    if (cls === 'unresolvable')   addUnresolvable(collPath, id);
  };

  const checkArray = (ids, collPath) => {
    if (!Array.isArray(ids)) return;
    for (const id of ids) check(id, collPath);
  };

  // --- carpools ---
  const carpoolsSnap = await tripRef.collection('carpools').get();
  for (const doc of carpoolsSnap.docs) {
    const data = doc.data();
    const p = `carpools/${doc.id}`;
    const driverId = data.driverUserId ?? data.driverParticipantId;
    if (driverId) check(driverId, p);
    checkArray(data.assignedParticipantIds, p);
  }

  // --- rooms ---
  const roomsSnap = await tripRef.collection('rooms').get();
  for (const doc of roomsSnap.docs) {
    const data = doc.data();
    const p = `rooms/${doc.id}`;
    checkArray(data.assignedMemberIds, p);
    if (Array.isArray(data.beds)) {
      for (const bed of data.beds) checkArray(bed.assignedMemberIds, p);
    }
  }

  // --- expenseGroups (visibleToMemberIds) ---
  const groupsSnap = await tripRef.collection('expenseGroups').get();
  for (const groupDoc of groupsSnap.docs) {
    checkArray(groupDoc.data().visibleToMemberIds, `expenseGroups/${groupDoc.id}`);
  }

  // --- expenses (collection plate : trips/{tripId}/expenses/{expenseId}) ---
  const expensesSnap = await tripRef.collection('expenses').get();
  for (const expDoc of expensesSnap.docs) {
    const expData = expDoc.data();
    const ep = `expenses/${expDoc.id}`;
    if (expData.paidBy) check(expData.paidBy, ep);
    checkArray(expData.participantIds, ep);
    if (expData.participantShares && typeof expData.participantShares === 'object') {
      for (const key of Object.keys(expData.participantShares)) check(key, ep);
    }
  }

  // --- expenseSettledTransfers ---
  const settledSnap = await tripRef.collection('expenseSettledTransfers').get();
  for (const doc of settledSnap.docs) {
    const data = doc.data();
    const p = `expenseSettledTransfers/${doc.id}`;
    const { fromRaw, toRaw, fromResolved, toResolved, parsed } =
      resolveSettledTransferMemberIds(data, doc.id, uidMap);
    if (fromRaw) check(fromRaw, p);
    if (toRaw) check(toRaw, p);
    const groupId = ((data.groupId || '') + '').trim() || parsed?.groupId || '';
    const currency = ((data.currency || 'EUR') + '').trim().toUpperCase();
    const amount = typeof data.amount === 'number'
      ? data.amount
      : Number(parsed?.cents || 0) / 100;
    if (groupId && fromResolved && toResolved) {
      const expectedId = buildSettledTransferDocId(
        groupId, currency, fromResolved, toResolved, amount,
      );
      if (expectedId !== doc.id) needsMigration = true;
    }
  }

  // --- meals ---
  const mealsSnap = await tripRef.collection('meals').get();
  for (const doc of mealsSnap.docs) {
    const data = doc.data();
    const p = `meals/${doc.id}`;
    checkArray(data.participantIds, p);
    if (data.chefParticipantId) check(data.chefParticipantId, p);
  }

  return { needsMigration, unresolvable };
}

// ---------------------------------------------------------------------------
// Per-collection migration
// ---------------------------------------------------------------------------

async function migrateCarpools(tripRef, uidMap, opts, stats) {
  const snap = await tripRef.collection('carpools').get();
  if (snap.empty) return;

  const db = tripRef.firestore;
  let batch   = db.batch();
  let opCount = 0;

  for (const doc of snap.docs) {
    const data   = doc.data();
    const update = {};
    let needsUpdate = false;

    // driverUserId (vieux nom) → driverParticipantId (nouveau nom + valeur remappée)
    const hasOldField = data.driverUserId !== undefined;
    const rawDriverId = hasOldField ? data.driverUserId : data.driverParticipantId;
    if (rawDriverId) {
      const { newId, changed } = remapOne(rawDriverId, uidMap);
      if (changed || hasOldField) {
        update['driverParticipantId'] = changed ? newId : rawDriverId;
        if (hasOldField) update['driverUserId'] = admin.firestore.FieldValue.delete();
        needsUpdate = true;
        if (opts.verbose) {
          const action = changed ? `${rawDriverId} → ${newId}` : `(valeur inchangée, renommage seul)`;
          console.log(`    carpools/${doc.id}  driverParticipantId: ${action}${hasOldField ? '  [+ delete driverUserId]' : ''}`);
        }
      }
    }

    if (Array.isArray(data.assignedParticipantIds)) {
      const { newIds, changed } = remapArray(data.assignedParticipantIds, uidMap);
      if (changed) {
        update['assignedParticipantIds'] = newIds;
        needsUpdate = true;
        if (opts.verbose) {
          console.log(`    carpools/${doc.id}  assignedParticipantIds:`);
          data.assignedParticipantIds.forEach((id, i) => {
            if (id !== newIds[i]) console.log(`      ${id} → ${newIds[i]}`);
          });
        }
      }
    }

    if (!needsUpdate) continue;
    stats.carpoolsUpdated++;
    if (opts.dryRun) continue;

    if (opCount >= BATCH_SIZE - 2) { await batch.commit(); batch = db.batch(); opCount = 0; }
    batch.update(doc.ref, update);
    opCount++;
  }

  if (!opts.dryRun && opCount > 0) await batch.commit();
}

async function migrateRooms(tripRef, uidMap, opts, stats) {
  const snap = await tripRef.collection('rooms').get();
  if (snap.empty) return;

  const db = tripRef.firestore;
  let batch   = db.batch();
  let opCount = 0;

  for (const doc of snap.docs) {
    const data   = doc.data();
    const update = {};
    let needsUpdate = false;

    // Root assignedMemberIds (legacy) — supprimer systématiquement si présent
    if (data.assignedMemberIds !== undefined) {
      update['assignedMemberIds'] = admin.firestore.FieldValue.delete();
      needsUpdate = true;
      if (opts.verbose) {
        console.log(`    rooms/${doc.id}  assignedMemberIds (root) → supprimé`);
      }
    }

    // beds[].assignedMemberIds — réécriture complète du tableau
    if (Array.isArray(data.beds)) {
      let bedsChanged = false;
      const newBeds = data.beds.map((bed, i) => {
        if (!Array.isArray(bed.assignedMemberIds)) return bed;
        const { newIds, changed } = remapArray(bed.assignedMemberIds, uidMap);
        if (changed) {
          bedsChanged = true;
          if (opts.verbose) {
            console.log(`    rooms/${doc.id}  bed[${i}] assignedMemberIds:`);
            bed.assignedMemberIds.forEach((id, j) => {
              if (id !== newIds[j]) console.log(`      ${id} → ${newIds[j]}`);
            });
          }
        }
        return changed ? { ...bed, assignedMemberIds: newIds } : bed;
      });

      if (bedsChanged) {
        update['beds'] = newBeds;
        needsUpdate = true;
      }
    }

    if (!needsUpdate) continue;
    stats.roomsUpdated++;
    if (opts.dryRun) continue;

    if (opCount >= BATCH_SIZE - 2) { await batch.commit(); batch = db.batch(); opCount = 0; }
    batch.update(doc.ref, update);
    opCount++;
  }

  if (!opts.dryRun && opCount > 0) await batch.commit();
}

async function migrateExpenseGroups(tripRef, uidMap, opts, stats) {
  const groupsSnap = await tripRef.collection('expenseGroups').get();
  if (groupsSnap.empty) return;

  const db = tripRef.firestore;
  let batch   = db.batch();
  let opCount = 0;

  for (const groupDoc of groupsSnap.docs) {
    const groupData = groupDoc.data();
    if (!Array.isArray(groupData.visibleToMemberIds)) continue;

    const { newIds, changed } = remapArray(groupData.visibleToMemberIds, uidMap);
    if (!changed) continue;

    stats.expenseGroupsUpdated++;
    if (opts.verbose) {
      console.log(`    expenseGroups/${groupDoc.id}  visibleToMemberIds:`);
      groupData.visibleToMemberIds.forEach((id, i) => {
        if (id !== newIds[i]) console.log(`      ${id} → ${newIds[i]}`);
      });
    }
    if (opts.dryRun) continue;

    if (opCount >= BATCH_SIZE - 2) { await batch.commit(); batch = db.batch(); opCount = 0; }
    batch.update(groupDoc.ref, { visibleToMemberIds: newIds });
    opCount++;
  }

  if (!opts.dryRun && opCount > 0) await batch.commit();
}

async function migrateExpenses(tripRef, uidMap, opts, stats) {
  // Les dépenses sont dans la collection plate trips/{tripId}/expenses
  const expensesSnap = await tripRef.collection('expenses').get();
  if (expensesSnap.empty) return;

  const db = tripRef.firestore;
  let batch   = db.batch();
  let opCount = 0;

  for (const expDoc of expensesSnap.docs) {
    const expData   = expDoc.data();
    const expUpdate = {};
    let expNeedsUpdate = false;

    if (expData.paidBy) {
      const { newId, changed } = remapOne(expData.paidBy, uidMap);
      if (changed) {
        expUpdate['paidBy'] = newId;
        expNeedsUpdate = true;
        if (opts.verbose) {
          console.log(`    expenses/${expDoc.id}  paidBy: ${expData.paidBy} → ${newId}`);
        }
      }
    }

    if (Array.isArray(expData.participantIds)) {
      const { newIds, changed } = remapArray(expData.participantIds, uidMap);
      if (changed) {
        expUpdate['participantIds'] = newIds;
        expNeedsUpdate = true;
        if (opts.verbose) {
          console.log(`    expenses/${expDoc.id}  participantIds:`);
          expData.participantIds.forEach((id, i) => {
            if (id !== newIds[i]) console.log(`      ${id} → ${newIds[i]}`);
          });
        }
      }
    }

    if (expData.participantShares && typeof expData.participantShares === 'object') {
      const { newMap, changed } = remapMapKeys(expData.participantShares, uidMap);
      if (changed) {
        expUpdate['participantShares'] = newMap;
        expNeedsUpdate = true;
        if (opts.verbose) {
          console.log(`    expenses/${expDoc.id}  participantShares (clés):`);
          for (const [oldKey] of Object.entries(expData.participantShares)) {
            const r = remapOne(oldKey, uidMap);
            if (r.changed) console.log(`      ${oldKey} → ${r.newId}`);
          }
        }
      }
    }

    if (!expNeedsUpdate) continue;
    stats.expensesUpdated++;
    if (opts.dryRun) continue;

    if (opCount >= BATCH_SIZE - 2) { await batch.commit(); batch = db.batch(); opCount = 0; }
    batch.update(expDoc.ref, expUpdate);
    opCount++;
  }

  if (!opts.dryRun && opCount > 0) await batch.commit();
}

async function migrateExpenseSettledTransfers(tripRef, uidMap, opts, stats) {
  const snap = await tripRef.collection('expenseSettledTransfers').get();
  if (snap.empty) return;

  const db = tripRef.firestore;
  let batch   = db.batch();
  let opCount = 0;

  const commitIfNeeded = async () => {
    if (!opts.dryRun && opCount > 0) {
      await batch.commit();
      batch = db.batch();
      opCount = 0;
    }
  };

  for (const doc of snap.docs) {
    const data = doc.data();
    const { fromRaw, toRaw, fromResolved, toResolved, parsed } =
      resolveSettledTransferMemberIds(data, doc.id, uidMap);

    const groupId = ((data.groupId || '') + '').trim() || parsed?.groupId || '';
    const currency = ((data.currency || 'EUR') + '').trim().toUpperCase();
    const amount = typeof data.amount === 'number'
      ? data.amount
      : Number(parsed?.cents || 0) / 100;

    if (!groupId || !fromResolved || !toResolved) continue;

    const newDocId = buildSettledTransferDocId(
      groupId, currency, fromResolved, toResolved, amount,
    );
    const fieldsChanged = fromResolved !== fromRaw || toResolved !== toRaw;
    const idChanged = newDocId !== doc.id;

    if (!fieldsChanged && !idChanged) continue;

    stats.expenseSettledTransfersUpdated++;
    if (opts.verbose) {
      console.log(`    expenseSettledTransfers/${doc.id}`);
      if (fieldsChanged) {
        if (fromRaw !== fromResolved) {
          console.log(`      fromUserId: ${fromRaw} → ${fromResolved}`);
        }
        if (toRaw !== toResolved) {
          console.log(`      toUserId: ${toRaw} → ${toResolved}`);
        }
      }
      if (idChanged) {
        console.log(`      doc id: ${doc.id}`);
        console.log(`           → ${newDocId}`);
      }
    }
    if (opts.dryRun) continue;

    const payload = {
      groupId,
      fromUserId: fromResolved,
      toUserId: toResolved,
      amount,
      currency,
      createdAt: data.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
      createdBy: ((data.createdBy || '') + '').trim(),
    };

    if (idChanged) {
      if (opCount >= BATCH_SIZE - 2) await commitIfNeeded();
      batch.set(tripRef.collection('expenseSettledTransfers').doc(newDocId), payload);
      opCount++;
      if (opCount >= BATCH_SIZE - 1) await commitIfNeeded();
      batch.delete(doc.ref);
      opCount++;
    } else {
      if (opCount >= BATCH_SIZE - 2) await commitIfNeeded();
      batch.update(doc.ref, {
        fromUserId: fromResolved,
        toUserId: toResolved,
      });
      opCount++;
    }
  }

  await commitIfNeeded();
}

async function migrateMeals(tripRef, uidMap, opts, stats) {
  const snap = await tripRef.collection('meals').get();
  if (snap.empty) return;

  const db = tripRef.firestore;
  let batch   = db.batch();
  let opCount = 0;

  for (const doc of snap.docs) {
    const data   = doc.data();
    const update = {};
    let needsUpdate = false;

    if (Array.isArray(data.participantIds)) {
      const { newIds, changed } = remapArray(data.participantIds, uidMap);
      if (changed) {
        update['participantIds'] = newIds;
        needsUpdate = true;
        if (opts.verbose) {
          console.log(`    meals/${doc.id}  participantIds:`);
          data.participantIds.forEach((id, i) => {
            if (id !== newIds[i]) console.log(`      ${id} → ${newIds[i]}`);
          });
        }
      }
    }

    if (data.chefParticipantId) {
      const { newId, changed } = remapOne(data.chefParticipantId, uidMap);
      if (changed) {
        update['chefParticipantId'] = newId;
        needsUpdate = true;
        if (opts.verbose) {
          console.log(`    meals/${doc.id}  chefParticipantId: ${data.chefParticipantId} → ${newId}`);
        }
      }
    }

    if (!needsUpdate) continue;
    stats.mealsUpdated++;
    if (opts.dryRun) continue;

    if (opCount >= BATCH_SIZE - 2) { await batch.commit(); batch = db.batch(); opCount = 0; }
    batch.update(doc.ref, update);
    opCount++;
  }

  if (!opts.dryRun && opCount > 0) await batch.commit();
}

// ---------------------------------------------------------------------------
// participantCount initialisation
// ---------------------------------------------------------------------------

async function setParticipantCount(tripRef, allDocIds, opts, stats) {
  const count = allDocIds.size;
  const current = (await tripRef.get()).data()?.participantCount;
  if (current === count) return; // already correct

  stats.participantCountSet++;
  if (opts.verbose) {
    console.log(`    trip.participantCount: ${current ?? '(absent)'} → ${count}`);
  }
  if (!opts.dryRun) {
    await tripRef.update({ participantCount: count });
  }
}

// ---------------------------------------------------------------------------
// Participant name cleanup (strip ##ph_* suffix)
// ---------------------------------------------------------------------------

async function cleanupParticipantNames(tripRef, opts, stats) {
  const snap = await tripRef.collection('participants').get();
  if (snap.empty) return;

  const db = tripRef.firestore;
  let batch   = db.batch();
  let opCount = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (!data.participantName || typeof data.participantName !== 'string') continue;

    const sepIdx = data.participantName.lastIndexOf('##');
    if (sepIdx < 0) continue;

    const cleanName = data.participantName.slice(0, sepIdx);
    stats.participantsNamesCleaned++;

    if (opts.verbose) {
      console.log(`    participants/${doc.id}  participantName: "${data.participantName}" → "${cleanName}"`);
    }

    if (opts.dryRun) continue;

    if (opCount >= BATCH_SIZE - 2) { await batch.commit(); batch = db.batch(); opCount = 0; }
    batch.update(doc.ref, { participantName: cleanName });
    opCount++;
  }

  if (!opts.dryRun && opCount > 0) await batch.commit();
}

// ---------------------------------------------------------------------------
// Main trip migration
// ---------------------------------------------------------------------------

/**
 * Exécute la migration Phase 2 sur un seul voyage.
 * Retourne false si la validation pré-migration échoue.
 */
async function migrateTrip(tripRef, uidMap, allDocIds, opts, stats) {
  console.log('Validation pré-migration...');
  const { needsMigration, unresolvable } = await preFlightScan(tripRef, uidMap, allDocIds);

  if (unresolvable.size > 0) {
    console.error('\nERREUR — IDs non résolvables détectés. Migration annulée.');
    console.error('Corrigez ces entrées manuellement avant de relancer :\n');
    for (const [collPath, ids] of unresolvable.entries()) {
      console.error(`  ${collPath} :`);
      for (const id of ids) console.error(`    → ${id}`);
    }
    return false;
  }

  console.log('Validation OK — tous les IDs sont résolvables.\n');

  console.log('[carpools]');
  await migrateCarpools(tripRef, uidMap, opts, stats);
  console.log(`  → ${stats.carpoolsUpdated} carpool(s) ${opts.dryRun ? 'à mettre à jour' : 'mis à jour'}`);

  console.log('[rooms]');
  await migrateRooms(tripRef, uidMap, opts, stats);
  console.log(`  → ${stats.roomsUpdated} chambre(s) ${opts.dryRun ? 'à mettre à jour' : 'mises à jour'}`);

  console.log('[expenseGroups]');
  await migrateExpenseGroups(tripRef, uidMap, opts, stats);
  console.log(`  → ${stats.expenseGroupsUpdated} groupe(s) de dépenses ${opts.dryRun ? 'à mettre à jour' : 'mis à jour'}`);

  console.log('[expenses]');
  await migrateExpenses(tripRef, uidMap, opts, stats);
  console.log(`  → ${stats.expensesUpdated} dépense(s) ${opts.dryRun ? 'à mettre à jour' : 'mises à jour'}`);

  console.log('[expenseSettledTransfers]');
  await migrateExpenseSettledTransfers(tripRef, uidMap, opts, stats);
  console.log(`  → ${stats.expenseSettledTransfersUpdated} remboursement(s) enregistré(s) ${opts.dryRun ? 'à mettre à jour' : 'mis à jour'}`);

  console.log('[meals]');
  await migrateMeals(tripRef, uidMap, opts, stats);
  console.log(`  → ${stats.mealsUpdated} repas ${opts.dryRun ? 'à mettre à jour' : 'mis à jour'}`);

  console.log('[participants — nettoyage noms ph_]');
  await cleanupParticipantNames(tripRef, opts, stats);
  console.log(`  → ${stats.participantsNamesCleaned} nom(s) ${opts.dryRun ? 'à nettoyer' : 'nettoyé(s)'}`);

  console.log('[trip — participantCount]');
  await setParticipantCount(tripRef, allDocIds, opts, stats);
  console.log(`  → ${stats.participantCountSet} voyage(s) ${opts.dryRun ? 'à initialiser' : 'initialisé(s)'}`);

  return true;
}

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

async function discoverEligibleTrips(db) {
  const eligible = [];
  let lastDoc = null;

  while (true) {
    let query = db.collection('trips')
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(BATCH_SIZE);
    if (lastDoc) query = query.startAfter(lastDoc);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      const maps = await buildParticipantMaps(doc.ref);
      if (!maps) continue; // Phase 1 non faite

      const { needsMigration } = await preFlightScan(doc.ref, maps.uidMap, maps.allDocIds);
      const missingCount = doc.data().participantCount == null;
      if (needsMigration || maps.needsNameCleanup || missingCount) {
        eligible.push({ ref: doc.ref, data: doc.data(), uidMap: maps.uidMap, allDocIds: maps.allDocIds });
      }
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < BATCH_SIZE) break;
  }

  return eligible;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function run() {
  const opts = parseArgs(process.argv);
  if (!opts.keyPath) printUsageAndExit();

  const resolvedKey    = path.resolve(process.cwd(), opts.keyPath);
  const serviceAccount = JSON.parse(fs.readFileSync(resolvedKey, 'utf8'));

  const app = admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db  = app.firestore();

  console.log(`Mode     : ${opts.dryRun ? 'DRY-RUN (lecture seule)' : 'APPLY (écriture Firestore)'}`);
  console.log(`Projet   : ${serviceAccount.project_id}`);
  console.log('');
  console.log('Scan des voyages éligibles (Phase 2)...');

  const eligible = await discoverEligibleTrips(db);

  if (eligible.length === 0) {
    console.log('Aucun voyage à migrer en Phase 2.');
    await app.delete();
    return;
  }

  console.log(`\n${eligible.length} voyage(s) éligible(s) :\n`);
  eligible.forEach((entry, idx) => {
    const title = (entry.data.title || '').trim() || '(sans titre)';
    console.log(`  [${idx + 1}] ${title}  (${entry.ref.id})  [map: ${entry.uidMap.size} participant(s)]`);
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
  console.log(`Map participants   : ${selected.uidMap.size} entrée(s)\n`);

  if (opts.verbose) {
    console.log('Map uid → participantDocId :');
    for (const [uid, docId] of selected.uidMap.entries()) {
      console.log(`  ${uid} → ${docId}`);
    }
    console.log('');
  }

  const stats = {
    carpoolsUpdated:               0,
    roomsUpdated:                  0,
    expenseGroupsUpdated:          0,
    expensesUpdated:               0,
    expenseSettledTransfersUpdated: 0,
    mealsUpdated:                  0,
    participantsNamesCleaned:      0,
    participantCountSet:           0,
  };

  const success = await migrateTrip(
    selected.ref,
    selected.uidMap,
    selected.allDocIds,
    opts,
    stats,
  );

  console.log('');
  console.log('--- Résultat ---');
  if (!success) {
    console.log('Migration annulée (IDs non résolvables — voir détails ci-dessus).');
  } else {
    if (opts.dryRun) console.log('(dry-run — aucune écriture effectuée)');
    console.log(`Carpools mis à jour           : ${stats.carpoolsUpdated}`);
    console.log(`Chambres mises à jour         : ${stats.roomsUpdated}`);
    console.log(`Groupes de dépenses mis à jour: ${stats.expenseGroupsUpdated}`);
    console.log(`Dépenses mises à jour         : ${stats.expensesUpdated}`);
    console.log(`Remboursements enregistrés    : ${stats.expenseSettledTransfersUpdated}`);
    console.log(`Repas mis à jour              : ${stats.mealsUpdated}`);
    console.log(`Noms participants nettoyés    : ${stats.participantsNamesCleaned}`);
    console.log(`participantCount initialisé   : ${stats.participantCountSet}`);
    if (opts.dryRun) {
      const total = stats.carpoolsUpdated + stats.roomsUpdated
        + stats.expenseGroupsUpdated + stats.expensesUpdated
        + stats.expenseSettledTransfersUpdated + stats.mealsUpdated
        + stats.participantsNamesCleaned + stats.participantCountSet;
      console.log(`\nRelancez avec --apply pour écrire ces ${total} modification(s).`);
    }
  }

  await app.delete();
}

run().catch((err) => {
  console.error('Erreur fatale :', err);
  process.exit(1);
});
