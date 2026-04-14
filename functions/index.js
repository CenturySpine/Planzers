const admin = require('firebase-admin');
const {
  onDocumentCreated,
  onDocumentWritten,
  onDocumentUpdated,
} = require('firebase-functions/v2/firestore');
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

/** @param {FirebaseFirestore.DocumentData} data */
function memberIdsAsSet(data) {
  const raw = data.memberIds;
  if (!Array.isArray(raw)) return new Set();
  return new Set(raw.map((v) => String(v)));
}

/** Trip planner placeholders: ids in trip.memberIds until a guest claims one. */
function isPlaceholderMemberId(id) {
  const s = normalizeString(id);
  return s.startsWith('ph_') && s.length > 8;
}

/** Co-admin uids on the trip document (creator is always admin via ownerId). */
function tripAdminMemberIdSet(data) {
  const raw = data.adminMemberIds;
  if (!Array.isArray(raw)) return new Set();
  return new Set(raw.map((v) => String(v)));
}

function isTripAdminUser(data, uid) {
  const u = normalizeString(uid);
  if (!u) return false;
  if (normalizeString(data.ownerId) === u) return true;
  return tripAdminMemberIdSet(data).has(u);
}

/**
 * When a placeholder row becomes a real uid in memberIds, carry co-admin from
 * ph_* to uid in adminMemberIds. Returns null if the field needs no update.
 * @param {unknown} adminIdsRaw
 * @param {string} phId
 * @param {string} uid
 * @returns {string[] | null}
 */
function adminMemberIdsAfterPlaceholderClaim(adminIdsRaw, phId, uid) {
  const raw = Array.isArray(adminIdsRaw)
    ? adminIdsRaw.map((v) => String(v))
    : [];
  if (!raw.includes(phId)) return null;
  return [...new Set(raw.map((id) => (id === phId ? uid : id)))];
}

/**
 * Undo {@link adminMemberIdsAfterPlaceholderClaim} when claim migration fails.
 * @param {unknown} adminIdsRaw
 * @param {string} uid
 * @param {string} phId
 * @returns {string[] | null}
 */
function adminMemberIdsAfterRevertClaim(adminIdsRaw, uid, phId) {
  const raw = Array.isArray(adminIdsRaw)
    ? adminIdsRaw.map((v) => String(v))
    : [];
  if (!raw.includes(uid)) return null;
  return [...new Set(raw.map((id) => (id === uid ? phId : id)))];
}

function assertTripInviteToken(data, token) {
  const expectedToken = normalizeString(data.inviteToken);
  if (!expectedToken || expectedToken !== token) {
    throw new HttpsError(
      'permission-denied',
      'Lien d invitation invalide ou expire'
    );
  }
}

/**
 * Rewires [fromId] to [toId] in expense groups, expenses, and room bed data.
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} fromId
 * @param {string} toId
 */
async function migrateTripMemberIdReferences(tripRef, fromId, toId) {
  const db = admin.firestore();
  const [groupsSnap, expensesSnap, roomsSnap] = await Promise.all([
    tripRef.collection('expenseGroups').get(),
    tripRef.collection('expenses').get(),
    tripRef.collection('rooms').get(),
  ]);

  /** @type {{ ref: FirebaseFirestore.DocumentReference, data: Record<string, unknown> }[]} */
  const updates = [];

  for (const doc of groupsSnap.docs) {
    const vis = doc.data().visibleToMemberIds;
    if (!Array.isArray(vis) || !vis.map(String).includes(fromId)) continue;
    const next = [
      ...new Set(vis.map((id) => (String(id) === fromId ? toId : String(id)))),
    ];
    updates.push({ ref: doc.ref, data: { visibleToMemberIds: next } });
  }

  for (const doc of expensesSnap.docs) {
    const exp = doc.data() || {};
    const participants = (
      Array.isArray(exp.participantIds) ? exp.participantIds : []
    ).map(String);
    const paidBy = normalizeString(exp.paidBy);
    let dirty = false;
    let newParticipants = participants;
    if (participants.includes(fromId)) {
      newParticipants = [
        ...new Set(participants.map((id) => (id === fromId ? toId : id))),
      ];
      dirty = true;
    }
    let newPaidBy = paidBy;
    if (paidBy === fromId) {
      newPaidBy = toId;
      dirty = true;
    }

    /** @type {Record<string, unknown>} */
    const expUpdate = {};
    if (dirty) {
      expUpdate.participantIds = newParticipants;
      expUpdate.paidBy = newPaidBy;
    }

    const sharesRaw = exp.participantShares;
    if (
      sharesRaw &&
      typeof sharesRaw === 'object' &&
      !Array.isArray(sharesRaw) &&
      Object.prototype.hasOwnProperty.call(sharesRaw, fromId)
    ) {
      const nextShares = { ...sharesRaw };
      const v = nextShares[fromId];
      delete nextShares[fromId];
      nextShares[toId] = v;
      expUpdate.participantShares = nextShares;
      dirty = true;
    }

    if (dirty) {
      updates.push({ ref: doc.ref, data: expUpdate });
    }
  }

  for (const doc of roomsSnap.docs) {
    const data = doc.data() || {};
    const bedsRaw = Array.isArray(data.beds) ? data.beds : [];
    let roomDirty = false;
    const newBeds = bedsRaw.map((bed) => {
      if (!bed || typeof bed !== 'object') return bed;
      const ids = Array.isArray(bed.assignedMemberIds)
        ? bed.assignedMemberIds.map(String)
        : [];
      if (!ids.includes(fromId)) return bed;
      roomDirty = true;
      const rep = [...new Set(ids.map((id) => (id === fromId ? toId : id)))];
      return { ...bed, assignedMemberIds: rep };
    });
    /** @type {Record<string, unknown>} */
    const newData = {};
    if (roomDirty) {
      newData.beds = newBeds;
    }
    const legacy = Array.isArray(data.assignedMemberIds)
      ? data.assignedMemberIds.map(String)
      : [];
    if (legacy.includes(fromId)) {
      roomDirty = true;
      newData.assignedMemberIds = [
        ...new Set(legacy.map((id) => (id === fromId ? toId : id))),
      ];
    }
    if (roomDirty && Object.keys(newData).length > 0) {
      updates.push({ ref: doc.ref, data: newData });
    }
  }

  let batch = db.batch();
  let n = 0;
  for (const { ref, data } of updates) {
    batch.update(ref, data);
    n++;
    if (n >= 450) {
      await batch.commit();
      batch = db.batch();
      n = 0;
    }
  }
  if (n > 0) {
    await batch.commit();
  }
}

/**
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} uid
 * @param {string} phId
 */
async function revertTripMemberClaim(tripRef, uid, phId) {
  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(tripRef);
    if (!snap.exists) return;
    const data = snap.data() || {};
    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(uid)) return;
    const newMemberIds = memberIds.map((id) => (id === uid ? phId : id));
    const FieldValue = admin.firestore.FieldValue;
    /** @type {Record<string, unknown>} */
    const upd = {
      memberIds: newMemberIds,
      updatedAt: FieldValue.serverTimestamp(),
    };
    const nextAdmins = adminMemberIdsAfterRevertClaim(
      data.adminMemberIds,
      uid,
      phId
    );
    if (nextAdmins) {
      upd.adminMemberIds = nextAdmins;
    }
    tx.update(tripRef, upd);
  });
}

/**
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} phId
 */
async function assertPlaceholderUnusedInExpensesAndRooms(tripRef, phId) {
  const [expensesSnap, roomsSnap] = await Promise.all([
    tripRef.collection('expenses').get(),
    tripRef.collection('rooms').get(),
  ]);

  for (const doc of expensesSnap.docs) {
    const exp = doc.data() || {};
    const participants = (
      Array.isArray(exp.participantIds) ? exp.participantIds : []
    ).map(String);
    const paidBy = normalizeString(exp.paidBy);
    const shares = exp.participantShares;
    const inShares =
      shares &&
      typeof shares === 'object' &&
      !Array.isArray(shares) &&
      Object.prototype.hasOwnProperty.call(shares, phId);
    if (participants.includes(phId) || paidBy === phId || inShares) {
      throw new HttpsError(
        'failed-precondition',
        'Ce voyageur prévu est encore utilisé dans des dépenses. Retire-le des participants avant de le supprimer.'
      );
    }
  }

  for (const doc of roomsSnap.docs) {
    const data = doc.data() || {};
    const bedsRaw = Array.isArray(data.beds) ? data.beds : [];
    for (const bed of bedsRaw) {
      if (!bed || typeof bed !== 'object') continue;
      const ids = Array.isArray(bed.assignedMemberIds)
        ? bed.assignedMemberIds.map(String)
        : [];
      if (ids.includes(phId)) {
        throw new HttpsError(
          'failed-precondition',
          'Ce voyageur prévu est encore assigné à une chambre. Retire l\'assignation avant de le supprimer.'
        );
      }
    }
  }
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

const FCM_INVALID_TOKEN_CODES = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
]);

const TRIP_NOTIFICATION_CHANNELS = Object.freeze({
  MESSAGES: 'messages',
  ACTIVITIES: 'activities',
});
const CHANNEL_PRESENCE_MAX_AGE_MS = 120000;

function tripCounterRef(uid, tripId) {
  return admin
    .firestore()
    .collection('users')
    .doc(uid)
    .collection('tripNotificationCounters')
    .doc(tripId);
}

function tripPresenceRef(uid, tripId) {
  return admin
    .firestore()
    .collection('users')
    .doc(uid)
    .collection('tripNotificationPresence')
    .doc(tripId);
}

async function recipientsNotActivelyViewingChannel({
  tripId,
  recipients,
  channel,
}) {
  const nowMs = Date.now();
  const checks = recipients.map(async (uid) => {
    const cleanUid = normalizeString(uid);
    if (!cleanUid) return null;
    try {
      const snap = await tripPresenceRef(cleanUid, tripId).get();
      if (!snap.exists) return cleanUid;
      const data = snap.data() || {};
      const openChannel = normalizeString(data.openChannel);
      const updatedAt = data.updatedAt;
      const updatedAtMs =
        updatedAt instanceof admin.firestore.Timestamp
          ? updatedAt.toMillis()
          : 0;
      const isFresh = nowMs - updatedAtMs <= CHANNEL_PRESENCE_MAX_AGE_MS;
      if (isFresh && openChannel === channel) {
        return null;
      }
      return cleanUid;
    } catch (e) {
      console.warn('recipientsNotActivelyViewingChannel', cleanUid, e);
      return cleanUid;
    }
  });
  const result = await Promise.all(checks);
  return result.filter((uid) => !!uid);
}

async function incrementTripUnreadCounters({ tripId, recipients, channel }) {
  if (!Array.isArray(recipients) || recipients.length === 0) return;
  const FieldValue = admin.firestore.FieldValue;
  let batch = admin.firestore().batch();
  let n = 0;
  for (const uid of recipients) {
    const cleanUid = normalizeString(uid);
    if (!cleanUid) continue;
    batch.set(
      tripCounterRef(cleanUid, tripId),
      {
        channels: {
          [channel]: FieldValue.increment(1),
        },
        total: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    n++;
    if (n >= 400) {
      await batch.commit();
      batch = admin.firestore().batch();
      n = 0;
    }
  }
  if (n > 0) {
    await batch.commit();
  }
}

async function collectRecipientTokenEntries(db, recipients) {
  /** @type {{ token: string, ref: FirebaseFirestore.DocumentReference }[]} */
  const tokenEntries = [];
  await Promise.all(
    recipients.map(async (uid) => {
      try {
        const tokensSnap = await db
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .get();
        for (const doc of tokensSnap.docs) {
          const t = normalizeString((doc.data() || {}).token);
          if (t) {
            tokenEntries.push({ token: t, ref: doc.ref });
          }
        }
      } catch (e) {
        console.warn('collectRecipientTokenEntries', uid, e);
      }
    })
  );
  return tokenEntries;
}

async function cleanupInvalidFcmTokens(db, sendResult, tokenEntries) {
  let batch = db.batch();
  let batchOps = 0;
  for (let i = 0; i < sendResult.responses.length; i++) {
    const r = sendResult.responses[i];
    if (r.success) continue;
    const code = r.error?.code || '';
    if (!FCM_INVALID_TOKEN_CODES.has(code)) continue;
    const ref = tokenEntries[i]?.ref;
    if (!ref) continue;
    batch.delete(ref);
    batchOps++;
    if (batchOps >= 400) {
      await batch.commit();
      batch = db.batch();
      batchOps = 0;
    }
  }
  if (batchOps > 0) {
    await batch.commit();
  }
}

function channelsMap(data) {
  if (!data || typeof data !== 'object') return {};
  const channels = data.channels;
  if (!channels || typeof channels !== 'object' || Array.isArray(channels)) {
    return {};
  }
  return channels;
}

function channelReadTimestamp(data, channel) {
  const channels = channelsMap(data);
  const raw = channels[channel];
  if (raw instanceof admin.firestore.Timestamp) {
    return raw;
  }
  return null;
}

async function countUnreadForChannel({ tripId, uid, channel, readAfter }) {
  const channelCollection =
    channel === TRIP_NOTIFICATION_CHANNELS.MESSAGES ? 'messages' : 'activities';
  const actorField =
    channel === TRIP_NOTIFICATION_CHANNELS.MESSAGES ? 'authorId' : 'createdBy';
  const tripRef = admin.firestore().collection('trips').doc(tripId);

  const totalSnap = await tripRef
    .collection(channelCollection)
    .where('createdAt', '>', readAfter)
    .get();
  if (!uid) return totalSnap.size;

  let unread = 0;
  for (const doc of totalSnap.docs) {
    const data = doc.data() || {};
    const actorId = normalizeString(data[actorField]);
    if (!actorId || actorId !== uid) {
      unread++;
    }
  }
  return unread;
}

async function setTripChannelCounter({ tripId, uid, channel, value }) {
  const counterRef = tripCounterRef(uid, tripId);
  const snap = await counterRef.get();
  const prevData = snap.exists ? snap.data() || {} : {};
  const prevChannels = channelsMap(prevData);
  const nextChannels = { ...prevChannels, [channel]: value };
  const total = Object.values(nextChannels).reduce((sum, current) => {
    const n = typeof current === 'number' ? current : Number(current) || 0;
    return sum + n;
  }, 0);
  await counterRef.set(
    {
      channels: nextChannels,
      total,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

/**
 * Shared trip notification payload contract used by Flutter/Web binders.
 * @param {{
 *   channel: string,
 *   tripId: string,
 *   actorId: string,
 *   type: string,
 *   targetPath: string,
 *   createdAt?: FirebaseFirestore.Timestamp,
 *   payload?: Record<string, string>,
 * }} event
 */
function buildTripNotificationEventData(event) {
  const data = {
    tripId: normalizeString(event.tripId),
    type: normalizeString(event.type),
    channel: normalizeString(event.channel),
    targetPath: normalizeString(event.targetPath),
    actorId: normalizeString(event.actorId),
    createdAtMs: String(
      event.createdAt instanceof admin.firestore.Timestamp
        ? event.createdAt.toMillis()
        : Date.now()
    ),
  };
  if (event.payload && typeof event.payload === 'object') {
    for (const [k, v] of Object.entries(event.payload)) {
      const cleanK = normalizeString(k);
      const cleanV = normalizeString(v);
      if (!cleanK || !cleanV) continue;
      data[`payload_${cleanK}`] = cleanV;
    }
  }
  return data;
}

/**
 * Sends a push notification to other trip members when a message is created.
 * Tokens live under users/{uid}/fcmTokens (written by the Flutter app).
 */
exports.notifyTripMessageRecipients = onDocumentCreated(
  {
    document: 'trips/{tripId}/messages/{messageId}',
    region: 'europe-west1',
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const tripId = event.params.tripId;
    const msg = snap.data() || {};
    const authorId = normalizeString(msg.authorId);
    const text = normalizeString(msg.text).slice(0, 180);

    if (!authorId || !text) {
      return;
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) return;

    const trip = tripSnap.data() || {};
    const memberIds = Array.isArray(trip.memberIds)
      ? trip.memberIds.map((v) => String(v))
      : [];
    const candidateRecipients = memberIds.filter((id) => id && id !== authorId);
    const recipients = await recipientsNotActivelyViewingChannel({
      tripId,
      recipients: candidateRecipients,
      channel: TRIP_NOTIFICATION_CHANNELS.MESSAGES,
    });
    if (recipients.length === 0) return;

    const tripTitle = normalizeString(trip.title) || 'Voyage';
    const labels =
      trip.memberPublicLabels && typeof trip.memberPublicLabels === 'object'
        ? trip.memberPublicLabels
        : {};
    let resolvedAuthorLabel = normalizeString(labels[authorId]);
    if (!resolvedAuthorLabel) {
      try {
        const u = await admin.auth().getUser(authorId);
        resolvedAuthorLabel = emailLocalPart(u.email || '');
      } catch (e) {
        console.warn('notifyTripMessageRecipients getUser', authorId, e);
      }
    }
    if (!resolvedAuthorLabel) {
      resolvedAuthorLabel = 'Quelqu’un';
    }

    await incrementTripUnreadCounters({
      tripId,
      recipients,
      channel: TRIP_NOTIFICATION_CHANNELS.MESSAGES,
    });
    const tokenEntries = await collectRecipientTokenEntries(db, recipients);
    if (tokenEntries.length === 0) return;

    const messages = tokenEntries.map(({ token }) => ({
      token,
      notification: {
        title: `Messagerie · ${tripTitle}`,
        body: `${resolvedAuthorLabel} : ${text}`,
      },
      data: buildTripNotificationEventData({
        channel: TRIP_NOTIFICATION_CHANNELS.MESSAGES,
        tripId,
        actorId: authorId,
        type: 'trip_message',
        targetPath: `/trips/${tripId}/messages`,
        createdAt:
          msg.createdAt instanceof admin.firestore.Timestamp
            ? msg.createdAt
            : undefined,
      }),
    }));

    const result = await admin.messaging().sendEach(messages);
    await cleanupInvalidFcmTokens(db, result, tokenEntries);
  }
);

exports.notifyTripActivityRecipients = onDocumentCreated(
  {
    document: 'trips/{tripId}/activities/{activityId}',
    region: 'europe-west1',
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const tripId = event.params.tripId;
    const activity = snap.data() || {};
    const actorId = normalizeString(activity.createdBy);
    const label = normalizeString(activity.label).slice(0, 180);
    if (!actorId || !label) {
      return;
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) return;

    const trip = tripSnap.data() || {};
    const memberIds = Array.isArray(trip.memberIds)
      ? trip.memberIds.map((v) => String(v))
      : [];
    const candidateRecipients = memberIds.filter((id) => id && id !== actorId);
    const recipients = await recipientsNotActivelyViewingChannel({
      tripId,
      recipients: candidateRecipients,
      channel: TRIP_NOTIFICATION_CHANNELS.ACTIVITIES,
    });
    if (recipients.length === 0) return;

    const tripTitle = normalizeString(trip.title) || 'Voyage';
    const labels =
      trip.memberPublicLabels && typeof trip.memberPublicLabels === 'object'
        ? trip.memberPublicLabels
        : {};
    let actorLabel = normalizeString(labels[actorId]);
    if (!actorLabel) {
      try {
        const u = await admin.auth().getUser(actorId);
        actorLabel = emailLocalPart(u.email || '');
      } catch (e) {
        console.warn('notifyTripActivityRecipients getUser', actorId, e);
      }
    }
    if (!actorLabel) {
      actorLabel = 'Quelqu’un';
    }

    await incrementTripUnreadCounters({
      tripId,
      recipients,
      channel: TRIP_NOTIFICATION_CHANNELS.ACTIVITIES,
    });
    const tokenEntries = await collectRecipientTokenEntries(db, recipients);
    if (tokenEntries.length === 0) return;

    const messages = tokenEntries.map(({ token }) => ({
      token,
      notification: {
        title: `Activites · ${tripTitle}`,
        body: `${actorLabel} a propose : ${label}`,
      },
      data: buildTripNotificationEventData({
        channel: TRIP_NOTIFICATION_CHANNELS.ACTIVITIES,
        tripId,
        actorId,
        type: 'trip_activity',
        targetPath: `/trips/${tripId}/activities`,
        createdAt:
          activity.createdAt instanceof admin.firestore.Timestamp
            ? activity.createdAt
            : undefined,
      }),
    }));
    const result = await admin.messaging().sendEach(messages);
    await cleanupInvalidFcmTokens(db, result, tokenEntries);
  }
);

exports.syncTripUnreadCountersFromReadState = onDocumentWritten(
  {
    document: 'trips/{tripId}/notificationReads/{userId}',
    region: 'europe-west1',
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (event) => {
    const afterSnap = event.data.after;
    if (!afterSnap.exists) {
      return;
    }
    const beforeSnap = event.data.before;
    const tripId = event.params.tripId;
    const userId = event.params.userId;

    const watchedChannels = [
      TRIP_NOTIFICATION_CHANNELS.MESSAGES,
      TRIP_NOTIFICATION_CHANNELS.ACTIVITIES,
    ];
    for (const channel of watchedChannels) {
      const beforeTs = beforeSnap.exists
        ? channelReadTimestamp(beforeSnap.data() || {}, channel)
        : null;
      const afterTs = channelReadTimestamp(afterSnap.data() || {}, channel);
      const beforeMillis = beforeTs ? beforeTs.toMillis() : 0;
      const afterMillis = afterTs ? afterTs.toMillis() : 0;
      if (beforeMillis === afterMillis) {
        continue;
      }
      const readAfter =
        afterTs || admin.firestore.Timestamp.fromMillis(0);
      const unread = await countUnreadForChannel({
        tripId,
        uid: userId,
        channel,
        readAfter,
      });
      await setTripChannelCounter({
        tripId,
        uid: userId,
        channel,
        value: unread,
      });
    }
  }
);

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

    const removed = [...beforeIds].filter((id) => !afterIds.has(id));

    const tripRef = afterSnap.ref;
    for (const uid of added) {
      // Placeholder claimed by a real account: join callable migrates data;
      // do not union the new uid into every expense like a brand-new member.
      if (
        added.length === 1 &&
        removed.length === 1 &&
        isPlaceholderMemberId(removed[0]) &&
        !isPlaceholderMemberId(uid)
      ) {
        continue;
      }
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

exports.generateTripLinkPreview = onDocumentUpdated(
  {
    document: 'trips/{tripId}',
    region: 'europe-west1',
    timeoutSeconds: 30,
    memory: '256MiB',
  },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};

    const beforeUrl = normalizeString(before.linkUrl);
    const afterUrl = normalizeString(after.linkUrl);

    // Avoid loops: only run when linkUrl actually changes.
    if (beforeUrl === afterUrl) return;

    const tripRef = event.data.after.ref;

    if (!afterUrl) {
      await tripRef.set(
        {
          linkPreview: admin.firestore.FieldValue.delete(),
        },
        { merge: true }
      );
      return;
    }

    const parsed = safeUrl(afterUrl);
    if (!parsed) {
      await tripRef.set(
        {
          linkPreview: {
            status: 'error',
            url: afterUrl,
            error: 'invalid_url',
            fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
      return;
    }

    // Mark as loading (UI can show spinner).
    await tripRef.set(
      {
        linkPreview: {
          status: 'loading',
          url: parsed.toString(),
          fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );

    try {
      const html = await fetchHtml(parsed);
      const preview = parsePreviewFromHtml(parsed, html);

      const hasSomething =
        preview.title || preview.description || preview.imageUrl || preview.siteName;

      await tripRef.set(
        {
          linkPreview: {
            status: hasSomething ? 'ok' : 'empty',
            url: parsed.toString(),
            title: preview.title,
            description: preview.description,
            siteName: preview.siteName,
            imageUrl: preview.imageUrl,
            fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
    } catch (e) {
      await tripRef.set(
        {
          linkPreview: {
            status: 'error',
            url: parsed.toString(),
            error: String(e),
            fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
    }
  }
);

/**
 * Adds [uid] to trip members if [token] matches the trip inviteToken.
 * When the trip still has placeholder members, [placeholderMemberId] must name
 * the placeholder row to claim (replaced by [uid]).
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} uid
 * @param {string} token
 * @param {string} placeholderMemberId
 */
async function completeJoinTripWithInvite(
  tripRef,
  uid,
  token,
  placeholderMemberId
) {
  const FieldValue = admin.firestore.FieldValue;
  const placeholderArg = normalizeString(placeholderMemberId);
  let claimedPh = null;

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(tripRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const data = snap.data() || {};
    assertTripInviteToken(data, token);

    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (memberIds.includes(uid)) {
      return;
    }

    const phMembers = memberIds.filter(isPlaceholderMemberId);

    if (phMembers.length > 0) {
      if (!placeholderArg || !isPlaceholderMemberId(placeholderArg)) {
        throw new HttpsError(
          'invalid-argument',
          'Choisis un voyageur prévu sur la liste pour rejoindre ce voyage.'
        );
      }
      if (!memberIds.includes(placeholderArg)) {
        throw new HttpsError(
          'failed-precondition',
          'Ce voyageur a déjà été choisi ou est introuvable.'
        );
      }
      const newMemberIds = memberIds.map((id) =>
        id === placeholderArg ? uid : id
      );
      claimedPh = placeholderArg;
      /** @type {Record<string, unknown>} */
      const tripUpdate = {
        memberIds: newMemberIds,
        updatedAt: FieldValue.serverTimestamp(),
      };
      const nextAdmins = adminMemberIdsAfterPlaceholderClaim(
        data.adminMemberIds,
        placeholderArg,
        uid
      );
      if (nextAdmins) {
        tripUpdate.adminMemberIds = nextAdmins;
      }
      tx.update(tripRef, tripUpdate);
    } else {
      memberIds.push(uid);
      tx.update(tripRef, {
        memberIds,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });

  const tripSnap = await tripRef.get();
  const tripData = tripSnap.data() || {};
  const finalMemberIds = Array.isArray(tripData.memberIds)
    ? tripData.memberIds.map((v) => String(v))
    : [];
  if (!finalMemberIds.includes(uid)) {
    return;
  }

  if (claimedPh) {
    try {
      await migrateTripMemberIdReferences(tripRef, claimedPh, uid);
    } catch (e) {
      console.error('migrateTripMemberIdReferences failed', tripRef.id, e);
      try {
        await revertTripMemberClaim(tripRef, uid, claimedPh);
      } catch (revertErr) {
        console.error('revertTripMemberClaim failed', tripRef.id, revertErr);
      }
      throw new HttpsError(
        'internal',
        'Impossible de finaliser ton arrivée dans le voyage. Réessaie dans un instant.'
      );
    }
  }

  let emailLocal = '';
  try {
    const userRecord = await admin.auth().getUser(uid);
    emailLocal = emailLocalPart(userRecord.email || '');
  } catch (e) {
    console.warn('joinTripWithInvite getUser', e);
  }

  const labelUpdate = {};
  if (claimedPh) {
    labelUpdate[`memberPublicLabels.${claimedPh}`] = FieldValue.delete();
  }
  if (emailLocal) {
    labelUpdate[`memberPublicLabels.${uid}`] = emailLocal;
  }
  if (Object.keys(labelUpdate).length > 0) {
    await tripRef.update(labelUpdate);
  }
}

exports.getInviteJoinContext = onCall(
  {
    region: 'europe-west1',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripIdIn = normalizeString(request.data?.tripId);
    const token = normalizeString(request.data?.token);
    if (!token) {
      throw new HttpsError('invalid-argument', 'Invitation invalide');
    }

    const db = admin.firestore();

    let tripRef;
    if (tripIdIn) {
      tripRef = db.collection('trips').doc(tripIdIn);
    } else {
      const q = await db
        .collection('trips')
        .where('inviteToken', '==', token)
        .limit(2)
        .get();

      if (q.empty) {
        throw new HttpsError('not-found', 'Code d invitation inconnu');
      }
      if (q.size > 1) {
        console.error('getInviteJoinContext duplicate token', token);
        throw new HttpsError('internal', 'Erreur serveur');
      }
      tripRef = q.docs[0].ref;
    }

    const snap = await tripRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const data = snap.data() || {};
    assertTripInviteToken(data, token);

    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    const labels =
      data.memberPublicLabels && typeof data.memberPublicLabels === 'object'
        ? data.memberPublicLabels
        : {};

    const placeholders = memberIds
      .filter(isPlaceholderMemberId)
      .map((id) => ({
        id,
        displayName: normalizeString(labels[id]) || 'Voyageur',
      }));

    return {
      tripId: tripRef.id,
      tripTitle: normalizeString(data.title) || 'Voyage',
      placeholders,
      requiresPlaceholderChoice: placeholders.length > 0,
    };
  }
);

exports.removeTripPlaceholderMember = onCall(
  {
    region: 'europe-west1',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const placeholderId = normalizeString(request.data?.placeholderId);
    if (!tripId || !placeholderId || !isPlaceholderMemberId(placeholderId)) {
      throw new HttpsError('invalid-argument', 'Parametres invalides');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const data = tripSnap.data() || {};
    if (normalizeString(data.ownerId) !== uid) {
      throw new HttpsError(
        'permission-denied',
        'Seul le créateur du voyage peut retirer un voyageur prévu.'
      );
    }

    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(placeholderId)) {
      throw new HttpsError('not-found', 'Voyageur prévu introuvable');
    }

    await assertPlaceholderUnusedInExpensesAndRooms(tripRef, placeholderId);

    const FieldValue = admin.firestore.FieldValue;
    const groupsSnap = await tripRef.collection('expenseGroups').get();

    let batch = db.batch();
    let n = 0;
    for (const doc of groupsSnap.docs) {
      const vis = doc.data().visibleToMemberIds;
      if (!Array.isArray(vis) || !vis.map(String).includes(placeholderId)) {
        continue;
      }
      batch.update(doc.ref, {
        visibleToMemberIds: FieldValue.arrayRemove(placeholderId),
      });
      n++;
      if (n >= 450) {
        await batch.commit();
        batch = db.batch();
        n = 0;
      }
    }

    batch.update(tripRef, {
      memberIds: FieldValue.arrayRemove(placeholderId),
      [`memberPublicLabels.${placeholderId}`]: FieldValue.delete(),
      adminMemberIds: FieldValue.arrayRemove(placeholderId),
    });
    n++;
    if (n > 0) {
      await batch.commit();
    }

    return { ok: true };
  }
);

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

    const placeholderMemberId = normalizeString(
      request.data?.placeholderMemberId
    );

    const tripRef = admin.firestore().collection('trips').doc(tripId);
    await completeJoinTripWithInvite(
      tripRef,
      uid,
      token,
      placeholderMemberId
    );

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

    const placeholderMemberId = normalizeString(
      request.data?.placeholderMemberId
    );

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
    await completeJoinTripWithInvite(
      tripRef,
      uid,
      token,
      placeholderMemberId
    );

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
        adminMemberIds: admin.firestore.FieldValue.arrayRemove(uid),
      });
    });

    return { ok: true };
  }
);

exports.cycleTripMemberAdminRole = onCall(
  {
    region: 'europe-west1',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const memberId = normalizeString(request.data?.memberId);
    if (!tripId || !memberId) {
      throw new HttpsError('invalid-argument', 'Parametres invalides');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const data = tripSnap.data() || {};
    if (!isTripAdminUser(data, uid)) {
      throw new HttpsError(
        'permission-denied',
        'Seuls les administrateurs peuvent modifier ce rôle'
      );
    }

    const ownerId = normalizeString(data.ownerId);
    if (memberId === ownerId) {
      throw new HttpsError(
        'invalid-argument',
        'Le créateur du voyage reste administrateur'
      );
    }

    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(memberId)) {
      throw new HttpsError('not-found', 'Participant introuvable');
    }

    const admins = tripAdminMemberIdSet(data);
    const FieldValue = admin.firestore.FieldValue;
    if (admins.has(memberId)) {
      await tripRef.update({
        adminMemberIds: FieldValue.arrayRemove(memberId),
      });
    } else {
      await tripRef.update({
        adminMemberIds: FieldValue.arrayUnion(memberId),
      });
    }

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

