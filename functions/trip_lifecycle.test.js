const test = require('node:test');
const assert = require('node:assert/strict');
const {
  parisDayNumber,
  tripLastDay,
  dueLifecycleSteps,
  runTripLifecycle,
} = require('./trip_lifecycle');

// A trip's last day as the app stores it: local (Paris) midnight.
const parisMidnight = (y, m, d) => new Date(Date.UTC(y, m - 1, d) - 2 * 3600 * 1000);
const ts = (date) => ({ toDate: () => date });
const at = (y, m, d, h = 12) => new Date(Date.UTC(y, m - 1, d, h));

test('parisDayNumber uses the Paris calendar day', () => {
  // 23:30 UTC on Oct 1 is already Oct 2 in Paris (UTC+2).
  assert.equal(
    parisDayNumber(new Date(Date.UTC(2026, 9, 1, 23, 30))),
    parisDayNumber(at(2026, 10, 2))
  );
  assert.equal(parisDayNumber(parisMidnight(2026, 10, 2)), parisDayNumber(at(2026, 10, 2)));
});

test('tripLastDay falls back to the start date', () => {
  const start = parisMidnight(2026, 8, 1);
  assert.equal(tripLastDay({ startDate: ts(start) }), start);
  assert.equal(tripLastDay({}), null);
});

test('archive is due from day 30 after the last day, once', () => {
  const tripData = { endDate: ts(parisMidnight(2026, 8, 10)) };
  assert.equal(dueLifecycleSteps({ tripData, lifecycle: {}, now: at(2026, 9, 8) }).archive, false);
  assert.equal(dueLifecycleSteps({ tripData, lifecycle: {}, now: at(2026, 9, 9) }).archive, true);
  assert.equal(
    dueLifecycleSteps({ tripData, lifecycle: { autoArchivedAt: 1 }, now: at(2026, 9, 9) }).archive,
    false
  );
});

test('documents are due for deletion from day 60, regardless of archiving', () => {
  const tripData = { endDate: ts(parisMidnight(2026, 8, 10)) };
  const day59 = dueLifecycleSteps({ tripData, lifecycle: {}, now: at(2026, 10, 8) });
  const day60 = dueLifecycleSteps({ tripData, lifecycle: {}, now: at(2026, 10, 9) });
  assert.equal(day59.purgeWallet, false);
  assert.equal(day60.purgeWallet, true);
  assert.equal(day60.archive, true);
});

test('trips without dates are never processed', () => {
  assert.deepEqual(
    dueLifecycleSteps({ tripData: {}, lifecycle: {}, now: at(2027, 1, 1) }),
    { archive: false, purgeWallet: false }
  );
});

function fakeFirestore({ trips, lifecycle = {}, archived = {}, modules = {} }) {
  const writes = { lifecycle: { ...lifecycle }, archived: { ...archived } };
  const db = {
    writes,
    collection(name) {
      if (name === 'trips') {
        return {
          where() { return this; },
          async get() {
            const docs = Object.entries(trips).map(([id, data]) => ({
              id,
              data: () => data,
              ref: {
                collection: () => ({
                  listDocuments: async () => (modules[id] || []).map((uid) => ({ id: uid })),
                }),
              },
            }));
            return { size: docs.length, docs };
          },
        };
      }
      if (name === 'tripLifecycle') {
        return {
          doc: (id) => ({
            get: async () => ({ data: () => writes.lifecycle[id] }),
            set: async (data) => {
              writes.lifecycle[id] = { ...(writes.lifecycle[id] || {}), ...data };
            },
          }),
        };
      }
      if (name === 'users') {
        return {
          doc: (uid) => ({
            collection: () => ({
              doc: (tripId) => ({
                create: async (data) => {
                  const key = `${uid}/${tripId}`;
                  if (writes.archived[key]) {
                    const e = new Error('exists');
                    e.code = 6;
                    throw e;
                  }
                  writes.archived[key] = data;
                },
              }),
            }),
          }),
        };
      }
      throw new Error(`unexpected collection ${name}`);
    },
  };
  return db;
}

const FieldValue = { serverTimestamp: () => 'now' };
const Timestamp = { fromDate: (d) => d };

test('runTripLifecycle archives for every member and keeps manual archives', async () => {
  const db = fakeFirestore({
    trips: { t1: { endDate: ts(parisMidnight(2026, 8, 10)), memberUserIds: ['u1', 'u2'] } },
    archived: { 'u2/t1': { archivedAt: 'manual' } },
  });
  const deleted = [];
  const summary = await runTripLifecycle({
    db, bucket: {}, FieldValue, Timestamp, now: at(2026, 9, 20),
    deleteMemberWalletData: async ({ uid }) => { deleted.push(uid); return true; },
  });
  assert.deepEqual(db.writes.archived['u1/t1'], { archivedAt: 'now', auto: true });
  assert.deepEqual(db.writes.archived['u2/t1'], { archivedAt: 'manual' });
  assert.equal(db.writes.lifecycle.t1.autoArchivedAt, 'now');
  assert.deepEqual(deleted, []);
  assert.equal(summary.archived, 1);
});

test('runTripLifecycle deletes documents of members and former module owners', async () => {
  const db = fakeFirestore({
    trips: { t1: { endDate: ts(parisMidnight(2026, 8, 10)), memberUserIds: ['u1'] } },
    lifecycle: { t1: { autoArchivedAt: 'earlier' } },
    modules: { t1: ['u1', 'u9'] },
  });
  const deleted = [];
  await runTripLifecycle({
    db, bucket: {}, FieldValue, Timestamp, now: at(2026, 10, 10),
    deleteMemberWalletData: async ({ uid }) => { deleted.push(uid); return true; },
  });
  assert.deepEqual(deleted.sort(), ['u1', 'u9']);
  assert.equal(db.writes.lifecycle.t1.walletPurgedAt, 'now');
});

test('a failed deletion is retried on the next run', async () => {
  const db = fakeFirestore({
    trips: { t1: { endDate: ts(parisMidnight(2026, 8, 10)), memberUserIds: ['u1'] } },
    lifecycle: { t1: { autoArchivedAt: 'earlier' } },
  });
  const summary = await runTripLifecycle({
    db, bucket: {}, FieldValue, Timestamp, now: at(2026, 10, 10),
    deleteMemberWalletData: async () => false,
  });
  assert.equal(db.writes.lifecycle.t1.walletPurgedAt, undefined);
  assert.equal(summary.failed, 1);
});
