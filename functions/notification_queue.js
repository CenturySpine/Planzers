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
    if (code === 'already-exists' || code === 'ALREADY_EXISTS' || e?.code === 6) {
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

module.exports = {
  buildNotificationQueueDocId,
  enqueueTripNotification,
  claimAndDeleteNotificationQueueDoc,
};
