import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/expenses/presentation/expense_editor_pages.dart';

void main() {
  test('keeps stored expense billing units outside the current scope', () {
    final billingUnitIds = expenseDetailBillingUnitIds(
      participantScopeMemberIds: ['member-a', 'member-b'],
      paidBy: 'archived-group',
      participantIds: ['member-b', 'member-c', 'archived-group'],
    );

    expect(billingUnitIds, [
      'member-a',
      'member-b',
      'archived-group',
      'member-c',
    ]);
  });

  test('trims empty and duplicate billing unit ids', () {
    final billingUnitIds = expenseDetailBillingUnitIds(
      participantScopeMemberIds: [' member-a ', '', 'member-a'],
      paidBy: ' member-b ',
      participantIds: ['member-b', ' ', 'member-c'],
    );

    expect(billingUnitIds, ['member-a', 'member-b', 'member-c']);
  });
}
