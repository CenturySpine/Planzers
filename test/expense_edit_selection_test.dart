import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/expenses/presentation/expense_edit_selection.dart';

void main() {
  test(
    'initial participant ids preserve stored values outside current scope',
    () {
      expect(
        initialExpenseEditParticipantIds(
          storedParticipantIds: const [' group-a ', 'member-b'],
          fallbackScopeIds: const ['member-c'],
        ),
        {'group-a', 'member-b'},
      );
    },
  );

  test(
    'initial participant ids fall back to scope when stored values are empty',
    () {
      expect(
        initialExpenseEditParticipantIds(
          storedParticipantIds: const [' ', ''],
          fallbackScopeIds: const [' member-a ', 'member-b'],
        ),
        {'member-a', 'member-b'},
      );
    },
  );

  test('initial payer preserves stored value outside current scope', () {
    expect(
      initialExpenseEditPaidBy(
        storedPaidBy: ' group-a ',
        fallbackScopeIds: const ['member-a'],
      ),
      'group-a',
    );
  });

  test(
    'editable members include scope, stored participants, and payer once',
    () {
      expect(
        editableExpenseMemberIds(
          scopeIds: const ['member-a', 'member-b'],
          participantIds: const ['member-b', 'group-a'],
          paidBy: 'group-a',
        ),
        ['member-a', 'member-b', 'group-a'],
      );
    },
  );
}
