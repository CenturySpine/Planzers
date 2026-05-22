const test = require('node:test');
const assert = require('node:assert/strict');
const {
  tripExpenseFromDoc,
  computeBalances,
  suggestTransfers,
  computeGroupSummary,
  amountsMatch,
} = require('./expense_settlement');

function fakeDoc(id, data) {
  return {
    id,
    data: () => data,
  };
}

test('computeBalances and suggestTransfers with settlement expense', () => {
  const expenses = [
    tripExpenseFromDoc(
      fakeDoc('e1', {
        groupId: 'g1',
        operationType: 'expense',
        amount: 100,
        currency: 'EUR',
        paidBy: 'alice',
        participantIds: ['alice', 'bob'],
        splitMode: 'equal',
      })
    ),
    tripExpenseFromDoc(
      fakeDoc('s1', {
        groupId: 'g1',
        operationType: 'settlement',
        amount: 50,
        currency: 'EUR',
        paidBy: 'bob',
        participantIds: ['alice'],
        splitMode: 'equal',
      })
    ),
  ];

  const balances = computeBalances(expenses);
  assert.ok(amountsMatch(balances.EUR.alice, 0));
  assert.ok(amountsMatch(balances.EUR.bob, 0));

  const suggestions = suggestTransfers(balances);
  assert.equal(suggestions.length, 0);
});

test('suggestTransfers proposes reimbursement when balances remain', () => {
  const expenses = [
    tripExpenseFromDoc(
      fakeDoc('e1', {
        groupId: 'g1',
        operationType: 'expense',
        amount: 40,
        currency: 'EUR',
        paidBy: 'alice',
        participantIds: ['alice', 'bob'],
        splitMode: 'equal',
      })
    ),
  ];

  const balances = computeBalances(expenses);
  const suggestions = suggestTransfers(balances);
  assert.equal(suggestions.length, 1);
  assert.equal(suggestions[0].fromParticipantId, 'bob');
  assert.equal(suggestions[0].toParticipantId, 'alice');
  assert.ok(amountsMatch(suggestions[0].amount, 20));
  assert.equal(suggestions[0].currency, 'EUR');
});

test('computeGroupSummary ignores settlements', () => {
  const expenses = [
    tripExpenseFromDoc(
      fakeDoc('e1', {
        groupId: 'g1',
        operationType: 'expense',
        amount: 30,
        currency: 'EUR',
        paidBy: 'alice',
        participantIds: ['alice'],
      })
    ),
    tripExpenseFromDoc(
      fakeDoc('s1', {
        groupId: 'g1',
        operationType: 'settlement',
        amount: 30,
        currency: 'EUR',
        paidBy: 'bob',
        participantIds: ['alice'],
      })
    ),
  ];

  const summary = computeGroupSummary(expenses);
  assert.ok(amountsMatch(summary.postTotalsByCurrency.EUR, 30));
  assert.ok(amountsMatch(summary.paidByTotalsByCurrency.alice.EUR, 30));
  assert.equal(summary.paidByTotalsByCurrency.bob, undefined);
});
