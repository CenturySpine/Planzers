'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const test = require('node:test');

class FakeTimestamp {}
class FakeGeoPoint {}
class FakeDocumentReference {}

const fakeAdmin = {
  firestore: {
    Timestamp: FakeTimestamp,
    GeoPoint: FakeGeoPoint,
    DocumentReference: FakeDocumentReference,
  },
};

const originalLoad = Module._load;
Module._load = function load(request, parent, isMain) {
  if (
    request === 'firebase-admin' ||
    request.endsWith('/firebase-admin') ||
    request.endsWith('\\firebase-admin')
  ) {
    return fakeAdmin;
  }
  return originalLoad.call(this, request, parent, isMain);
};

const { runImport } = require('./trip_export_import');
Module._load = originalLoad;

function buildExportPayload() {
  return {
    formatVersion: 1,
    exportedAt: '2026-06-02T00:00:00.000Z',
    sourceProjectId: 'source-project',
    tripId: 'trip-a',
    trip: {
      path: 'trips/trip-a',
      data: { title: 'Voyage sauvegardé' },
      subcollections: {
        messages: {
          'message-a': {
            path: 'trips/trip-a/messages/message-a',
            data: { text: 'Bonjour' },
            subcollections: {},
          },
        },
      },
    },
    users: {
      userA: {
        path: 'users/userA',
        data: { displayName: 'Alice' },
      },
    },
  };
}

function writePayload(payload) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'planerz-trip-import-'));
  const filePath = path.join(dir, 'export.json');
  fs.writeFileSync(filePath, JSON.stringify(payload), 'utf8');
  return filePath;
}

function createFakeDb({ tripExists }) {
  const writes = [];
  const commits = [];
  const recursiveDeletes = [];

  const db = {
    collection(collectionPath) {
      return {
        doc(documentId) {
          return {
            path: `${collectionPath}/${documentId}`,
            async get() {
              return { exists: tripExists };
            },
          };
        },
      };
    },
    doc(documentPath) {
      return { path: documentPath };
    },
    batch() {
      const batchWrites = [];
      return {
        set(ref, data, options) {
          const write = { path: ref.path, data, options };
          batchWrites.push(write);
          writes.push(write);
        },
        async commit() {
          commits.push(batchWrites);
        },
      };
    },
    async recursiveDelete(ref) {
      recursiveDeletes.push(ref.path);
    },
  };

  return { db, writes, commits, recursiveDeletes };
}

async function withQuietConsole(callback) {
  const originalLog = console.log;
  try {
    console.log = () => {};
    return await callback();
  } finally {
    console.log = originalLog;
  }
}

test('import merges user documents and replaces an existing trip tree', async () => {
  const filePath = writePayload(buildExportPayload());
  const { db, writes, recursiveDeletes } = createFakeDb({ tripExists: true });

  await withQuietConsole(() =>
    runImport(db, {
      filePath,
      apply: true,
      dryRun: false,
      force: true,
    }),
  );

  assert.deepEqual(recursiveDeletes, ['trips/trip-a']);

  const userWrite = writes.find((write) => write.path === 'users/userA');
  assert.ok(userWrite);
  assert.deepEqual(userWrite.options, { merge: true });

  const tripWrite = writes.find((write) => write.path === 'trips/trip-a');
  assert.ok(tripWrite);
  assert.deepEqual(tripWrite.options, { merge: false });

  const messageWrite = writes.find(
    (write) => write.path === 'trips/trip-a/messages/message-a',
  );
  assert.ok(messageWrite);
  assert.deepEqual(messageWrite.options, { merge: false });
});

test('import does not delete a trip tree when the trip is new', async () => {
  const filePath = writePayload(buildExportPayload());
  const { db, recursiveDeletes } = createFakeDb({ tripExists: false });

  await withQuietConsole(() =>
    runImport(db, {
      filePath,
      apply: true,
      dryRun: false,
      force: true,
    }),
  );

  assert.deepEqual(recursiveDeletes, []);
});

test('import rejects payloads whose trip id and document path disagree', async () => {
  const payload = buildExportPayload();
  payload.trip.path = 'trips/other-trip';
  const filePath = writePayload(payload);
  const { db } = createFakeDb({ tripExists: false });

  await withQuietConsole(async () => {
    await assert.rejects(
      () =>
        runImport(db, {
          filePath,
          apply: true,
          dryRun: false,
          force: true,
        }),
      /Chemin de voyage incohérent/,
    );
  });
});
