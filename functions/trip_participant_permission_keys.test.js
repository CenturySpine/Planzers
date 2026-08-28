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

function exportBlock(exportName) {
  const start = source.indexOf(`exports.${exportName} =`);
  assert.notEqual(start, -1, `${exportName} export not found`);

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

function functionBlock(functionName) {
  const start = source.indexOf(`function ${functionName}(`);
  assert.notEqual(start, -1, `${functionName} function not found`);

  const nextFunction = source.indexOf('\nfunction ', start + 1);
  const nextExport = source.indexOf('\nexports.', start + 1);
  const candidates = [nextFunction, nextExport]
    .filter((index) => index !== -1)
    .sort((a, b) => a - b);
  return source.slice(start, candidates[0] ?? source.length);
}

test('participant add and remove callables use manageParticipants permission', () => {
  assert.equal(participantPermissionKey('addTripParticipant'), 'manageParticipants');
  assert.equal(participantPermissionKey('removeTripParticipant'), 'manageParticipants');
  assert.equal(participantPermissionKey('removeTripRegisteredMember'), 'manageParticipants');
});

test('server participant permission defaults use current keys only', () => {
  const defaultsBlock = functionBlock('defaultTripPermissions');
  const participantsMatch = defaultsBlock.match(/participants:\s*\{([\s\S]*?)\n    \}/);
  assert.ok(participantsMatch, 'participants defaults block not found');

  const participantsBlock = participantsMatch[1];
  assert.match(participantsBlock, /manageParticipants:\s*'owner'/);
  assert.match(participantsBlock, /toggleAdminRole:\s*'owner'/);
  assert.doesNotMatch(participantsBlock, /createParticipant/);
  assert.doesNotMatch(participantsBlock, /editPlaceholderParticipant/);
  assert.doesNotMatch(participantsBlock, /deletePlaceholderParticipant/);
  assert.doesNotMatch(participantsBlock, /deleteRegisteredParticipant/);
});

test('invite joining claims participant slots transactionally', () => {
  const joinBlock = functionBlock('completeJoinTripWithInvite');
  assert.match(joinBlock, /return db\.runTransaction/);
  assert.match(joinBlock, /tx\.update\(claimedParticipantRef/);
  assert.match(joinBlock, /tx\.set\(tripRef\.collection\('participants'\)\.doc\(\)/);
  assert.match(joinBlock, /tx\.update\(tripRef/);
  assert.doesNotMatch(joinBlock, /claimedParticipantRef\.update/);
  assert.doesNotMatch(joinBlock, /collection\('participants'\)\.add/);
});

test('calendar stay sync skips valid custom participant stays', () => {
  const syncBlock = exportBlock('syncParticipantStaysOnTripCalendarChange');
  assert.match(syncBlock, /shouldResetParticipantStayOnCalendarChange/);
  assert.match(syncBlock, /continue;/);

  const resetBlock = functionBlock('shouldResetParticipantStayOnCalendarChange');
  assert.match(resetBlock, /participantStayWithinTripBounds/);
  assert.match(resetBlock, /stayFieldsEqual\(currentStay, defaultStayForTrip\(beforeTrip\)\)/);
});
