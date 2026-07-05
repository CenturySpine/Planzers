'use strict';

const { FieldValue } = require('firebase-admin/firestore');
const { HttpsError } = require('firebase-functions/v2/https');

const PARTICIPANT_NAME_MIN_LEN = 2;
const PARTICIPANT_NAME_MAX_LEN = 50;
const INVITE_CODE_CHAR_COUNT = 6;
const INVITE_CODE_SEGMENT_SIZE = 3;

function normalizeString(value) {
  return (typeof value === 'string' ? value : '').trim();
}

function compactInviteToken(value) {
  return normalizeString(value).toUpperCase().replace(/[^A-Z0-9]/g, '');
}

function formatInviteToken(code) {
  if (code.length !== INVITE_CODE_CHAR_COUNT) return code;
  return `${code.slice(0, INVITE_CODE_SEGMENT_SIZE)}-${code.slice(INVITE_CODE_SEGMENT_SIZE)}`;
}

function canonicalInviteToken(value) {
  const raw = normalizeString(value);
  if (!raw) return '';
  const compact = compactInviteToken(raw);
  return compact.length === INVITE_CODE_CHAR_COUNT ? formatInviteToken(compact) : raw;
}

function inviteTokensMatch(expected, token) {
  const expectedCanonical = canonicalInviteToken(expected);
  return Boolean(expectedCanonical) && expectedCanonical === canonicalInviteToken(token);
}

function inviteTokenLookupValues(token) {
  const raw = normalizeString(token);
  if (!raw) return [];

  const values = new Set([raw, raw.toUpperCase(), raw.toLowerCase()]);
  const compact = compactInviteToken(raw);
  if (compact.length === INVITE_CODE_CHAR_COUNT) {
    const formatted = formatInviteToken(compact);
    values.add(compact);
    values.add(compact.toLowerCase());
    values.add(formatted);
    values.add(formatted.toLowerCase());
  }
  return [...values].filter(Boolean);
}

function assertTripInviteToken(data, token) {
  if (!inviteTokensMatch(data.inviteToken, token)) {
    throw new HttpsError(
      'permission-denied',
      'Lien d invitation invalide ou expire'
    );
  }
}

/** Required when joining without claiming a pre-planned participant slot. */
function assertParticipantNameForNewJoin(rawName) {
  const name = normalizeString(rawName);
  if (
    name.length < PARTICIPANT_NAME_MIN_LEN ||
    name.length > PARTICIPANT_NAME_MAX_LEN
  ) {
    throw new HttpsError(
      'invalid-argument',
      'Indique ton prénom ou pseudo pour rejoindre ce voyage (2 à 50 caractères).'
    );
  }
  return name;
}

/**
 * Adds [uid] to trip members if [token] matches the trip inviteToken.
 * The participant claim and trip membership update must stay in one Firestore
 * transaction so two concurrent joins cannot claim the same placeholder slot.
 */
async function completeJoinTripWithInvite({
  tripRef,
  uid,
  token,
  participantSlotId,
  bypassParticipantChoice,
  newParticipantName,
  useProfileNameForJoin,
  defaultStayForTrip,
}) {
  const slotArg = normalizeString(participantSlotId);
  const bypass = bypassParticipantChoice === true;
  const db = tripRef.firestore;

  await db.runTransaction(async (transaction) => {
    const tripSnap = await transaction.get(tripRef);
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const data = tripSnap.data() || {};
    assertTripInviteToken(data, token);

    const memberUserIds = Array.isArray(data.memberUserIds)
      ? data.memberUserIds.map((value) => String(value))
      : [];
    if (memberUserIds.includes(uid)) {
      return;
    }

    const participantsSnap = await transaction.get(tripRef.collection('participants'));
    const unclaimedSlots = participantsSnap.docs.filter((doc) => {
      const userId = normalizeString(doc.data().userId);
      const isChild = doc.data().isChild === true;
      return !userId && !isChild;
    });

    let claimedParticipantRef = null;

    if (unclaimedSlots.length > 0 && !bypass) {
      if (!slotArg) {
        throw new HttpsError(
          'invalid-argument',
          'Choisis un voyageur prévu sur la liste pour rejoindre ce voyage.'
        );
      }
      const slotDoc = participantsSnap.docs.find((doc) => doc.id === slotArg);
      if (!slotDoc || normalizeString(slotDoc.data().userId)) {
        throw new HttpsError(
          'failed-precondition',
          'Ce voyageur a déjà été choisi ou est introuvable.'
        );
      }
      if (slotDoc.data().isChild === true) {
        throw new HttpsError(
          'failed-precondition',
          'Ce voyageur prévu est un enfant et ne peut pas être associé à un compte.'
        );
      }
      claimedParticipantRef = slotDoc.ref;
    }

    if (claimedParticipantRef) {
      transaction.update(claimedParticipantRef, { userId: uid });
    } else {
      const participantName = assertParticipantNameForNewJoin(newParticipantName);
      const defaultStay = defaultStayForTrip(data);
      const newParticipantDoc = {
        participantName,
        userId: uid,
        ...defaultStay,
        cupidonEnabled: false,
        phoneVisibility: 'nobody',
        createdAt: FieldValue.serverTimestamp(),
      };
      if (useProfileNameForJoin === true) {
        newParticipantDoc.useProfileName = true;
      }
      transaction.set(tripRef.collection('participants').doc(), newParticipantDoc);
    }

    transaction.update(tripRef, {
      memberUserIds: FieldValue.arrayUnion(uid),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

module.exports = {
  assertParticipantNameForNewJoin,
  assertTripInviteToken,
  canonicalInviteToken,
  completeJoinTripWithInvite,
  inviteTokenLookupValues,
  inviteTokensMatch,
};
