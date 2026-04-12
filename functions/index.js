const admin = require('firebase-admin');
const { onDocumentUpdated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const cheerio = require('cheerio');

admin.initializeApp();

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function safeUrl(v) {
  const s = normalizeString(v);
  if (!s) return null;
  try {
    const u = new URL(s);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
    return u;
  } catch {
    return null;
  }
}

function pickFirst(...values) {
  for (const v of values) {
    const s = normalizeString(v);
    if (s) return s;
  }
  return '';
}

/** Text before @ for public trip member chips (empty if unusable). */
function emailLocalPart(email) {
  const e = normalizeString(email);
  if (!e) return '';
  const at = e.indexOf('@');
  return at > 0 ? e.slice(0, at).trim() : e;
}

async function fetchHtml(url) {
  const res = await fetch(url.toString(), {
    redirect: 'follow',
    headers: {
      'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      accept:
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    },
  });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  return await res.text();
}

function parsePreviewFromHtml(pageUrl, html) {
  const $ = cheerio.load(html);

  const meta = (key) =>
    pickFirst(
      $(`meta[property="${key}"]`).attr('content'),
      $(`meta[name="${key}"]`).attr('content')
    );

  const ogTitle = meta('og:title');
  const ogDescription = meta('og:description');
  const ogImage = meta('og:image');
  const ogSiteName = meta('og:site_name');

  const twitterTitle = meta('twitter:title');
  const twitterDescription = meta('twitter:description');
  const twitterImage = meta('twitter:image');

  const titleTag = normalizeString($('title').first().text());

  const title = pickFirst(ogTitle, twitterTitle, titleTag);
  const description = pickFirst(ogDescription, twitterDescription);
  const siteName = pickFirst(ogSiteName, pageUrl.hostname);
  const imageRaw = pickFirst(ogImage, twitterImage);

  let imageUrl = '';
  if (imageRaw) {
    try {
      imageUrl = new URL(imageRaw, pageUrl).toString();
    } catch {
      imageUrl = '';
    }
  }

  return {
    title,
    description,
    siteName,
    imageUrl,
  };
}

/**
 * Writes `linkPreview` on [docRef] from [afterUrlRaw], or clears it when empty.
 * Used for trip documents and activity subdocuments (same field names).
 * @param {FirebaseFirestore.DocumentReference} docRef
 * @param {string} afterUrlRaw
 */
async function applyLinkPreview(docRef, afterUrlRaw) {
  const FieldValue = admin.firestore.FieldValue;
  const afterUrl = normalizeString(afterUrlRaw);
  if (!afterUrl) {
    await docRef.set(
      {
        linkPreview: FieldValue.delete(),
      },
      { merge: true }
    );
    return;
  }

  const parsed = safeUrl(afterUrl);
  if (!parsed) {
    await docRef.set(
      {
        linkPreview: {
          status: 'error',
          url: afterUrl,
          error: 'invalid_url',
          fetchedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );
    return;
  }

  await docRef.set(
    {
      linkPreview: {
        status: 'loading',
        url: parsed.toString(),
        fetchedAt: FieldValue.serverTimestamp(),
      },
    },
    { merge: true }
  );

  try {
    const html = await fetchHtml(parsed);
    const preview = parsePreviewFromHtml(parsed, html);

    const hasSomething =
      preview.title ||
      preview.description ||
      preview.imageUrl ||
      preview.siteName;

    await docRef.set(
      {
        linkPreview: {
          status: hasSomething ? 'ok' : 'empty',
          url: parsed.toString(),
          title: preview.title,
          description: preview.description,
          siteName: preview.siteName,
          imageUrl: preview.imageUrl,
          fetchedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );
  } catch (e) {
    await docRef.set(
      {
        linkPreview: {
          status: 'error',
          url: parsed.toString(),
          error: String(e),
          fetchedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );
  }
}

/** @param {FirebaseFirestore.DocumentData} data */
function memberIdsAsSet(data) {
  const raw = data.memberIds;
  if (!Array.isArray(raw)) return new Set();
  return new Set(raw.map((v) => String(v)));
}

/**
 * When someone is added to trip.memberIds, add them to every expense post
 * (visibleToMemberIds) and every expense (participantIds). arrayUnion is
 * idempotent. Batched in chunks of 500 writes.
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} uid
 */
async function backfillTripMemberInExpenseSubcollections(tripRef, uid) {
  const FieldValue = admin.firestore.FieldValue;
  const db = admin.firestore();

  const [groupsSnap, expensesSnap] = await Promise.all([
    tripRef.collection('expenseGroups').get(),
    tripRef.collection('expenses').get(),
  ]);

  const updates = [];
  for (const doc of groupsSnap.docs) {
    updates.push({
      ref: doc.ref,
      data: { visibleToMemberIds: FieldValue.arrayUnion(uid) },
    });
  }
  for (const doc of expensesSnap.docs) {
    updates.push({
      ref: doc.ref,
      data: { participantIds: FieldValue.arrayUnion(uid) },
    });
  }

  let batch = db.batch();
  let n = 0;
  for (const { ref, data } of updates) {
    batch.update(ref, data);
    n++;
    if (n >= 500) {
      await batch.commit();
      batch = db.batch();
      n = 0;
    }
  }
  if (n > 0) {
    await batch.commit();
  }
}

/** Fires when trip.memberIds gains users (e.g. invite join). */
exports.backfillNewTripMemberInExpenses = onDocumentUpdated(
  {
    document: 'trips/{tripId}',
    region: 'europe-west1',
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (event) => {
    const beforeSnap = event.data.before;
    const afterSnap = event.data.after;
    if (!afterSnap.exists) return;

    const beforeIds = beforeSnap.exists
      ? memberIdsAsSet(beforeSnap.data() || {})
      : new Set();
    const afterIds = memberIdsAsSet(afterSnap.data() || {});

    const added = [...afterIds].filter((id) => !beforeIds.has(id));
    if (added.length === 0) return;

    const tripRef = afterSnap.ref;
    for (const uid of added) {
      try {
        await backfillTripMemberInExpenseSubcollections(tripRef, uid);
      } catch (e) {
        console.error(
          'backfillNewTripMemberInExpenses failed',
          tripRef.id,
          uid,
          e
        );
        throw e;
      }
    }
  }
);

exports.generateTripLinkPreview = onDocumentWritten(
  {
    document: 'trips/{tripId}',
    region: 'europe-west1',
    timeoutSeconds: 30,
    memory: '256MiB',
  },
  async (event) => {
    if (!event.data.after.exists) return;
    const before = event.data.before.exists
      ? event.data.before.data() || {}
      : {};
    const after = event.data.after.data() || {};

    const beforeUrl = normalizeString(before.linkUrl);
    const afterUrl = normalizeString(after.linkUrl);
    if (beforeUrl === afterUrl) return;

    await applyLinkPreview(event.data.after.ref, afterUrl);
  }
);

exports.generateActivityLinkPreview = onDocumentWritten(
  {
    document: 'trips/{tripId}/activities/{activityId}',
    region: 'europe-west1',
    timeoutSeconds: 30,
    memory: '256MiB',
  },
  async (event) => {
    if (!event.data.after.exists) return;
    const before = event.data.before.exists
      ? event.data.before.data() || {}
      : {};
    const after = event.data.after.data() || {};

    const beforeUrl = normalizeString(before.linkUrl);
    const afterUrl = normalizeString(after.linkUrl);
    if (beforeUrl === afterUrl) return;

    await applyLinkPreview(event.data.after.ref, afterUrl);
  }
);

/**
 * Adds [uid] to trip members if [token] matches the trip inviteToken.
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} uid
 * @param {string} token
 */
async function completeJoinTripWithInvite(tripRef, uid, token) {
  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(tripRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const data = snap.data() || {};
    const expectedToken = normalizeString(data.inviteToken);
    if (!expectedToken || expectedToken !== token) {
      throw new HttpsError(
        'permission-denied',
        'Lien d invitation invalide ou expire'
      );
    }

    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (memberIds.includes(uid)) {
      return;
    }

    memberIds.push(uid);
    tx.update(tripRef, {
      memberIds,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  let emailLocal = '';
  try {
    const userRecord = await admin.auth().getUser(uid);
    emailLocal = emailLocalPart(userRecord.email || '');
  } catch (e) {
    console.warn('joinTripWithInvite getUser', e);
  }
  if (emailLocal) {
    await tripRef.update({
      [`memberPublicLabels.${uid}`]: emailLocal,
    });
  }
}

exports.joinTripWithInvite = onCall(
  {
    region: 'europe-west1',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const token = normalizeString(request.data?.token);
    if (!tripId || !token) {
      throw new HttpsError('invalid-argument', 'Lien d invitation invalide');
    }

    const tripRef = admin.firestore().collection('trips').doc(tripId);
    await completeJoinTripWithInvite(tripRef, uid, token);

    return { ok: true };
  }
);

/** Same as joinTripWithInvite, but resolves the trip from invite token only. */
exports.joinTripWithInviteToken = onCall(
  {
    region: 'europe-west1',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const token = normalizeString(request.data?.token);
    if (!token) {
      throw new HttpsError('invalid-argument', 'Code d invitation invalide');
    }

    const db = admin.firestore();
    const snap = await db
      .collection('trips')
      .where('inviteToken', '==', token)
      .limit(2)
      .get();

    if (snap.empty) {
      throw new HttpsError('not-found', 'Code d invitation inconnu');
    }
    if (snap.size > 1) {
      console.error('joinTripWithInviteToken duplicate token', token);
      throw new HttpsError('internal', 'Erreur serveur');
    }

    const tripRef = snap.docs[0].ref;
    await completeJoinTripWithInvite(tripRef, uid, token);

    return { ok: true, tripId: tripRef.id };
  }
);

/**
 * Removes [uid] from shared expenses for a trip: drops them from participantIds,
 * reassigns paidBy when needed, deletes docs with no participants left.
 *
 * @param {FirebaseFirestore.Transaction} tx
 * @param {FirebaseFirestore.QueryDocumentSnapshot[]} expenseDocs
 * @param {string} uid
 */
function applyLeaveTripExpenseStripping(tx, expenseDocs, uid) {
  for (const doc of expenseDocs) {
    const exp = doc.data() || {};
    const participants = (Array.isArray(exp.participantIds)
      ? exp.participantIds
      : []
    )
      .map((v) => String(v).trim())
      .filter((id) => id.length > 0);
    const paidBy = normalizeString(exp.paidBy);
    const inParticipants = participants.includes(uid);
    const isPayer = paidBy === uid;
    if (!inParticipants && !isPayer) {
      continue;
    }

    const newParticipants = participants.filter((id) => id !== uid);
    if (newParticipants.length === 0) {
      tx.delete(doc.ref);
      continue;
    }

    let newPaidBy = paidBy;
    if (isPayer || !newParticipants.includes(paidBy)) {
      newPaidBy = newParticipants[0];
    }

    tx.update(doc.ref, {
      participantIds: newParticipants,
      paidBy: newPaidBy,
    });
  }
}

exports.leaveTrip = onCall(
  {
    region: 'europe-west1',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    if (!tripId) {
      throw new HttpsError('invalid-argument', 'Voyage invalide');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);

    await db.runTransaction(async (tx) => {
      const tripSnap = await tx.get(tripRef);
      if (!tripSnap.exists) {
        throw new HttpsError('not-found', 'Voyage introuvable');
      }

      const data = tripSnap.data() || {};
      const ownerId = normalizeString(data.ownerId);
      if (ownerId === uid) {
        throw new HttpsError(
          'permission-denied',
          'Le créateur du voyage ne peut pas quitter ainsi'
        );
      }

      const memberIds = Array.isArray(data.memberIds)
        ? data.memberIds.map((v) => String(v))
        : [];
      if (!memberIds.includes(uid)) {
        throw new HttpsError(
          'permission-denied',
          'Tu ne fais pas partie de ce voyage'
        );
      }

      const expensesQuery = tripRef.collection('expenses');
      const expensesSnap = await tx.get(expensesQuery);
      applyLeaveTripExpenseStripping(tx, expensesSnap.docs, uid);

      tx.update(tripRef, {
        memberIds: admin.firestore.FieldValue.arrayRemove(uid),
        [`memberPublicLabels.${uid}`]: admin.firestore.FieldValue.delete(),
      });
    });

    return { ok: true };
  }
);

exports.registerMyTripMemberLabel = onCall(
  {
    region: 'europe-west1',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    if (!tripId) {
      throw new HttpsError('invalid-argument', 'Voyage invalide');
    }

    const tripRef = admin.firestore().collection('trips').doc(tripId);
    const snap = await tripRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const data = snap.data() || {};
    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(uid)) {
      throw new HttpsError(
        'permission-denied',
        'Tu ne fais pas partie de ce voyage'
      );
    }

    let emailLocal = '';
    try {
      const userRecord = await admin.auth().getUser(uid);
      emailLocal = emailLocalPart(userRecord.email || '');
    } catch (e) {
      console.warn('registerMyTripMemberLabel getUser', e);
    }
    if (!emailLocal) {
      return { ok: false, reason: 'no-email' };
    }

    await tripRef.update({
      [`memberPublicLabels.${uid}`]: emailLocal,
    });
    return { ok: true };
  }
);

