/**
 * Server-side cleanup of a traveler's personal data for a trip, which share
 * the same retention (leaving the trip, removal, trip deletion, purge after
 * the trip):
 * - personal documents ("Mes documents"): records under
 *   trips/{tripId}/travelerModules/{uid}/walletDocuments, files under
 *   users/{uid}/wallet/{tripId}/;
 * - activity photos: records under
 *   trips/{tripId}/travelerModules/{uid}/activityPhotos, files under
 *   users/{uid}/activityPhotos/{tripId}/, and the traveler's favorite photo
 *   choices under trips/{tripId}/travelerModules/{uid}/activityFavorites.
 *
 * The files live outside trips/{tripId}/ (owner-only Storage paths), so the
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
 * @param {string} uid
 * @param {string} tripId
 * @returns {string|null} Storage prefix of the traveler's activity photos
 *   for the trip, or null for unsafe ids.
 */
function activityPhotosStoragePrefix(uid, tripId) {
  if (!SAFE_SEGMENT.test(String(uid || '')) || !SAFE_SEGMENT.test(String(tripId || ''))) {
    return null;
  }
  return `users/${uid}/activityPhotos/${tripId}/`;
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
 * Removes a traveler's personal data (documents and activity photos, records
 * and files, and favorite photo choices) for one trip.
 * Best effort: logs and swallows errors so the calling flow (leaving a trip,
 * removing a member) never fails because of this cleanup.
 * @returns {Promise<boolean>} false when part of the cleanup failed
 * @param {{ db: object, bucket: object, tripId: string, uid: string, logger?: object }} args
 */
async function deleteMemberWalletData({ db, bucket, tripId, uid, logger = console }) {
  const walletPrefix = walletStoragePrefix(uid, tripId);
  const photosPrefix = activityPhotosStoragePrefix(uid, tripId);
  if (!walletPrefix || !photosPrefix) return true;
  const moduleRef = db
    .collection('trips')
    .doc(tripId)
    .collection('travelerModules')
    .doc(uid);
  let ok = true;
  for (const [collection, prefix] of [
    ['walletDocuments', walletPrefix],
    ['activityPhotos', photosPrefix],
    ['activityFavorites', null],
  ]) {
    try {
      await db.recursiveDelete(moduleRef.collection(collection));
    } catch (e) {
      ok = false;
      logger.error('personal data cleanup: records not deleted', {
        tripId, uid, collection, error: String(e),
      });
    }
    if (!prefix) continue;
    try {
      await deleteStoragePrefix(bucket, prefix);
    } catch (e) {
      ok = false;
      logger.error('personal data cleanup: files not deleted', {
        tripId, uid, collection, error: String(e),
      });
    }
  }
  return ok;
}

/**
 * Removes the personal files (documents and activity photos) of every listed
 * member for a trip being deleted (records go with the trip's recursive
 * delete).
 * @param {{ bucket: object, tripId: string, memberUserIds: unknown }} args
 */
async function deleteTripWalletFiles({ bucket, tripId, memberUserIds }) {
  const uids = Array.isArray(memberUserIds)
    ? [...new Set(memberUserIds.map((v) => String(v)))]
    : [];
  for (const uid of uids) {
    for (const prefix of [
      walletStoragePrefix(uid, tripId),
      activityPhotosStoragePrefix(uid, tripId),
    ]) {
      if (prefix) await deleteStoragePrefix(bucket, prefix);
    }
  }
}

/**
 * Deletes the two files of one activity photo; "not found" is ignored.
 * @param {{ bucket: object, tripId: string, uid: string, photoId: string }} args
 */
async function deleteActivityPhotoFiles({ bucket, tripId, uid, photoId }) {
  const prefix = activityPhotosStoragePrefix(uid, tripId);
  if (!prefix || !SAFE_SEGMENT.test(String(photoId || ''))) return;
  for (const name of [`${photoId}.jpg`, `${photoId}_thumb.jpg`]) {
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
 * Deletes every traveler's photo records attached to an activity (their
 * files are removed by the per-photo deletion trigger).
 * @returns {Promise<number>} number of records deleted
 * @param {{ db: object, tripId: string, activityId: string }} args
 */
async function deleteActivityPhotoRecords({ db, tripId, activityId }) {
  if (!SAFE_SEGMENT.test(String(tripId || '')) || !activityId) return 0;
  const moduleRefs = await db
    .collection('trips')
    .doc(tripId)
    .collection('travelerModules')
    .listDocuments();
  let deleted = 0;
  for (const moduleRef of moduleRefs) {
    const snap = await moduleRef
      .collection('activityPhotos')
      .where('activityId', '==', activityId)
      .get();
    for (const doc of snap.docs) {
      await doc.ref.delete();
      deleted++;
    }
  }
  return deleted;
}

module.exports = {
  walletStoragePrefix,
  activityPhotosStoragePrefix,
  deleteStoragePrefix,
  deleteMemberWalletData,
  deleteTripWalletFiles,
  deleteActivityPhotoFiles,
  deleteActivityPhotoRecords,
};
