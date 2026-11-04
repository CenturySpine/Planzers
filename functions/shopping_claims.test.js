'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { shoppingHolderIds, isShoppingItemHeldBy } = require('./shopping_claims');

describe('shoppingHolderIds', () => {
  it('uses the participant id and the account when there is one', () => {
    assert.deepEqual([...shoppingHolderIds({ participantId: ' p1 ', userId: 'u1' })], ['p1', 'u1']);
  });

  it('uses the participant id alone without an account', () => {
    assert.deepEqual([...shoppingHolderIds({ participantId: 'p1', userId: '' })], ['p1']);
    assert.deepEqual([...shoppingHolderIds({ participantId: 'p1' })], ['p1']);
  });
});

describe('isShoppingItemHeldBy', () => {
  const holders = shoppingHolderIds({ participantId: 'p1', userId: 'u1' });

  it('matches items held by the participant id or the account', () => {
    assert.equal(isShoppingItemHeldBy({ claimedBy: 'p1' }, holders), true);
    assert.equal(isShoppingItemHeldBy({ claimedBy: ' u1 ' }, holders), true);
  });

  it('leaves items held by others or by nobody', () => {
    assert.equal(isShoppingItemHeldBy({ claimedBy: 'u2' }, holders), false);
    assert.equal(isShoppingItemHeldBy({}, holders), false);
    assert.equal(isShoppingItemHeldBy({ claimedBy: '' }, holders), false);
    assert.equal(isShoppingItemHeldBy(undefined, holders), false);
    // The consolidated list metadata document holds nothing.
    assert.equal(isShoppingItemHeldBy({ categories: [] }, holders), false);
  });
});
