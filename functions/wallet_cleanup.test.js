const test = require('node:test');
const assert = require('node:assert/strict');
const {
  walletStoragePrefix,
  activityPhotosStoragePrefix,
  deleteMemberWalletData,
  deleteTripWalletFiles,
  deleteActivityPhotoFiles,
  deleteActivityPhotoRecords,
  deleteMealPhotoRecords,
} = require('./wallet_cleanup');

function fakeBucket(paths) {
  const remaining = new Set(paths);
  return {
    remaining,
    async getFiles({ prefix }) {
      const files = [...remaining]
        .filter((p) => p.startsWith(prefix))
        .map((p) => ({ name: p, delete: async () => remaining.delete(p) }));
      return [files];
    },
    file(path) {
      return {
        async delete() {
          if (!remaining.delete(path)) {
            const e = new Error('No such object');
            e.code = 404;
            throw e;
          }
        },
      };
    },
  };
}

function fakeDb() {
  const deleted = [];
  return {
    deleted,
    collection: (name) => ({
      doc: (id) => {
        const base = `${name}/${id}`;
        const chain = (p) => ({
          collection: (c) => ({
            path: `${p}/${c}`,
            doc: (d) => chain(`${p}/${c}/${d}`),
          }),
        });
        return chain(base);
      },
    }),
    async recursiveDelete(target) {
      deleted.push(target.path);
    },
  };
}

test('walletStoragePrefix targets one trip of one user', () => {
  assert.equal(walletStoragePrefix('u1', 't1'), 'users/u1/wallet/t1/');
});

test('walletStoragePrefix refuses ids that could widen the prefix', () => {
  assert.equal(walletStoragePrefix('', 't1'), null);
  assert.equal(walletStoragePrefix('u1', ''), null);
  assert.equal(walletStoragePrefix('u1/..', 't1'), null);
  assert.equal(walletStoragePrefix('u1', 't1/x'), null);
});

test('activityPhotosStoragePrefix targets one trip of one user', () => {
  assert.equal(activityPhotosStoragePrefix('u1', 't1'), 'users/u1/activityPhotos/t1/');
  assert.equal(activityPhotosStoragePrefix('u1/..', 't1'), null);
  assert.equal(activityPhotosStoragePrefix('u1', ''), null);
});

test('deleteMemberWalletData removes documents and photos of that trip only', async () => {
  const bucket = fakeBucket([
    'users/u1/wallet/t1/a.pdf',
    'users/u1/wallet/t1/b.jpg',
    'users/u1/wallet/t2/c.pdf',
    'users/u1/activityPhotos/t1/p1.jpg',
    'users/u1/activityPhotos/t1/p1_thumb.jpg',
    'users/u1/activityPhotos/t2/p2.jpg',
    'users/u1/profile_1.jpg',
    'users/u2/wallet/t1/d.pdf',
  ]);
  const db = fakeDb();
  await deleteMemberWalletData({ db, bucket, tripId: 't1', uid: 'u1' });
  assert.deepEqual(db.deleted, [
    'trips/t1/travelerModules/u1/walletDocuments',
    'trips/t1/travelerModules/u1/activityPhotos',
    'trips/t1/travelerModules/u1/activityFavorites',
  ]);
  assert.deepEqual(
    [...bucket.remaining].sort(),
    [
      'users/u1/activityPhotos/t2/p2.jpg',
      'users/u1/profile_1.jpg',
      'users/u1/wallet/t2/c.pdf',
      'users/u2/wallet/t1/d.pdf',
    ]
  );
});

test('deleteMemberWalletData never throws', async () => {
  const bucket = { getFiles: async () => { throw new Error('storage down'); } };
  const db = fakeDb();
  db.recursiveDelete = async () => { throw new Error('firestore down'); };
  const logged = [];
  await deleteMemberWalletData({
    db, bucket, tripId: 't1', uid: 'u1', logger: { error: (m) => logged.push(m) },
  });
  // Records of the three collections, files of the two with Storage.
  assert.equal(logged.length, 5);
});

test('deleteTripWalletFiles removes every member files for the trip only', async () => {
  const bucket = fakeBucket([
    'users/u1/wallet/t1/a.pdf',
    'users/u2/wallet/t1/b.pdf',
    'users/u2/wallet/t2/c.pdf',
    'users/u2/activityPhotos/t1/p1.jpg',
    'users/u2/activityPhotos/t2/p2.jpg',
    'trips/t1/banner_1.jpg',
  ]);
  await deleteTripWalletFiles({ bucket, tripId: 't1', memberUserIds: ['u1', 'u2', 'u2'] });
  assert.deepEqual(
    [...bucket.remaining].sort(),
    ['trips/t1/banner_1.jpg', 'users/u2/activityPhotos/t2/p2.jpg', 'users/u2/wallet/t2/c.pdf']
  );
});

test('deleteActivityPhotoFiles removes the photo and its thumbnail only', async () => {
  const bucket = fakeBucket([
    'users/u1/activityPhotos/t1/p1.jpg',
    'users/u1/activityPhotos/t1/p1_thumb.jpg',
    'users/u1/activityPhotos/t1/p10.jpg',
  ]);
  await deleteActivityPhotoFiles({ bucket, tripId: 't1', uid: 'u1', photoId: 'p1' });
  assert.deepEqual([...bucket.remaining], ['users/u1/activityPhotos/t1/p10.jpg']);
  // Already gone: nothing to do, no error.
  await deleteActivityPhotoFiles({ bucket, tripId: 't1', uid: 'u1', photoId: 'p1' });
});

test('deleteActivityPhotoFiles refuses unsafe ids', async () => {
  const bucket = fakeBucket(['users/u1/activityPhotos/t1/p1.jpg']);
  await deleteActivityPhotoFiles({ bucket, tripId: 't1', uid: 'u1', photoId: '../p1' });
  await deleteActivityPhotoFiles({ bucket, tripId: 't1', uid: 'u1', photoId: '' });
  assert.deepEqual([...bucket.remaining], ['users/u1/activityPhotos/t1/p1.jpg']);
});

test('deleteActivityPhotoRecords deletes every traveler photo of the activity', async () => {
  const photos = {
    u1: [{ id: 'p1', activityId: 'a1' }, { id: 'p2', activityId: 'a2' }],
    u2: [{ id: 'p3', activityId: 'a1' }],
  };
  const deleted = [];
  const db = {
    collection: () => ({
      doc: () => ({
        collection: () => ({
          listDocuments: async () =>
            Object.keys(photos).map((uid) => ({
              collection: () => ({
                where: (field, op, value) => ({
                  get: async () => ({
                    docs: photos[uid]
                      .filter((p) => p[field] === value)
                      .map((p) => ({ ref: { delete: async () => deleted.push(`${uid}/${p.id}`) } })),
                  }),
                }),
              }),
            })),
        }),
      }),
    }),
  };
  const count = await deleteActivityPhotoRecords({ db, tripId: 't1', activityId: 'a1' });
  assert.equal(count, 2);
  assert.deepEqual(deleted.sort(), ['u1/p1', 'u2/p3']);
});

test('deleteMealPhotoRecords deletes every traveler photo of the meal only', async () => {
  const photos = {
    u1: [{ id: 'p1', mealId: 'm1' }, { id: 'p2', activityId: 'm1' }],
    u2: [{ id: 'p3', mealId: 'm1' }, { id: 'p4', mealId: 'm2' }],
  };
  const deleted = [];
  const db = {
    collection: () => ({
      doc: () => ({
        collection: () => ({
          listDocuments: async () =>
            Object.keys(photos).map((uid) => ({
              collection: () => ({
                where: (field, op, value) => ({
                  get: async () => ({
                    docs: photos[uid]
                      .filter((p) => p[field] === value)
                      .map((p) => ({ ref: { delete: async () => deleted.push(`${uid}/${p.id}`) } })),
                  }),
                }),
              }),
            })),
        }),
      }),
    }),
  };
  const count = await deleteMealPhotoRecords({ db, tripId: 't1', mealId: 'm1' });
  assert.equal(count, 2);
  assert.deepEqual(deleted.sort(), ['u1/p1', 'u2/p3']);
});
