const test = require('node:test');
const assert = require('node:assert/strict');
const {
  buildNotificationQueueDocId,
  enqueueTripNotification,
  claimAndDeleteNotificationQueueDoc,
  deliverNotificationBatch,
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

test('deliverNotificationBatch does not increment unread counters when FCM throws', async () => {
  let incrementCalled = false;
  let cleanupCalled = false;

  await assert.rejects(
    deliverNotificationBatch({
      db: {},
      tokenEntries: [{ token: 'token-1' }],
      messages: [{ token: 'token-1' }],
      tripId: 'trip-1',
      recipients: ['user-1'],
      channel: 'messages',
      async sendEach() {
        throw new Error('FCM unavailable');
      },
      async incrementTripUnreadCounters() {
        incrementCalled = true;
      },
      async cleanupInvalidFcmTokens() {
        cleanupCalled = true;
      },
    }),
    /FCM unavailable/,
  );

  assert.equal(incrementCalled, false);
  assert.equal(cleanupCalled, false);
});

test('deliverNotificationBatch increments unread counters after FCM accepts messages', async () => {
  const calls = [];

  await deliverNotificationBatch({
    db: {},
    tokenEntries: [{ token: 'token-1' }],
    messages: [{ token: 'token-1' }],
    tripId: 'trip-1',
    recipients: ['user-1'],
    channel: 'messages',
    async sendEach(messages) {
      calls.push(['sendEach', messages.length]);
      return { responses: [{ success: true }] };
    },
    async incrementTripUnreadCounters(args) {
      calls.push(['increment', args.tripId, args.recipients, args.channel]);
    },
    async cleanupInvalidFcmTokens(_db, result, tokenEntries) {
      calls.push(['cleanup', result.responses.length, tokenEntries.length]);
    },
  });

  assert.deepEqual(calls, [
    ['sendEach', 1],
    ['increment', 'trip-1', ['user-1'], 'messages'],
    ['cleanup', 1, 1],
  ]);
});

test('deliverNotificationBatch still increments unread counters when recipients have no tokens', async () => {
  const calls = [];

  await deliverNotificationBatch({
    db: {},
    tokenEntries: [],
    messages: [],
    tripId: 'trip-1',
    recipients: ['user-1'],
    channel: 'messages',
    async sendEach() {
      calls.push('sendEach');
    },
    async incrementTripUnreadCounters(args) {
      calls.push(['increment', args.tripId, args.recipients, args.channel]);
    },
    async cleanupInvalidFcmTokens() {
      calls.push('cleanup');
    },
  });

  assert.deepEqual(calls, [
    ['increment', 'trip-1', ['user-1'], 'messages'],
  ]);
});
