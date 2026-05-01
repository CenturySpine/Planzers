/**
 * @param {string} path Firestore document path
 * @returns {string|null} user id from users/{uid}/dismissedAdminAnnouncements/{announcementId}
 */
function userIdFromDismissedAdminAnnouncementPath(path) {
  const parts = typeof path === 'string' ? path.split('/') : [];
  if (
    parts.length === 4 &&
    parts[0] === 'users' &&
    parts[2] === 'dismissedAdminAnnouncements'
  ) {
    return parts[1] || null;
  }
  return null;
}

/**
 * @param {Set<string>|Iterable<string>} livingAnnouncementIds
 * @param {Array<{ id: string, path: string }>} dismissDocs
 * @returns {{ refPath: string, announcementId: string, userId: string }[]}
 */
function collectOrphanDismissDocs(livingAnnouncementIds, dismissDocs) {
  const living =
    livingAnnouncementIds instanceof Set
      ? livingAnnouncementIds
      : new Set(livingAnnouncementIds);

  /** @type {{ refPath: string, announcementId: string, userId: string }[]} */
  const orphans = [];
  for (const doc of dismissDocs) {
    const announcementId = doc.id;
    const docPath = doc.path;
    if (living.has(announcementId)) continue;
    const userId = userIdFromDismissedAdminAnnouncementPath(docPath);
    if (!userId) continue;
    orphans.push({
      refPath: docPath,
      announcementId,
      userId,
    });
  }
  return orphans;
}

module.exports = {
  userIdFromDismissedAdminAnnouncementPath,
  collectOrphanDismissDocs,
};
