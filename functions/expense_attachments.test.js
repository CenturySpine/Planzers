const test = require('node:test');
const assert = require('node:assert/strict');
const {
  expenseAttachmentsStoragePrefix,
  deleteExpenseAttachmentFiles,
  deleteExpenseAttachments,
} = require('./expense_attachments');

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
  const chain = (p) => ({
    path: p,
    collection: (c) => ({
      path: `${p}/${c}`,
      doc: (d) => chain(`${p}/${c}/${d}`),
    }),
  });
  return {
    deleted,
    collection: (name) => ({ doc: (id) => chain(`${name}/${id}`) }),
    async recursiveDelete(target) {
      deleted.push(target.path);
    },
  };
}

test('expenseAttachmentsStoragePrefix targets one expense of one trip', () => {
  assert.equal(expenseAttachmentsStoragePrefix('t1', 'e1'), 'trips/t1/expenses/e1/');
});

test('expenseAttachmentsStoragePrefix refuses ids that could widen the prefix', () => {
  assert.equal(expenseAttachmentsStoragePrefix('', 'e1'), null);
  assert.equal(expenseAttachmentsStoragePrefix('t1', ''), null);
  assert.equal(expenseAttachmentsStoragePrefix('t1/..', 'e1'), null);
  assert.equal(expenseAttachmentsStoragePrefix('t1', 'e1/x'), null);
});

test('deleteExpenseAttachmentFiles removes the receipt and its thumbnail only', async () => {
  const bucket = fakeBucket([
    'trips/t1/expenses/e1/a1.jpg',
    'trips/t1/expenses/e1/a1_thumb.jpg',
    'trips/t1/expenses/e1/a10.jpg',
  ]);
  await deleteExpenseAttachmentFiles({ bucket, tripId: 't1', expenseId: 'e1', attachmentId: 'a1' });
  assert.deepEqual([...bucket.remaining], ['trips/t1/expenses/e1/a10.jpg']);
});

test('deleteExpenseAttachmentFiles ignores files already gone and unsafe ids', async () => {
  const bucket = fakeBucket(['trips/t1/expenses/e1/a1.jpg']);
  await deleteExpenseAttachmentFiles({ bucket, tripId: 't1', expenseId: 'e1', attachmentId: 'a1' });
  await deleteExpenseAttachmentFiles({ bucket, tripId: 't1', expenseId: 'e1', attachmentId: '../x' });
  assert.deepEqual([...bucket.remaining], []);
});

test('deleteExpenseAttachments removes the records and files of that expense only', async () => {
  const bucket = fakeBucket([
    'trips/t1/expenses/e1/a1.jpg',
    'trips/t1/expenses/e1/a1_thumb.jpg',
    'trips/t1/expenses/e2/a2.jpg',
    'trips/t1/banner_1.jpg',
  ]);
  const db = fakeDb();
  await deleteExpenseAttachments({ db, bucket, tripId: 't1', expenseId: 'e1' });
  assert.deepEqual(db.deleted, ['trips/t1/expenses/e1/attachments']);
  assert.deepEqual(
    [...bucket.remaining].sort(),
    ['trips/t1/banner_1.jpg', 'trips/t1/expenses/e2/a2.jpg']
  );
});

test('deleteExpenseAttachments does nothing for unsafe ids', async () => {
  const bucket = fakeBucket(['trips/t1/expenses/e1/a1.jpg']);
  const db = fakeDb();
  await deleteExpenseAttachments({ db, bucket, tripId: 't1', expenseId: '' });
  assert.deepEqual(db.deleted, []);
  assert.deepEqual([...bucket.remaining], ['trips/t1/expenses/e1/a1.jpg']);
});
