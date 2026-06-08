const test = require('node:test');
const assert = require('node:assert/strict');
const {
  buildNotificationQueueDocId,
  enqueueTripNotification,
  claimAndDeleteNotificationQueueDoc,
} = require('./notification_queue');

test('buildNotificationQueueDocId for trip_message', () => {
  assert.equal(
    buildNotificationQueueDocId('trip_message', {
      tripId: 'trip-1',
      messageId: 'msg-1',
    }),
    'trip_message__trip-1__msg-1'
  );
});

test('buildNotificationQueueDocId for trip_activity', () => {
  assert.equal(
    buildNotificationQueueDocId('trip_activity', {
      tripId: 'trip-1',
      activityId: 'act-1',
    }),
    'trip_activity__trip-1__act-1'
  );
});

test('buildNotificationQueueDocId for trip_announcement', () => {
  assert.equal(
    buildNotificationQueueDocId('trip_announcement', {
      tripId: 'trip-1',
      announcementId: 'ann-1',
    }),
    'trip_announcement__trip-1__ann-1'
  );
});

test('buildNotificationQueueDocId for cupidon_match', () => {
  assert.equal(
    buildNotificationQueueDocId('cupidon_match', {
      tripId: 'trip-1',
      matchId: 'match-1',
      notifiedUid: 'uid-a',
    }),
    'cupidon_match__trip-1__match-1__uid-a'
  );
});

test('buildNotificationQueueDocId for expense reimbursement types', () => {
  assert.equal(
    buildNotificationQueueDocId('expense_reimbursement_paid', {
      tripId: 'trip-1',
      expenseId: 'exp-1',
    }),
    'expense_reimbursement_paid__trip-1__exp-1'
  );
  assert.equal(
    buildNotificationQueueDocId('expense_reimbursement_unpaid', {
      tripId: 'trip-1',
      expenseId: 'exp-2',
    }),
    'expense_reimbursement_unpaid__trip-1__exp-2'
  );
});

test('enqueueTripNotification returns enqueued true on create', async () => {
  const createCalls = [];
  const db = {
    collection() {
      return {
        doc(docId) {
          return {
            async create(payload) {
              createCalls.push({ docId, payload });
            },
          };
        },
      };
    },
  };

  const result = await enqueueTripNotification(db, {
    docId: 'trip_message__t__m',
    payload: { type: 'trip_message', tripId: 't' },
  });

  assert.deepEqual(result, { enqueued: true });
  assert.equal(createCalls.length, 1);
  assert.equal(createCalls[0].docId, 'trip_message__t__m');
  assert.equal(createCalls[0].payload.type, 'trip_message');
  assert.ok(createCalls[0].payload.createdAt);
});

test('enqueueTripNotification returns enqueued false on ALREADY_EXISTS', async () => {
  const db = {
    collection() {
      return {
        doc() {
          return {
            async create() {
              const error = new Error('already exists');
              error.code = 'already-exists';
              throw error;
            },
          };
        },
      };
    },
  };

  const result = await enqueueTripNotification(db, {
    docId: 'trip_message__t__m',
    payload: { type: 'trip_message' },
  });

  assert.deepEqual(result, { enqueued: false });
});

test('claimAndDeleteNotificationQueueDoc returns null when doc absent', async () => {
  const db = {
    runTransaction(callback) {
      const tx = {
        async get() {
          return { exists: false };
        },
        delete() {
          throw new Error('delete should not be called');
        },
      };
      return callback(tx);
    },
  };

  const result = await claimAndDeleteNotificationQueueDoc(db, { path: 'notificationQueue/x' });
  assert.equal(result, null);
});

test('claimAndDeleteNotificationQueueDoc deletes and returns data when doc present', async () => {
  let deletedRef = null;
  const db = {
    runTransaction(callback) {
      const tx = {
        async get() {
          return {
            exists: true,
            data() {
              return { type: 'trip_message', tripId: 't' };
            },
          };
        },
        delete(ref) {
          deletedRef = ref;
        },
      };
      return callback(tx);
    },
  };

  const ref = { path: 'notificationQueue/x' };
  const result = await claimAndDeleteNotificationQueueDoc(db, ref);

  assert.deepEqual(result, { type: 'trip_message', tripId: 't' });
  assert.equal(deletedRef, ref);
});
