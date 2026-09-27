/**
 * Server-side cleanup of the personal documents ("Mes documents") of a
 * traveler for a trip: the records under
 * trips/{tripId}/travelerModules/{uid}/walletDocuments and the files under
 * users/{uid}/wallet/{tripId}/ in Storage.
 *
 * The files live outside trips/{tripId}/ (owner-only Storage path), so the
 * trip-wide Storage cleanup does not reach them.
 */

const SAFE_SEGMENT = /^[A-Za-z0-9_-]+$/;

/**
 * @param {string} uid
 * @param {string} tripId
 * @returns {string|null} Storage prefix, or null for unsafe ids (never
 *   delete a broader prefix than one trip of one user).
 */
function walletStoragePrefix(uid, tripId) {
  if (!SAFE_SEGMENT.test(String(uid || '')) || !SAFE_SEGMENT.test(String(tripId || ''))) {
    return null;
  }
  return `users/${uid}/wallet/${tripId}/`;
}

/**
 * Deletes every object under [prefix]; "not found" is ignored.
 * @param {{ getFiles: Function }} bucket
 * @param {string} prefix
 */
async function deleteStoragePrefix(bucket, prefix) {
  const [files] = await bucket.getFiles({ prefix, autoPaginate: true });
  if (!Array.isArray(files) || files.length === 0) return 0;
  await Promise.all(
    files.map(async (file) => {
      try {
        await file.delete();
      } catch (e) {
        const code = String(e?.code ?? '');
        if (code === '404' || code === 'not-found') return;
        throw e;
      }
    })
  );
  return files.length;
}

/**
 * Removes a traveler's wallet documents (records and files) for one trip.
 * Best effort: logs and swallows errors so the calling flow (leaving a trip,
 * removing a member) never fails because of this cleanup.
 * @returns {Promise<boolean>} false when part of the cleanup failed
 * @param {{ db: object, bucket: object, tripId: string, uid: string, logger?: object }} args
 */
async function deleteMemberWalletData({ db, bucket, tripId, uid, logger = console }) {
  const prefix = walletStoragePrefix(uid, tripId);
  if (!prefix) return true;
  let ok = true;
  try {
    await db.recursiveDelete(
      db
        .collection('trips')
        .doc(tripId)
        .collection('travelerModules')
        .doc(uid)
        .collection('walletDocuments')
    );
  } catch (e) {
    ok = false;
    logger.error('wallet cleanup: records not deleted', { tripId, uid, error: String(e) });
  }
  try {
    await deleteStoragePrefix(bucket, prefix);
  } catch (e) {
    ok = false;
    logger.error('wallet cleanup: files not deleted', { tripId, uid, error: String(e) });
  }
  return ok;
}

/**
 * Removes the wallet files of every listed member for a trip being deleted
 * (records go with the trip's recursive delete).
 * @param {{ bucket: object, tripId: string, memberUserIds: unknown }} args
 */
async function deleteTripWalletFiles({ bucket, tripId, memberUserIds }) {
  const uids = Array.isArray(memberUserIds)
    ? [...new Set(memberUserIds.map((v) => String(v)))]
    : [];
  for (const uid of uids) {
    const prefix = walletStoragePrefix(uid, tripId);
    if (prefix) await deleteStoragePrefix(bucket, prefix);
  }
}

module.exports = {
  walletStoragePrefix,
  deleteStoragePrefix,
  deleteMemberWalletData,
  deleteTripWalletFiles,
};
