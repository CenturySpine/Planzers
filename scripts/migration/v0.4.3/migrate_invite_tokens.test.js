const test = require('node:test');
const assert = require('node:assert/strict');

const {
  TARGET_TOKEN_RE,
  sanitizeInviteCodeInput,
  formatInviteCodeToken,
  planTripInviteTokenMigration,
  planInviteTokenMigrations,
} = require('./migrate_invite_tokens');

test('sanitize strips separators and caps length', () => {
  assert.equal(sanitizeInviteCodeInput('abC-dEf'), 'ABCDEF');
  assert.equal(sanitizeInviteCodeInput('c36d32f1da6e39a4687df4688eda4199'), 'C36D32');
});

test('format builds token with middle hyphen', () => {
  assert.equal(formatInviteCodeToken('ABCDEF'), 'ABC-DEF');
  assert.equal(TARGET_TOKEN_RE.test('ABC-DEF'), true);
});

test('plan derives legacy hex token from first six alnum chars', () => {
  const used = new Map();
  const plan = planTripInviteTokenMigration(
    'c36d32f1da6e39a4687df4688eda4199',
    'trip-1',
    used,
    () => 0,
  );
  assert.deepEqual(plan, { newToken: 'C36-D32', reason: 'derived' });
});

test('plan normalizes lowercase hyphenated token', () => {
  const used = new Map();
  const plan = planTripInviteTokenMigration('abc-def', 'trip-1', used, () => 0);
  assert.deepEqual(plan, { newToken: 'ABC-DEF', reason: 'case-normalize' });
});

test('plan skips already migrated token', () => {
  const used = new Map([['ABC-DEF', 'trip-1']]);
  const plan = planTripInviteTokenMigration('ABC-DEF', 'trip-1', used, () => 0);
  assert.equal(plan, null);
});

test('planInviteTokenMigrations avoids collisions between trips', () => {
  let i = 0;
  const rng = (max) => i++ % max;
  const actions = planInviteTokenMigrations(
    [
      { id: 'trip-a', inviteToken: 'aaaaaa' },
      { id: 'trip-b', inviteToken: 'aaa-aaa' },
    ],
    rng,
  );
  assert.equal(actions.length, 2);
  assert.equal(actions[0].newToken, 'AAA-AAA');
  assert.notEqual(actions[1].newToken, 'AAA-AAA');
  assert.equal(actions[1].reason, 'collision-case-normalize');
});
