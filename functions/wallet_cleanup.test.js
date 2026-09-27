const test = require('node:test');
const assert = require('node:assert/strict');
const {
  walletStoragePrefix,
  deleteMemberWalletData,
  deleteTripWalletFiles,
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

test('deleteMemberWalletData removes records and only that trip files', async () => {
  const bucket = fakeBucket([
    'users/u1/wallet/t1/a.pdf',
    'users/u1/wallet/t1/b.jpg',
    'users/u1/wallet/t2/c.pdf',
    'users/u1/profile_1.jpg',
    'users/u2/wallet/t1/d.pdf',
  ]);
  const db = fakeDb();
  await deleteMemberWalletData({ db, bucket, tripId: 't1', uid: 'u1' });
  assert.deepEqual(db.deleted, ['trips/t1/travelerModules/u1/walletDocuments']);
  assert.deepEqual(
    [...bucket.remaining].sort(),
    ['users/u1/profile_1.jpg', 'users/u1/wallet/t2/c.pdf', 'users/u2/wallet/t1/d.pdf']
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
  assert.equal(logged.length, 2);
});

test('deleteTripWalletFiles removes every member files for the trip only', async () => {
  const bucket = fakeBucket([
    'users/u1/wallet/t1/a.pdf',
    'users/u2/wallet/t1/b.pdf',
    'users/u2/wallet/t2/c.pdf',
    'trips/t1/banner_1.jpg',
  ]);
  await deleteTripWalletFiles({ bucket, tripId: 't1', memberUserIds: ['u1', 'u2', 'u2'] });
  assert.deepEqual(
    [...bucket.remaining].sort(),
    ['trips/t1/banner_1.jpg', 'users/u2/wallet/t2/c.pdf']
  );
});
