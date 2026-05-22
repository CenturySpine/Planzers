const test = require('node:test');
const assert = require('node:assert/strict');
const { tripCallerRoleRank, roleRank } = require('./expense_settlement_recalc');

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
