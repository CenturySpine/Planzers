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

test('invite join claims participant slot and membership in one transaction', () => {
  const start = source.indexOf('async function completeJoinTripWithInvite');
  assert.notEqual(start, -1, 'completeJoinTripWithInvite helper not found');
  const end = source.indexOf('\nexports.getInviteJoinContext', start);
  const block = source.slice(start, end);
  const transactionIndex = block.indexOf('await db.runTransaction');
  assert.notEqual(transactionIndex, -1, 'join helper must use a transaction');

  const transactionBlock = block.slice(transactionIndex);
  assert.match(transactionBlock, /tx\.update\(claimedParticipantRef,\s*\{\s*userId: uid\s*\}\)/);
  assert.match(transactionBlock, /tx\.update\(tripRef,\s*\{[\s\S]*memberUserIds: FieldValue\.arrayUnion\(uid\)/);
});
