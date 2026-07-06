import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/expenses/data/expenses_repository.dart';

void main() {
  group('validatedExpenseCustomShares', () {
    test('keeps shares when they match the expense amount', () {
      final shares = validatedExpenseCustomShares(
        participantIds: const ['alice', 'bob'],
        participantShares: const {'alice': 35, 'bob': 15},
        amount: 50,
      );

      expect(shares, const {'alice': 35, 'bob': 15});
    });

    test('rejects negative shares', () {
      expect(
        () => validatedExpenseCustomShares(
          participantIds: const ['alice', 'bob'],
          participantShares: const {'alice': 55, 'bob': -5},
          amount: 50,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects shares that do not add up to the expense amount', () {
      expect(
        () => validatedExpenseCustomShares(
          participantIds: const ['alice', 'bob'],
          participantShares: const {'alice': 20, 'bob': 20},
          amount: 50,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
