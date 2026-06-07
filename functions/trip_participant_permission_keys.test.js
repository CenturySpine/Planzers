const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, 'index.js'), 'utf8');

function callableBlock(exportName) {
  const start = source.indexOf(`exports.${exportName} = onCall`);
  assert.notEqual(start, -1, `${exportName} callable not found`);

  const nextExport = source.indexOf('\nexports.', start + 1);
  return source.slice(start, nextExport === -1 ? source.length : nextExport);
}

function participantPermissionKey(exportName) {
  const block = callableBlock(exportName);
  const match = block.match(
    /assertTripParticipantPermission\(\{[\s\S]*?permissionKey:\s*'([^']+)'/
  );
  assert.ok(match, `${exportName} participant permission check not found`);
  return match[1];
}

test('participant add and remove callables use manageParticipants permission', () => {
  assert.equal(participantPermissionKey('addTripParticipant'), 'manageParticipants');
  assert.equal(participantPermissionKey('removeTripParticipant'), 'manageParticipants');
  assert.equal(participantPermissionKey('removeTripRegisteredMember'), 'manageParticipants');
});
