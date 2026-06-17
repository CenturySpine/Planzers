const test = require('node:test');
const assert = require('node:assert/strict');
const {
  buildNotificationQueueDocId,
  enqueueTripNotification,
  claimNotificationQueueDoc,
  releaseNotificationQueueDoc,
  completeNotificationQueueDoc,
} = require('./notification_queue');

function ref(collection, id) {
  return { collection, id, path: `${collection}/${id}` };
}

function dbWithTransaction(createTransaction) {
  return {
    collection(collection) {
      return {
        doc(id) {
          return ref(collection, id);
        },
      };
    },
    runTransaction(transactionCallback) {
      return transactionCallback(createTransaction());
    },
  };
}

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
  const db = dbWithTransaction(() => ({
    async get() {
      return { exists: false };
    },
    create(documentRef, payload) {
      createCalls.push({ documentRef, payload });
    },
  }));

  const result = await enqueueTripNotification(db, {
    docId: 'trip_message__t__m',
    payload: { type: 'trip_message', tripId: 't' },
  });

  assert.deepEqual(result, { enqueued: true });
  assert.equal(createCalls.length, 1);
  assert.equal(createCalls[0].documentRef.path, 'notificationQueue/trip_message__t__m');
  assert.equal(createCalls[0].payload.type, 'trip_message');
  assert.equal(createCalls[0].payload.status, 'pending');
  assert.ok(createCalls[0].payload.createdAt);
});

test('enqueueTripNotification returns enqueued false when queue doc exists', async () => {
  const createCalls = [];
  const db = dbWithTransaction(() => ({
    async get(documentRef) {
      return { exists: documentRef.collection === 'notificationQueue' };
    },
    create(documentRef, payload) {
      createCalls.push({ documentRef, payload });
    },
  }));

  const result = await enqueueTripNotification(db, {
    docId: 'trip_message__t__m',
    payload: { type: 'trip_message' },
  });

  assert.deepEqual(result, { enqueued: false });
  assert.equal(createCalls.length, 0);
});

test('enqueueTripNotification returns enqueued false when already processed', async () => {
  const createCalls = [];
  const db = dbWithTransaction(() => ({
    async get(documentRef) {
      return { exists: documentRef.collection === 'notificationQueueProcessed' };
    },
    create(documentRef, payload) {
      createCalls.push({ documentRef, payload });
    },
  }));

  const result = await enqueueTripNotification(db, {
    docId: 'trip_message__t__m',
    payload: { type: 'trip_message' },
  });

  assert.deepEqual(result, { enqueued: false });
  assert.equal(createCalls.length, 0);
});

test('claimNotificationQueueDoc returns absent when doc missing', async () => {
  const db = dbWithTransaction(() => ({
    async get() {
      return { exists: false };
    },
    update() {
      throw new Error('update should not be called');
    },
  }));

  const result = await claimNotificationQueueDoc(db, ref('notificationQueue', 'x'));
  assert.deepEqual(result, { claimed: false, retry: false, reason: 'absent' });
});

test('claimNotificationQueueDoc marks pending doc as processing', async () => {
  let updatedRef = null;
  let updatedPayload = null;
  const db = dbWithTransaction(() => ({
    async get() {
      return {
        exists: true,
        data() {
          return { type: 'trip_message', tripId: 't', status: 'pending' };
        },
      };
    },
    update(documentRef, payload) {
      updatedRef = documentRef;
      updatedPayload = payload;
    },
  }));

  const queueRef = ref('notificationQueue', 'x');
  const result = await claimNotificationQueueDoc(db, queueRef);

  assert.deepEqual(result, {
    claimed: true,
    data: { type: 'trip_message', tripId: 't', status: 'pending' },
  });
  assert.equal(updatedRef, queueRef);
  assert.equal(updatedPayload.status, 'processing');
  assert.ok(updatedPayload.processingLeaseExpiresAt);
});

test('claimNotificationQueueDoc asks retry while another worker owns the lease', async () => {
  const db = dbWithTransaction(() => ({
    async get() {
      return {
        exists: true,
        data() {
          return {
            status: 'processing',
            processingLeaseExpiresAt: { toMillis: () => Date.now() + 60_000 },
          };
        },
      };
    },
    update() {
      throw new Error('update should not be called');
    },
  }));

  const result = await claimNotificationQueueDoc(db, ref('notificationQueue', 'x'));

  assert.deepEqual(result, { claimed: false, retry: true, reason: 'processing' });
});

test('releaseNotificationQueueDoc restores pending status after failure', async () => {
  let updatedPayload = null;
  const db = dbWithTransaction(() => ({
    async get() {
      return { exists: true };
    },
    update(_documentRef, payload) {
      updatedPayload = payload;
    },
  }));

  const result = await releaseNotificationQueueDoc(
    db,
    ref('notificationQueue', 'x'),
    new Error('send failed')
  );

  assert.equal(result, true);
  assert.equal(updatedPayload.status, 'pending');
  assert.equal(updatedPayload.lastError, 'send failed');
  assert.ok(updatedPayload.processingLeaseExpiresAt);
});

test('completeNotificationQueueDoc writes processed marker and deletes queue doc', async () => {
  const createCalls = [];
  let deletedRef = null;
  const db = dbWithTransaction(() => ({
    async get(documentRef) {
      return { exists: documentRef.collection === 'notificationQueue' };
    },
    create(documentRef, payload) {
      createCalls.push({ documentRef, payload });
    },
    delete(documentRef) {
      deletedRef = documentRef;
    },
  }));

  const queueRef = ref('notificationQueue', 'trip_message__t__m');
  const result = await completeNotificationQueueDoc(db, queueRef, {
    docId: 'trip_message__t__m',
    channel: 'messages',
    type: 'trip_message',
    tripId: 't',
  });

  assert.equal(result, true);
  assert.equal(createCalls.length, 1);
  assert.equal(createCalls[0].documentRef.path, 'notificationQueueProcessed/trip_message__t__m');
  assert.equal(createCalls[0].payload.type, 'trip_message');
  assert.equal(deletedRef, queueRef);
});

test('completeNotificationQueueDoc only deletes queue doc when marker already exists', async () => {
  const createCalls = [];
  let deletedRef = null;
  const db = dbWithTransaction(() => ({
    async get() {
      return { exists: true };
    },
    create(documentRef, payload) {
      createCalls.push({ documentRef, payload });
    },
    delete(documentRef) {
      deletedRef = documentRef;
    },
  }));

  const queueRef = ref('notificationQueue', 'trip_message__t__m');
  const result = await completeNotificationQueueDoc(db, queueRef, {
    docId: 'trip_message__t__m',
  });

  assert.equal(result, false);
  assert.equal(createCalls.length, 0);
  assert.equal(deletedRef, queueRef);
});
