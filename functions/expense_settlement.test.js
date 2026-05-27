const test = require('node:test');
const assert = require('node:assert/strict');
const {
  tripExpenseFromDoc,
  computeBalances,
  suggestTransfers,
  computeGroupSummary,
  amountsMatch,
  resolveUnit,
  normalizeNetForFirestore,
  normalizeNetsMapForFirestore,
  balancesForClientFirestore,
  balancesForSuggestions,
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

test('resolveUnit returns 1 for unknown id and group.parts for group ids', () => {
  const groupsMap = { 'ab': { parts: 2 }, 'family': { parts: 2.5 } };
  assert.equal(resolveUnit('pierre', groupsMap), 1);
  assert.equal(resolveUnit('ab', groupsMap), 2);
  assert.equal(resolveUnit('family', groupsMap), 2.5);
});

// Reference scenario from the plan:
// Pierre, Sabine; group A&B (parts=2, Alice+Bob).
// T0: Sabine pays 100 €, concerned: Pierre, Sabine, A&B (4 parts → 25 € each)
//     → Pierre: -25, Sabine: +75, A&B: -50
// T1: A&B pays 100 €, concerned: Pierre, Sabine, A&B
//     → Pierre: -25, Sabine: -25, A&B: +50
// nets: Pierre: -50, Sabine: +50, A&B: 0 → suggestion: Pierre → Sabine, 50 €
test('computeBalances and suggestTransfers with participant group (Pierre/Sabine/A&B)', () => {
  const groupsMap = { 'ab': { parts: 2 } };
  const expenses = [
    tripExpenseFromDoc(
      fakeDoc('t0', {
        groupId: 'g1',
        operationType: 'expense',
        amount: 100,
        currency: 'EUR',
        paidBy: 'sabine',
        participantIds: ['pierre', 'sabine', 'ab'],
        splitMode: 'equal',
      })
    ),
    tripExpenseFromDoc(
      fakeDoc('t1', {
        groupId: 'g1',
        operationType: 'expense',
        amount: 100,
        currency: 'EUR',
        paidBy: 'ab',
        participantIds: ['pierre', 'sabine', 'ab'],
        splitMode: 'equal',
      })
    ),
  ];

  const balances = computeBalances(expenses, groupsMap);
  assert.ok(amountsMatch(balances.EUR.pierre, -50), `pierre=${balances.EUR.pierre}`);
  assert.ok(amountsMatch(balances.EUR.sabine, 50), `sabine=${balances.EUR.sabine}`);
  // A&B nets to 0, may be omitted or 0
  const abBalance = balances.EUR.ab ?? 0;
  assert.ok(amountsMatch(abBalance, 0), `ab=${abBalance}`);

  const suggestions = suggestTransfers(balances);
  assert.equal(suggestions.length, 1);
  assert.equal(suggestions[0].fromParticipantId, 'pierre');
  assert.equal(suggestions[0].toParticipantId, 'sabine');
  assert.ok(amountsMatch(suggestions[0].amount, 50));
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

test('normalizeNetForFirestore keeps equilibrium as explicit zero', () => {
  assert.equal(normalizeNetForFirestore(0), 0);
  assert.equal(normalizeNetForFirestore(0.008), 0);
  assert.equal(normalizeNetForFirestore(-0.49), 0);
  assert.equal(normalizeNetForFirestore(0.49), 0);
  assert.equal(normalizeNetForFirestore(0.5), 0.5);
  assert.equal(normalizeNetForFirestore(-0.5), -0.5);
});

test('normalizeNetsMapForFirestore keeps all participant keys', () => {
  const out = normalizeNetsMapForFirestore({
    alice: 12.34,
    bob: -0.02,
    carol: 0,
  });
  assert.deepEqual(out, {
    alice: 12.34,
    bob: 0,
    carol: 0,
  });
});

test('balancesForClientFirestore and balancesForSuggestions diverge below threshold', () => {
  const balances = {
    EUR: { alice: 20, bob: -0.3, carol: 0 },
  };
  assert.deepEqual(balancesForClientFirestore(balances), {
    EUR: { alice: 20, bob: 0, carol: 0 },
  });
  assert.deepEqual(balancesForSuggestions(balances), {
    EUR: { alice: 20 },
  });
  assert.equal(suggestTransfers(balancesForSuggestions(balances)).length, 0);
});
