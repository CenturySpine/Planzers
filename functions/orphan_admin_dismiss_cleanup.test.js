const test = require('node:test');
const assert = require('node:assert/strict');
const {
  userIdFromDismissedAdminAnnouncementPath,
  collectOrphanDismissDocs,
} = require('./orphan_admin_dismiss_cleanup');

test('userIdFromDismissedAdminAnnouncementPath parses standard user dismiss path', () => {
  assert.equal(
    userIdFromDismissedAdminAnnouncementPath(
      'users/u1/dismissedAdminAnnouncements/a1'
    ),
    'u1'
  );
});

test('userIdFromDismissedAdminAnnouncementPath rejects non-user paths', () => {
  assert.equal(
    userIdFromDismissedAdminAnnouncementPath(
      'trips/t1/dismissedAdminAnnouncements/a1'
    ),
    null
  );
  assert.equal(
    userIdFromDismissedAdminAnnouncementPath(
      'users/u1/other/a1'
    ),
    null
  );
});

test('collectOrphanDismissDocs keeps living announcements and skips unknown paths', () => {
  const living = new Set(['keep']);
  const docs = [
    { id: 'keep', path: 'users/u1/dismissedAdminAnnouncements/keep' },
    { id: 'gone', path: 'users/u1/dismissedAdminAnnouncements/gone' },
    { id: 'gone', path: 'users/u2/dismissedAdminAnnouncements/gone' },
    {
      id: 'ghost',
      path: 'other/x/dismissedAdminAnnouncements/ghost',
    },
  ];
  const orphans = collectOrphanDismissDocs(living, docs);
  assert.equal(orphans.length, 2);
  assert.ok(orphans.some((o) => o.userId === 'u1' && o.announcementId === 'gone'));
  assert.ok(orphans.some((o) => o.userId === 'u2' && o.announcementId === 'gone'));
});
