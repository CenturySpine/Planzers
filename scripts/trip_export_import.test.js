const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const {
  partitionUserWritesByExistence,
  runImport,
} = require('./trip_export_import');

function fakeDb({ existingPaths = [], tripExists = false } = {}) {
  const existing = new Set(existingPaths);
  return {
    doc: (docPath) => ({ path: docPath }),
    getAll: async (...refs) => refs.map((ref) => ({ exists: existing.has(ref.path) })),
    collection: (collectionName) => ({
      doc: (docId) => ({
        get: async () => ({
          exists: collectionName === 'trips' && tripExists,
          id: docId,
        }),
      }),
    }),
    batch: () => ({
      set: () => {},
      commit: async () => {},
    }),
  };
}

function writeExportPayload(payload) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'trip-export-import-'));
  const filePath = path.join(dir, 'export.json');
  fs.writeFileSync(filePath, JSON.stringify(payload), 'utf8');
  return filePath;
}

test('partitionUserWritesByExistence keeps existing destination profiles out of writes', async () => {
  const userWrites = [
    { path: 'users/existing', data: { displayName: 'Old export' } },
    { path: 'users/missing', data: { displayName: 'New user' } },
  ];

  const plan = await partitionUserWritesByExistence(
    fakeDb({ existingPaths: ['users/existing'] }),
    userWrites
  );

  assert.deepEqual(plan.existingWrites, [userWrites[0]]);
  assert.deepEqual(plan.missingWrites, [userWrites[1]]);
});

test('runImport refuses apply when the destination trip already exists', async () => {
  const filePath = writeExportPayload({
    formatVersion: 1,
    exportedAt: '2026-06-04T00:00:00.000Z',
    sourceProjectId: 'source',
    tripId: 'trip-1',
    trip: {
      path: 'trips/trip-1',
      data: { title: 'Voyage' },
      subcollections: {},
    },
    users: {},
  });

  await assert.rejects(
    () => runImport(fakeDb({ tripExists: true }), {
      filePath,
      apply: true,
      dryRun: false,
    }),
    /Import refusé : trips\/trip-1 existe déjà/
  );
});
