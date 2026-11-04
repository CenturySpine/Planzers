'use strict';

/**
 * Shopping items held by a trip participant, to free them when the
 * participant leaves or is removed from the trip.
 *
 * An item (manual or consolidated list) is held in `claimedBy` by:
 *   - the user id of a participant with an account (taken with the hand
 *     icon, or assigned by an admin);
 *   - the participant id of a participant without an account (assigned by
 *     an admin), which they keep if they later join with an account.
 */

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

/** Ids under which a participant may hold shopping items. */
function shoppingHolderIds({ participantId, userId }) {
  return new Set([normalizeString(participantId), normalizeString(userId)].filter(Boolean));
}

/** True when the item document data is held by one of [holderIds]. */
function isShoppingItemHeldBy(itemData, holderIds) {
  const claimedBy = normalizeString(itemData && itemData.claimedBy);
  return claimedBy !== '' && holderIds.has(claimedBy);
}

module.exports = {
  shoppingHolderIds,
  isShoppingItemHeldBy,
};
