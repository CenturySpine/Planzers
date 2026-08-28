'use strict';

const { FieldValue } = require('firebase-admin/firestore');

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

/**
 * Builds a deterministic notificationQueue document ID for idempotent enqueue.
 * @param {string} type
 * @param {Record<string, string>} parts
 * @returns {string}
 */
function buildNotificationQueueDocId(type, parts) {
  const cleanType = normalizeString(type);
  if (!cleanType) {
    throw new Error('buildNotificationQueueDocId: type is required');
  }

  const tripId = normalizeString(parts?.tripId);

  switch (cleanType) {
    case 'trip_message': {
      const messageId = normalizeString(parts?.messageId);
      if (!tripId || !messageId) {
        throw new Error('trip_message requires tripId and messageId');
      }
      return `trip_message__${tripId}__${messageId}`;
    }
    case 'trip_activity': {
      const activityId = normalizeString(parts?.activityId);
      if (!tripId || !activityId) {
        throw new Error('trip_activity requires tripId and activityId');
      }
      return `trip_activity__${tripId}__${activityId}`;
    }
    case 'trip_announcement': {
      const announcementId = normalizeString(parts?.announcementId);
      if (!tripId || !announcementId) {
        throw new Error('trip_announcement requires tripId and announcementId');
      }
      return `trip_announcement__${tripId}__${announcementId}`;
    }
    case 'cupidon_match': {
      const matchId = normalizeString(parts?.matchId);
      const notifiedUid = normalizeString(parts?.notifiedUid);
      if (!tripId || !matchId || !notifiedUid) {
        throw new Error('cupidon_match requires tripId, matchId and notifiedUid');
      }
      return `cupidon_match__${tripId}__${matchId}__${notifiedUid}`;
    }
    case 'expense_reimbursement_paid':
    case 'expense_reimbursement_unpaid': {
      const expenseId = normalizeString(parts?.expenseId);
      if (!tripId || !expenseId) {
        throw new Error(`${cleanType} requires tripId and expenseId`);
      }
      return `${cleanType}__${tripId}__${expenseId}`;
    }
    default:
      throw new Error(`buildNotificationQueueDocId: unsupported type ${cleanType}`);
  }
}

/**
 * Enqueues a notification with a deterministic doc ID (.create = idempotent).
 * @param {FirebaseFirestore.Firestore} db
 * @param {{ docId: string, payload: Record<string, unknown> }} options
 * @returns {Promise<{ enqueued: boolean }>}
 */
async function enqueueTripNotification(db, { docId, payload }) {
  const cleanDocId = normalizeString(docId);
  if (!cleanDocId) {
    throw new Error('enqueueTripNotification: docId is required');
  }

  const ref = db.collection('notificationQueue').doc(cleanDocId);
  try {
    await ref.create({
      ...payload,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { enqueued: true };
  } catch (e) {
    const code = normalizeString(e?.code);
    if (code === 'already-exists' || code === 'ALREADY_EXISTS' || code === '6' || e?.code === 6) {
      return { enqueued: false };
    }
    throw e;
  }
}

/**
 * Atomically claims a queue document by deleting it and returning its data.
 * @param {FirebaseFirestore.Firestore} db
 * @param {FirebaseFirestore.DocumentReference} ref
 * @returns {Promise<Record<string, unknown> | null>}
 */
async function claimAndDeleteNotificationQueueDoc(db, ref) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      return null;
    }
    tx.delete(ref);
    return snap.data() || {};
  });
}

/**
 * Sends a claimed notification batch and increments unread counters only after
 * FCM accepts the delivery request.
 * @param {{
 *   db: FirebaseFirestore.Firestore,
 *   tokenEntries: unknown[],
 *   messages: unknown[],
 *   tripId: string,
 *   recipients: string[],
 *   channel: string,
 *   sendEach: (messages: unknown[]) => Promise<unknown>,
 *   incrementTripUnreadCounters: (args: { tripId: string, recipients: string[], channel: string }) => Promise<void>,
 *   cleanupInvalidFcmTokens: (db: FirebaseFirestore.Firestore, result: unknown, tokenEntries: unknown[]) => Promise<void>,
 * }} options
 * @returns {Promise<void>}
 */
async function deliverNotificationBatch(options) {
  const tokenEntries = Array.isArray(options.tokenEntries)
    ? options.tokenEntries
    : [];
  const messages = Array.isArray(options.messages) ? options.messages : [];
  let sendResult = null;

  if (tokenEntries.length > 0) {
    sendResult = await options.sendEach(messages);
  }

  if (options.recipients.length > 0 && options.tripId) {
    await options.incrementTripUnreadCounters({
      tripId: options.tripId,
      recipients: options.recipients,
      channel: options.channel,
    });
  }

  if (sendResult) {
    await options.cleanupInvalidFcmTokens(
      options.db,
      sendResult,
      tokenEntries,
    );
  }
}

module.exports = {
  buildNotificationQueueDocId,
  enqueueTripNotification,
  claimAndDeleteNotificationQueueDoc,
  deliverNotificationBatch,
};
