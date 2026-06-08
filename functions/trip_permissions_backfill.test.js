const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, 'index.js'), 'utf8');

function sourceFunction(functionName) {
  const start = source.indexOf(`function ${functionName}(`);
  assert.notEqual(start, -1, `${functionName} not found`);

  const openingBrace = source.indexOf('{', start);
  assert.notEqual(openingBrace, -1, `${functionName} opening brace not found`);

  let depth = 0;
  for (let index = openingBrace; index < source.length; index += 1) {
    const char = source[index];
    if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        return source.slice(start, index + 1);
      }
    }
  }
  assert.fail(`${functionName} closing brace not found`);
}

function loadPermissionHelpers() {
  const sandbox = {};
  vm.runInNewContext(
    [
      sourceFunction('normalizeString'),
      sourceFunction('defaultTripPermissions'),
      sourceFunction('mergedTripPermissionsWithDefaults'),
      'helpers = { defaultTripPermissions, mergedTripPermissionsWithDefaults };',
    ].join('\n'),
    sandbox
  );
  return sandbox.helpers;
}

test('default trip permissions include participant management permission', () => {
  const { defaultTripPermissions } = loadPermissionHelpers();
  assert.equal(
    defaultTripPermissions().participants.manageParticipants,
    'owner'
  );
});

test('legacy permission backfill preserves configured participant management', () => {
  const { mergedTripPermissionsWithDefaults } = loadPermissionHelpers();

  const merged = mergedTripPermissionsWithDefaults({
    participants: {
      manageParticipants: 'admin',
    },
    expenses: {
      createExpense: 'admin',
    },
  });

  assert.equal(merged.participants.manageParticipants, 'admin');
  assert.equal(merged.participants.createParticipant, 'owner');
  assert.equal(merged.expenses.createExpense, 'admin');
  assert.equal(merged.meals.createMeal, 'admin');
});

test('legacy permission backfill preserves future configured keys', () => {
  const { mergedTripPermissionsWithDefaults } = loadPermissionHelpers();

  const merged = mergedTripPermissionsWithDefaults({
    participants: {
      manageParticipants: 'admin',
      futureParticipantAction: 'participant',
    },
    futureSection: {
      futureAction: 'admin',
    },
  });

  assert.equal(merged.participants.futureParticipantAction, 'participant');
  assert.equal(merged.futureSection.futureAction, 'admin');
});
