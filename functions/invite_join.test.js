const test = require('node:test');
const assert = require('node:assert/strict');
const {
  canonicalInviteToken,
  completeJoinTripWithInvite,
  inviteTokenLookupValues,
  inviteTokensMatch,
} = require('./invite_join');

function fakeTripRef({ tripData, participants }) {
  const writes = [];
  let nextParticipantId = 0;

  const participantCollection = {
    kind: 'participants',
    doc(id) {
      return {
        kind: 'participant',
        id: id ?? `new-${++nextParticipantId}`,
      };
    },
  };
  const tripRef = {
    kind: 'trip',
    firestore: {
      async runTransaction(callback) {
        return callback(transaction);
      },
    },
    collection(name) {
      assert.equal(name, 'participants');
      return participantCollection;
    },
  };
  const participantDocs = Object.entries(participants).map(([id, data]) => ({
    id,
    data: () => data,
    ref: participantCollection.doc(id),
  }));
  const transaction = {
    async get(ref) {
      if (ref.kind === 'trip') {
        return { exists: true, data: () => tripData };
      }
      if (ref.kind === 'participants') {
        return { docs: participantDocs };
      }
      throw new Error(`Unexpected ref kind: ${ref.kind}`);
    },
    update(ref, payload) {
      writes.push({ op: 'update', ref, payload });
    },
    set(ref, payload) {
      writes.push({ op: 'set', ref, payload });
    },
  };

  return { tripRef, writes };
}

test('invite token matching accepts legacy compact and lowercase tokens', () => {
  assert.equal(canonicalInviteToken('abcdef'), 'ABC-DEF');
  assert.equal(canonicalInviteToken('abc-def'), 'ABC-DEF');
  assert.equal(inviteTokensMatch('abcdef', 'ABC-DEF'), true);
  assert.equal(inviteTokensMatch('abc-def', 'ABCDEF'), true);
  assert.equal(inviteTokensMatch('ABC-DEF', 'ZZZ-999'), false);

  const lookupValues = inviteTokenLookupValues('ABC-DEF');
  assert.equal(lookupValues.includes('ABC-DEF'), true);
  assert.equal(lookupValues.includes('ABCDEF'), true);
  assert.equal(lookupValues.includes('abc-def'), true);
  assert.equal(lookupValues.includes('abcdef'), true);
});

test('completeJoinTripWithInvite claims a placeholder and updates membership together', async () => {
  const { tripRef, writes } = fakeTripRef({
    tripData: { inviteToken: 'abc123', memberUserIds: [] },
    participants: {
      slotA: { participantName: 'Alice' },
    },
  });

  await completeJoinTripWithInvite({
    tripRef,
    uid: 'uid-a',
    token: 'ABC-123',
    participantSlotId: 'slotA',
    bypassParticipantChoice: false,
    newParticipantName: '',
    useProfileNameForJoin: false,
    defaultStayForTrip: () => ({}),
  });

  assert.equal(writes.length, 2);
  assert.deepEqual(writes[0], {
    op: 'update',
    ref: { kind: 'participant', id: 'slotA' },
    payload: { userId: 'uid-a' },
  });
  assert.equal(writes[1].op, 'update');
  assert.equal(writes[1].ref.kind, 'trip');
  assert.ok(writes[1].payload.memberUserIds);
});

test('completeJoinTripWithInvite refuses a slot already claimed in the transaction snapshot', async () => {
  const { tripRef, writes } = fakeTripRef({
    tripData: { inviteToken: 'ABC-123', memberUserIds: [] },
    participants: {
      slotA: { participantName: 'Alice', userId: 'uid-other' },
    },
  });

  await assert.rejects(
    () => completeJoinTripWithInvite({
      tripRef,
      uid: 'uid-a',
      token: 'ABC-123',
      participantSlotId: 'slotA',
      bypassParticipantChoice: false,
      newParticipantName: '',
      useProfileNameForJoin: false,
      defaultStayForTrip: () => ({}),
    }),
    (error) => error.code === 'failed-precondition'
  );
  assert.deepEqual(writes, []);
});

test('completeJoinTripWithInvite creates a participant when slot choice is bypassed', async () => {
  const { tripRef, writes } = fakeTripRef({
    tripData: { inviteToken: 'ABC-123', memberUserIds: [] },
    participants: {
      slotA: { participantName: 'Alice' },
    },
  });

  await completeJoinTripWithInvite({
    tripRef,
    uid: 'uid-a',
    token: 'ABC-123',
    participantSlotId: '',
    bypassParticipantChoice: true,
    newParticipantName: 'Camille',
    useProfileNameForJoin: true,
    defaultStayForTrip: () => ({ stayStartDateKey: '2026-07-05' }),
  });

  assert.equal(writes.length, 2);
  assert.equal(writes[0].op, 'set');
  assert.equal(writes[0].ref.kind, 'participant');
  assert.equal(writes[0].payload.participantName, 'Camille');
  assert.equal(writes[0].payload.userId, 'uid-a');
  assert.equal(writes[0].payload.useProfileName, true);
  assert.equal(writes[0].payload.stayStartDateKey, '2026-07-05');
  assert.equal(writes[1].op, 'update');
  assert.equal(writes[1].ref.kind, 'trip');
});
