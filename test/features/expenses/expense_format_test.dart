import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/expenses/presentation/expense_format.dart';

void main() {
  test('weightedExpenseShareDrafts follows billing-unit parts', () {
    final shares = weightedExpenseShareDrafts(
      amount: 100,
      participantIds: const ['group-a', 'member-b'],
      groupParts: const {'group-a': 2},
    );

    expect(shares, {'group-a': 66.67, 'member-b': 33.33});
  });

  test('weightedExpenseShareDrafts keeps rounded shares equal to total', () {
    final shares = weightedExpenseShareDrafts(
      amount: 100,
      participantIds: const [
        'member-a',
        'member-b',
        'member-c',
        'member-d',
        'member-e',
        'member-f',
        'member-g',
      ],
      groupParts: const {},
    );

    final roundedTotal = shares.values.fold<double>(
      0,
      (sum, share) => sum + share,
    );
    expect(roundedTotal, closeTo(100, 0.001));
    expect(shares.values.where((share) => share == 14.29).length, 4);
    expect(shares.values.where((share) => share == 14.28).length, 3);
  });
}
