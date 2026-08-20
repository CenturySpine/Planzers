const test = require('node:test');
const assert = require('node:assert/strict');
const {
  assertSafeProviderUrl,
  isPrivateIpv4,
  secretIdFor,
  PROVIDER_ID_PATTERN,
} = require('./external_providers')._internal;

test('assertSafeProviderUrl accepts a well-formed https URL', () => {
  const url = assertSafeProviderUrl('https://ridgegear.example.com/oauth/authorize', 'URL');
  assert.equal(url.hostname, 'ridgegear.example.com');
});

test('assertSafeProviderUrl rejects http (not https)', () => {
  assert.throws(() => assertSafeProviderUrl('http://ridgegear.example.com/oauth/authorize', 'URL'));
});

test('assertSafeProviderUrl rejects malformed URLs', () => {
  assert.throws(() => assertSafeProviderUrl('not-a-url', 'URL'));
});

test('assertSafeProviderUrl rejects localhost', () => {
  assert.throws(() => assertSafeProviderUrl('https://localhost/oauth/authorize', 'URL'));
});

test('assertSafeProviderUrl rejects the cloud metadata server', () => {
  assert.throws(() => assertSafeProviderUrl('https://169.254.169.254/latest/meta-data', 'URL'));
});

test('isPrivateIpv4 flags RFC1918 ranges', () => {
  assert.equal(isPrivateIpv4('10.0.0.5'), true);
  assert.equal(isPrivateIpv4('172.16.0.1'), true);
  assert.equal(isPrivateIpv4('192.168.1.1'), true);
  assert.equal(isPrivateIpv4('127.0.0.1'), true);
});

test('isPrivateIpv4 does not flag a public IP or a hostname', () => {
  assert.equal(isPrivateIpv4('8.8.8.8'), false);
  assert.equal(isPrivateIpv4('ridgegear.example.com'), false);
});

test('secretIdFor derives a stable, provider-specific Secret Manager id', () => {
  assert.equal(secretIdFor('ridgegear'), 'extprov-ridgegear-client-secret');
});

test('PROVIDER_ID_PATTERN accepts lowercase-with-hyphens ids', () => {
  assert.ok(PROVIDER_ID_PATTERN.test('ridgegear'));
  assert.ok(PROVIDER_ID_PATTERN.test('planerz-selftest'));
});

test('PROVIDER_ID_PATTERN rejects uppercase, spaces, or a single char', () => {
  assert.ok(!PROVIDER_ID_PATTERN.test('Ridgegear'));
  assert.ok(!PROVIDER_ID_PATTERN.test('ridge gear'));
  assert.ok(!PROVIDER_ID_PATTERN.test('r'));
});
