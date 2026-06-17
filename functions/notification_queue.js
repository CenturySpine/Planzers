'use strict';

const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const NOTIFICATION_QUEUE_COLLECTION = 'notificationQueue';
const NOTIFICATION_QUEUE_PROCESSED_COLLECTION = 'notificationQueueProcessed';
const DEFAULT_PROCESSING_LEASE_SECONDS = 120;

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function timestampMillis(value) {
  if (value && typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  return 0;
}

function notificationQueueRef(db, docId) {
  return db.collection(NOTIFICATION_QUEUE_COLLECTION).doc(docId);
}

function processedNotificationRef(db, docId) {
  return db.collection(NOTIFICATION_QUEUE_PROCESSED_COLLECTION).doc(docId);
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
 * Enqueues a notification with a deterministic doc ID and durable completion
 * marker, so producer retries cannot recreate already-dispatched work.
 * @param {FirebaseFirestore.Firestore} db
 * @param {{ docId: string, payload: Record<string, unknown> }} options
 * @returns {Promise<{ enqueued: boolean }>}
 */
async function enqueueTripNotification(db, { docId, payload }) {
  const cleanDocId = normalizeString(docId);
  if (!cleanDocId) {
    throw new Error('enqueueTripNotification: docId is required');
  }

  const ref = notificationQueueRef(db, cleanDocId);
  const processedRef = processedNotificationRef(db, cleanDocId);
  let enqueued = false;

  await db.runTransaction(async (tx) => {
    const processedSnap = await tx.get(processedRef);
    if (processedSnap.exists) {
      return;
    }

    const queueSnap = await tx.get(ref);
    if (queueSnap.exists) {
      return;
    }

    tx.create(ref, {
      ...payload,
      status: 'pending',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    enqueued = true;
  });

  return { enqueued };
}

/**
 * Atomically claims a queue document by marking it as processing while leaving
 * the payload available for Cloud Functions retries.
 * @param {FirebaseFirestore.Firestore} db
 * @param {FirebaseFirestore.DocumentReference} ref
 * @param {{ leaseSeconds?: number }} [options]
 * @returns {Promise<{ claimed: true, data: Record<string, unknown> } | { claimed: false, retry: boolean, reason: string }>}
 */
async function claimNotificationQueueDoc(db, ref, options = {}) {
  const leaseSeconds = Number.isFinite(options.leaseSeconds)
    ? Math.max(1, options.leaseSeconds)
    : DEFAULT_PROCESSING_LEASE_SECONDS;
  const now = Timestamp.now();
  const leaseExpiresAt = Timestamp.fromMillis(now.toMillis() + leaseSeconds * 1000);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      return { claimed: false, retry: false, reason: 'absent' };
    }

    const data = snap.data() || {};
    const status = normalizeString(data.status) || 'pending';
    if (status === 'done') {
      return { claimed: false, retry: false, reason: 'done' };
    }
    if (
      status === 'processing' &&
      timestampMillis(data.processingLeaseExpiresAt) > now.toMillis()
    ) {
      return { claimed: false, retry: true, reason: 'processing' };
    }

    tx.update(ref, {
      status: 'processing',
      processingStartedAt: FieldValue.serverTimestamp(),
      processingLeaseExpiresAt: leaseExpiresAt,
      processingAttemptCount: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { claimed: true, data };
  });
}

/**
 * Releases a claimed queue document after a failed delivery attempt.
 * @param {FirebaseFirestore.Firestore} db
 * @param {FirebaseFirestore.DocumentReference} ref
 * @param {unknown} error
 * @returns {Promise<boolean>}
 */
async function releaseNotificationQueueDoc(db, ref, error) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      return false;
    }

    tx.update(ref, {
      status: 'pending',
      processingLeaseExpiresAt: FieldValue.delete(),
      lastError: normalizeString(error?.message) || String(error || 'unknown error'),
      lastErrorAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

/**
 * Marks a notification queue item as processed and removes it from the queue.
 * @param {FirebaseFirestore.Firestore} db
 * @param {FirebaseFirestore.DocumentReference} ref
 * @param {{ docId: string, channel?: string, type?: string, tripId?: string }} options
 * @returns {Promise<boolean>}
 */
async function completeNotificationQueueDoc(db, ref, options) {
  const cleanDocId = normalizeString(options?.docId) || normalizeString(ref?.id);
  if (!cleanDocId) {
    throw new Error('completeNotificationQueueDoc: docId is required');
  }

  const processedRef = processedNotificationRef(db, cleanDocId);
  return db.runTransaction(async (tx) => {
    const processedSnap = await tx.get(processedRef);
    const queueSnap = await tx.get(ref);
    if (processedSnap.exists) {
      if (queueSnap.exists) {
        tx.delete(ref);
      }
      return false;
    }

    tx.create(processedRef, {
      channel: normalizeString(options?.channel),
      type: normalizeString(options?.type),
      tripId: normalizeString(options?.tripId),
      processedAt: FieldValue.serverTimestamp(),
    });
    if (queueSnap.exists) {
      tx.delete(ref);
    }
    return true;
  });
}

module.exports = {
  buildNotificationQueueDocId,
  enqueueTripNotification,
  claimNotificationQueueDoc,
  releaseNotificationQueueDoc,
  completeNotificationQueueDoc,
};
