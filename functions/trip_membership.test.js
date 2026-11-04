'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  tripDataHasMember,
  assertTripMemberOrApplicationOwner,
} = require('./trip_membership');

/** Minimal Firestore stand-in: `docs` maps `collection/id` to document data. */
function fakeDb(docs) {
  const reads = [];
  return {
    reads,
    collection: (name) => ({
      doc: (id) => ({
        get: async () => {
          const key = `${name}/${id}`;
          reads.push(key);
          const data = docs[key];
          return { exists: data !== undefined, data: () => data };
        },
      }),
    }),
  };
}

async function assertDenied(promise) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, 'permission-denied');
    return true;
  });
}

describe('tripDataHasMember', () => {
  it('accepts a uid listed in memberUserIds', () => {
    assert.equal(tripDataHasMember({ memberUserIds: ['alice', 'bob'] }, 'bob'), true);
  });

  it('rejects a uid that is not listed', () => {
    assert.equal(tripDataHasMember({ memberUserIds: ['alice'] }, 'mallory'), false);
  });

  it('rejects trips without a member list', () => {
    assert.equal(tripDataHasMember({}, 'alice'), false);
    assert.equal(tripDataHasMember({ memberUserIds: 'alice' }, 'alice'), false);
    assert.equal(tripDataHasMember(undefined, 'alice'), false);
  });

  it('rejects an empty uid even when the list holds empty entries', () => {
    assert.equal(tripDataHasMember({ memberUserIds: ['', null] }, ''), false);
    assert.equal(tripDataHasMember({ memberUserIds: [''] }, undefined), false);
  });
});

describe('assertTripMemberOrApplicationOwner', () => {
  it('lets a trip member through', async () => {
    const db = fakeDb({ 'trips/t1': { memberUserIds: ['alice'] }, 'users/alice': {} });
    const result = await assertTripMemberOrApplicationOwner({ db, tripId: 't1', uid: 'alice' });
    assert.deepEqual(result, { isApplicationOwner: false });
    assert.deepEqual(db.reads.sort(), ['trips/t1', 'users/alice']);
  });

  it('lets a trip member through when they have no profile document', async () => {
    const db = fakeDb({ 'trips/t1': { memberUserIds: ['alice'] } });
    const result = await assertTripMemberOrApplicationOwner({ db, tripId: 't1', uid: 'alice' });
    assert.deepEqual(result, { isApplicationOwner: false });
  });

  it('rejects a signed-in user who is not a member', async () => {
    const db = fakeDb({ 'trips/t1': { memberUserIds: ['alice'] }, 'users/mallory': {} });
    await assertDenied(assertTripMemberOrApplicationOwner({ db, tripId: 't1', uid: 'mallory' }));
  });

  it('rejects a missing trip the same way as a non-member', async () => {
    const db = fakeDb({ 'users/mallory': {} });
    await assertDenied(assertTripMemberOrApplicationOwner({ db, tripId: 'nope', uid: 'mallory' }));
  });

  it('does not treat a truthy non-boolean flag as application owner', async () => {
    const db = fakeDb({
      'trips/t1': { memberUserIds: ['alice'] },
      'users/mallory': { isApplicationOwner: 'true' },
    });
    await assertDenied(assertTripMemberOrApplicationOwner({ db, tripId: 't1', uid: 'mallory' }));
  });

  it('lets an application owner through on a trip they do not belong to', async () => {
    const db = fakeDb({
      'trips/t1': { memberUserIds: ['alice'] },
      'users/admin': { isApplicationOwner: true },
    });
    const result = await assertTripMemberOrApplicationOwner({ db, tripId: 't1', uid: 'admin' });
    assert.deepEqual(result, { isApplicationOwner: true });
  });

  it('reports application owners who are also members', async () => {
    const db = fakeDb({
      'trips/t1': { memberUserIds: ['admin'] },
      'users/admin': { isApplicationOwner: true },
    });
    const result = await assertTripMemberOrApplicationOwner({ db, tripId: 't1', uid: 'admin' });
    assert.deepEqual(result, { isApplicationOwner: true });
  });
});

describe('AI callables check trip membership first', () => {
  const source = fs.readFileSync(path.join(__dirname, 'index.js'), 'utf8');
  const recipeSource = fs.readFileSync(path.join(__dirname, 'recipe_ai.js'), 'utf8');

  function callableBlock(exportName) {
    const start = source.indexOf(`exports.${exportName} = onCall`);
    assert.notEqual(start, -1, `${exportName} callable not found`);
    const nextExport = source.indexOf('\nexports.', start + 1);
    return source.slice(start, nextExport === -1 ? source.length : nextExport);
  }

  function recipeCallableBlock() {
    const start = recipeSource.indexOf('const generateRecipeWithAi = onCall');
    assert.notEqual(start, -1, 'generateRecipeWithAi callable not found');
    const end = recipeSource.indexOf('\nmodule.exports', start);
    return recipeSource.slice(start, end === -1 ? recipeSource.length : end);
  }

  function assertGuardBefore(exportName, sensitiveCalls, block = callableBlock(exportName)) {
    const guard = block.indexOf('await assertTripMemberOrApplicationOwner(');
    assert.notEqual(guard, -1, `${exportName} does not check trip membership`);
    for (const call of sensitiveCalls) {
      const at = block.indexOf(call);
      assert.notEqual(at, -1, `${exportName} no longer calls ${call}`);
      assert.ok(guard < at, `${exportName} calls ${call} before checking trip membership`);
    }
  }

  it('consolidateTripShoppingWithAi checks before reading the trip and calling the AI', () => {
    assertGuardBefore('consolidateTripShoppingWithAi', [
      ".collection('shoppingItems')",
      ".collection('meals')",
      'withAiQuota(',
    ]);
  });

  it('generateRecipeWithAi checks before using the quota and calling the AI', () => {
    assertGuardBefore(
      'generateRecipeWithAi',
      ['withAiQuota(', 'callGemini('],
      recipeCallableBlock()
    );
  });

  it('reserveAiQuota checks before reserving', () => {
    assertGuardBefore('reserveAiQuota', ['reserveQuota(']);
  });

  it('refundAiQuota checks before refunding, outside the best-effort catch', () => {
    assertGuardBefore('refundAiQuota', ['refundQuota(']);
    assert.doesNotMatch(
      callableBlock('refundAiQuota'),
      /assertTripMemberOrApplicationOwner\([^)]*\)\s*\.catch/
    );
  });
});
