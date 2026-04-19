import 'package:flutter_test/flutter_test.dart';
import 'package:planzers/features/expenses/data/expense.dart';
import 'package:planzers/features/expenses/domain/expense_settlement.dart';

TripExpense _e({
  required String paidBy,
  required List<String> participants,
  required double amount,
  String currency = 'EUR',
  String groupId = 'g1',
  String id = 'x',
  ExpenseSplitMode splitMode = ExpenseSplitMode.equal,
  Map<String, double>? participantShares,
}) {
  return TripExpense(
    id: id,
    groupId: groupId,
    title: 't',
    amount: amount,
    currency: currency,
    paidBy: paidBy,
    participantIds: participants,
    category: 'other',
    createdAt: DateTime(2026, 1, 1),
    expenseDate: DateTime(2026, 1, 1),
    splitMode: splitMode,
    participantShares: participantShares,
  );
}

void main() {
  test('equal split: payer is credited net (n-1) shares', () {
    final expenses = [
      _e(paidBy: 'a', participants: ['a', 'b', 'c'], amount: 90),
    ];
    final bal = computeBalances(expenses)['EUR']!;
    expect(bal['a'], closeTo(60, 0.01));
    expect(bal['b'], closeTo(-30, 0.01));
    expect(bal['c'], closeTo(-30, 0.01));
  });

  test('suggestTransfers settles two-person debt in one payment', () {
    final expenses = [
      _e(paidBy: 'a', participants: ['a', 'b'], amount: 100),
    ];
    final transfers = suggestTransfers(computeBalances(expenses));
    expect(transfers, hasLength(1));
    expect(transfers.single.fromUserId, 'b');
    expect(transfers.single.toUserId, 'a');
    expect(transfers.single.amount, closeTo(50, 0.01));
    expect(transfers.single.currency, 'EUR');
  });

  test('currencies are isolated', () {
    final expenses = [
      _e(
        paidBy: 'a',
        participants: ['a', 'b'],
        amount: 100,
        currency: 'EUR',
      ),
      _e(
        paidBy: 'b',
        participants: ['a', 'b'],
        amount: 20,
        currency: 'USD',
      ),
    ];
    final bal = computeBalances(expenses);
    expect(bal['EUR']!['a'], closeTo(50, 0.01));
    expect(bal['USD']!['b'], closeTo(10, 0.01));
  });

  test('computeViewerSettlement keeps only transfers involving the viewer', () {
    final expenses = [
      _e(paidBy: 'a', participants: ['a', 'b', 'c'], amount: 90),
    ];
    final settlement = computeViewerSettlement(expenses, 'b');
    expect(settlement.suggestedTransfers, hasLength(1));
    expect(
      settlement.suggestedTransfers.single.fromUserId == 'b' ||
          settlement.suggestedTransfers.single.toUserId == 'b',
      isTrue,
    );
  });

  test('computeViewerSettlement with no viewer id keeps all transfers', () {
    final expenses = [
      _e(paidBy: 'a', participants: ['a', 'b'], amount: 100),
    ];
    final settlement = computeViewerSettlement(expenses, null);
    expect(settlement.suggestedTransfers, hasLength(1));
    expect(settlement.suggestedTransfers.single.fromUserId, 'b');
  });

  test(
    'settled transfers are applied to balances and removed from suggestions',
    () {
      final expenses = [
        _e(paidBy: 'a', participants: ['a', 'b'], amount: 100),
      ];
      final settlement = computeViewerSettlement(
        expenses,
        null,
        settledTransfers: const [
          SuggestedTransfer(
            fromUserId: 'b',
            toUserId: 'a',
            amount: 50,
            currency: 'EUR',
          ),
        ],
      );

      final balances = settlement.balancesByCurrency['EUR']!;
      expect(balances['a'], closeTo(0, 0.01));
      expect(balances['b'], closeTo(0, 0.01));
      expect(settlement.suggestedTransfers, isEmpty);
    },
  );

  test('partial settled transfer reduces remaining suggestion amount', () {
    final expenses = [
      _e(paidBy: 'a', participants: ['a', 'b'], amount: 100),
    ];
    final settlement = computeViewerSettlement(
      expenses,
      null,
      settledTransfers: const [
        SuggestedTransfer(
          fromUserId: 'b',
          toUserId: 'a',
          amount: 20,
          currency: 'EUR',
        ),
      ],
    );
    expect(settlement.suggestedTransfers, hasLength(1));
    expect(settlement.suggestedTransfers.single.fromUserId, 'b');
    expect(settlement.suggestedTransfers.single.toUserId, 'a');
    expect(settlement.suggestedTransfers.single.amount, closeTo(30, 0.01));
  });

  test('custom split: balances follow participantShares', () {
    final expenses = [
      _e(
        paidBy: 'a',
        participants: ['a', 'b'],
        amount: 100,
        splitMode: ExpenseSplitMode.customAmounts,
        participantShares: {'a': 30, 'b': 70},
      ),
    ];
    final bal = computeBalances(expenses)['EUR']!;
    expect(bal['a'], closeTo(70, 0.01));
    expect(bal['b'], closeTo(-70, 0.01));
  });

  test('per-post scope: two groups do not merge balances', () {
    final g1 = [
      _e(id: '1', groupId: 'A', paidBy: 'a', participants: ['a', 'b'], amount: 100),
    ];
    final g2 = [
      _e(id: '2', groupId: 'B', paidBy: 'b', participants: ['a', 'b'], amount: 100),
    ];
    final bal1 = computeBalances(g1)['EUR']!;
    final bal2 = computeBalances(g2)['EUR']!;
    expect(bal1['a'], closeTo(50, 0.01));
    expect(bal1['b'], closeTo(-50, 0.01));
    expect(bal2['a'], closeTo(-50, 0.01));
    expect(bal2['b'], closeTo(50, 0.01));
  });
}
