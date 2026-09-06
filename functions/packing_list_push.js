// "À emporter" — pushing a trip organiser's personal packing list to every
// other traveler slot of the trip.
//
// A traveler can only write their own packing list (Firestore rules), so the
// fan-out write has to happen here with the Admin SDK. The organiser's own
// list is the source of truth; each push reconciles the "organiser" section
// of every traveler's list item by item (add / rename / remove) while never
// touching the items travelers added themselves, and never re-enabling the
// module for a traveler who explicitly hid it.

const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

const ADMIN_SCOPE = 'admin';
const BATCH_LIMIT = 400;

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function isTripOrganiser(tripData, uid) {
  const u = normalizeString(uid);
  if (!u) return false;
  if (normalizeString(tripData.ownerId) === u) return true;
  const admins = Array.isArray(tripData.adminMemberIds)
    ? tripData.adminMemberIds.map((v) => String(v))
    : [];
  return admins.includes(u);
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
    isTripOrganiser(tripData, uid) || (await userIsApplicationOwner(db, uid));
  if (!allowed) {
    throw new HttpsError(
      'permission-denied',
      'Seuls les organisateurs peuvent pousser une liste.'
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

  // Source = the caller's current list (personal + any items already pushed
  // to them by another organiser).
  const sourceSnap = await tripRef
    .collection('packingLists')
    .doc(mySlotId)
    .collection('items')
    .get();
  const sourceItems = sourceSnap.docs
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
