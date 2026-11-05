/**
 * Server-side cleanup of the receipts attached to expenses:
 * - records under trips/{tripId}/expenses/{expenseId}/attachments;
 * - files under trips/{tripId}/expenses/{expenseId}/ (<id>.jpg and
 *   <id>_thumb.jpg).
 *
 * Receipts belong to their expense, not to the traveler who added them:
 * they stay when that traveler leaves the trip, and go with the expense
 * (and with the trip's Storage purge when the trip is deleted).
 */

const { deleteStoragePrefix } = require('./wallet_cleanup');

const SAFE_SEGMENT = /^[A-Za-z0-9_-]+$/;

/**
 * @param {string} tripId
 * @param {string} expenseId
 * @returns {string|null} Storage prefix of the expense's receipts, or null
 *   for unsafe ids (never delete a broader prefix than one expense).
 */
function expenseAttachmentsStoragePrefix(tripId, expenseId) {
  if (!SAFE_SEGMENT.test(String(tripId || '')) || !SAFE_SEGMENT.test(String(expenseId || ''))) {
    return null;
  }
  return `trips/${tripId}/expenses/${expenseId}/`;
}

/**
 * Deletes the two files of one receipt; "not found" is ignored.
 * @param {{ bucket: object, tripId: string, expenseId: string, attachmentId: string }} args
 */
async function deleteExpenseAttachmentFiles({ bucket, tripId, expenseId, attachmentId }) {
  const prefix = expenseAttachmentsStoragePrefix(tripId, expenseId);
  if (!prefix || !SAFE_SEGMENT.test(String(attachmentId || ''))) return;
  for (const name of [`${attachmentId}.jpg`, `${attachmentId}_thumb.jpg`]) {
    try {
      await bucket.file(`${prefix}${name}`).delete();
    } catch (e) {
      const code = String(e?.code ?? '');
      if (code === '404' || code === 'not-found') continue;
      throw e;
    }
  }
}

/**
 * Removes every receipt of a deleted expense: its records, then its files
 * (including any left without a record).
 * @param {{ db: object, bucket: object, tripId: string, expenseId: string }} args
 */
async function deleteExpenseAttachments({ db, bucket, tripId, expenseId }) {
  const prefix = expenseAttachmentsStoragePrefix(tripId, expenseId);
  if (!prefix) return;
  await db.recursiveDelete(
    db
      .collection('trips')
      .doc(tripId)
      .collection('expenses')
      .doc(expenseId)
      .collection('attachments')
  );
  await deleteStoragePrefix(bucket, prefix);
}

module.exports = {
  expenseAttachmentsStoragePrefix,
  deleteExpenseAttachmentFiles,
  deleteExpenseAttachments,
};
