import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/expenses/presentation/expense_editor_pages.dart';

void main() {
  group('defaultExpensePayerId', () {
    test('prefers the viewer billing unit when it belongs to the scope', () {
      final payerId = defaultExpensePayerId(
        participantScopeMemberIds: const ['sabine', 'family-group'],
        currentUserBillingUnitId: 'family-group',
        currentUserMemberId: 'alice',
      );

      expect(payerId, 'family-group');
    });

    test('falls back to the raw member id for ungrouped viewers', () {
      final payerId = defaultExpensePayerId(
        participantScopeMemberIds: const ['sabine', 'alice'],
        currentUserBillingUnitId: null,
        currentUserMemberId: 'alice',
      );

      expect(payerId, 'alice');
    });
  });
}
