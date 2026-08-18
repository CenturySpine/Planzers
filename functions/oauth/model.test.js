const test = require('node:test');
const assert = require('node:assert/strict');
const { hashSecret, generateSecret, verifyScope } = require('./model');

test('hashSecret is deterministic and hex-encoded', () => {
  const a = hashSecret('same-secret');
  const b = hashSecret('same-secret');
  assert.equal(a, b);
  assert.match(a, /^[0-9a-f]{64}$/);
});

test('hashSecret differs for different secrets', () => {
  assert.notEqual(hashSecret('secret-a'), hashSecret('secret-b'));
});

test('generateSecret returns unique, non-empty values', () => {
  const a = generateSecret();
  const b = generateSecret();
  assert.notEqual(a, b);
  assert.ok(a.length > 0);
});

test('verifyScope: granted scope covers requested scope', () => {
  assert.equal(verifyScope({ scope: 'trips.read' }, 'trips.read'), true);
});

test('verifyScope: requested scope missing from granted scope', () => {
  assert.equal(verifyScope({ scope: 'trips.read' }, 'trips.write'), false);
});

test('verifyScope: empty requested scope is always satisfied', () => {
  assert.equal(verifyScope({ scope: 'trips.read' }, ''), true);
});

test('verifyScope: multiple granted scopes, subset requested', () => {
  assert.equal(
    verifyScope({ scope: 'trips.read profile.read' }, 'trips.read'),
    true
  );
});
