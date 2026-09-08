// "À emporter" — pushing the trip owner's "group" packing items to every
// other traveler slot of the trip.
//
// A traveler can only write their own packing list (Firestore rules), so the
// fan-out write has to happen here with the Admin SDK. The owner's own list
// is the source of truth, restricted to the personal items they flagged as
// "group" (`shared: true`); their other items stay private. Each push
// reconciles the "organiser" section of every traveler's list item by item
// (add / rename / remove) while never touching the items travelers added
// themselves, and never re-enabling the module for a traveler who explicitly
// hid it.

const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

const ADMIN_SCOPE = 'admin';
const BATCH_LIMIT = 400;

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function isTripOwner(tripData, uid) {
  const u = normalizeString(uid);
  return u.length > 0 && normalizeString(tripData.ownerId) === u;
}

async function userIsApplicationOwner(db, uid) {
  const snap = await db.collection('users').doc(uid).get();
  return snap.exists && snap.data() && snap.data().isApplicationOwner === true;
}

exports.pushPackingList = onCall({}, async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }

  const tripId = normalizeString(request.data && request.data.tripId);
  if (!tripId) {
    throw new HttpsError('invalid-argument', 'Voyage invalide');
  }

  const db = admin.firestore();
  const tripRef = db.collection('trips').doc(tripId);
  const tripSnap = await tripRef.get();
  if (!tripSnap.exists) {
    throw new HttpsError('not-found', 'Voyage introuvable');
  }
  const tripData = tripSnap.data() || {};

  const allowed =
    isTripOwner(tripData, uid) || (await userIsApplicationOwner(db, uid));
  if (!allowed) {
    throw new HttpsError(
      'permission-denied',
      'Seul le créateur du voyage peut pousser une liste.'
    );
  }

  // The caller's own participant slot.
  const mySlotSnap = await tripRef
    .collection('participants')
    .where('userId', '==', uid)
    .limit(1)
    .get();
  if (mySlotSnap.empty) {
    throw new HttpsError(
      'failed-precondition',
      "Tu n'es pas encore inscrit comme voyageur sur ce voyage."
    );
  }
  const mySlotId = mySlotSnap.docs[0].id;

  // Source = the caller's own items flagged as "group". Items the caller
  // received from a push (organiser scope) are never re-pushed.
  const sourceSnap = await tripRef
    .collection('packingLists')
    .doc(mySlotId)
    .collection('items')
    .get();
  const sourceItems = sourceSnap.docs
    .filter((doc) => {
      const data = doc.data() || {};
      return data.shared === true && data.scope !== ADMIN_SCOPE;
    })
    .map((doc) => ({ id: doc.id, label: normalizeString(doc.data().label) }))
    .filter((it) => it.label.length > 0);
  const sourceIds = new Set(sourceItems.map((it) => it.id));

  // Targets = every other non-child participant slot.
  const participantsSnap = await tripRef.collection('participants').get();
  const targets = participantsSnap.docs.filter(
    (doc) => doc.id !== mySlotId && doc.data().isChild !== true
  );

  let batch = db.batch();
  let ops = 0;
  const flush = async () => {
    if (ops > 0) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };
  const queue = async (fn) => {
    fn();
    ops += 1;
    if (ops >= BATCH_LIMIT) {
      await flush();
    }
  };

  let participantCount = 0;
  for (const target of targets) {
    const listRef = tripRef.collection('packingLists').doc(target.id);
    const itemsRef = listRef.collection('items');

    const existingAdminSnap = await itemsRef
      .where('scope', '==', ADMIN_SCOPE)
      .get();
    const existingById = new Map(
      existingAdminSnap.docs.map((doc) => [doc.id, doc.data() || {}])
    );

    // Drop organiser items no longer in the source list.
    for (const doc of existingAdminSnap.docs) {
      if (!sourceIds.has(doc.id)) {
        await queue(() => batch.delete(doc.ref));
      }
    }

    // Upsert every source item, keeping the traveler's check state.
    for (const item of sourceItems) {
      const prev = existingById.get(item.id);
      await queue(() =>
        batch.set(itemsRef.doc(item.id), {
          label: item.label,
          scope: ADMIN_SCOPE,
          checked: !!(prev && prev.checked === true),
          createdAt: (prev && prev.createdAt) || FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        })
      );
    }

    // Turn the module on unless the traveler explicitly switched it off.
    const listSnap = await listRef.get();
    const currentEnabled = listSnap.exists
      ? listSnap.data().enabled
      : undefined;
    const listPayload = { updatedAt: FieldValue.serverTimestamp() };
    if (currentEnabled !== true && currentEnabled !== false) {
      listPayload.enabled = true;
    }
    await queue(() => batch.set(listRef, listPayload, { merge: true }));

    participantCount += 1;
  }

  await flush();

  return {
    ok: true,
    participantCount,
    itemCount: sourceItems.length,
  };
});
