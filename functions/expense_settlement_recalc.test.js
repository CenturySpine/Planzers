const test = require('node:test');
const assert = require('node:assert/strict');
const {
  expenseLineMinRole,
  normalizeExpensePayload,
  tripCallerRoleRank,
  roleRank,
} = require('./expense_settlement_recalc');

test('tripCallerRoleRank treats co-admins via adminMemberIds', () => {
  const tripData = {
    ownerId: 'owner-uid',
    adminMemberIds: ['co-admin-uid'],
    memberUserIds: ['owner-uid', 'co-admin-uid', 'member-uid'],
  };

  assert.equal(tripCallerRoleRank(tripData, 'owner-uid'), roleRank('owner'));
  assert.equal(tripCallerRoleRank(tripData, 'co-admin-uid'), roleRank('admin'));
  assert.equal(tripCallerRoleRank(tripData, 'member-uid'), 0);
  assert.ok(
    tripCallerRoleRank(tripData, 'co-admin-uid') >= roleRank('admin'),
    'co-admin can pass refreshExpenseGroupSettlement role gate'
  );
});

test('tripCallerRoleRank does not use legacy adminUserIds field', () => {
  const tripData = {
    ownerId: 'owner-uid',
    adminUserIds: ['co-admin-uid'],
    adminMemberIds: [],
    memberUserIds: ['owner-uid', 'co-admin-uid'],
  };

  assert.equal(tripCallerRoleRank(tripData, 'co-admin-uid'), 0);
});

test('expenseLineMinRole reads expense line permissions with participant fallback', () => {
  assert.equal(expenseLineMinRole({}, 'editExpense'), roleRank('participant'));
  assert.equal(
    expenseLineMinRole(
      { permissions: { expenses: { editExpense: 'admin' } } },
      'editExpense'
    ),
    roleRank('admin')
  );
});

test('normalizeExpensePayload validates custom shares against amount', () => {
  assert.throws(
    () =>
      normalizeExpensePayload({
        groupId: 'group-a',
        title: 'Courses',
        amount: 12,
        currency: 'EUR',
        paidBy: 'member-a',
        participantIds: ['member-a', 'member-b'],
        expenseDate: '2026-07-07',
        splitMode: 'custom',
        participantShares: {
          'member-a': 4,
          'member-b': 4,
        },
      }),
    /Somme des parts invalide/
  );

  const payload = normalizeExpensePayload({
    groupId: 'group-a',
    title: 'Courses',
    amount: 12,
    currency: 'EUR',
    paidBy: 'member-a',
    participantIds: ['member-a', 'member-b'],
    expenseDate: '2026-07-07',
    splitMode: 'custom',
    participantShares: {
      'member-a': 4,
      'member-b': 8,
    },
  });

  assert.equal(payload.operationType, 'expense');
  assert.deepEqual(payload.participantShares, {
    'member-a': 4,
    'member-b': 8,
  });
});
