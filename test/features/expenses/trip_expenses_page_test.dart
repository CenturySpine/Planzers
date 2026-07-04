import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/expenses/data/expense_group.dart';
import 'package:planerz/features/expenses/presentation/trip_expenses_page.dart';

TripExpenseGroup _group(String id) {
  return TripExpenseGroup(
    id: id,
    title: id,
    visibleToMemberIds: const ['member-1'],
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('resolveActiveExpenseGroupId', () {
    test('falls back to the first visible group when no group is active', () {
      final groups = [_group('locked'), _group('open')];

      expect(
        resolveActiveExpenseGroupId(
          visibleGroups: groups,
          preferredGroupId: null,
        ),
        'locked',
      );
    });

    test(
      'falls back to the first visible group when active group is stale',
      () {
        final groups = [_group('current'), _group('other')];

        expect(
          resolveActiveExpenseGroupId(
            visibleGroups: groups,
            preferredGroupId: 'deleted',
          ),
          'current',
        );
      },
    );

    test('keeps a valid active group', () {
      final groups = [_group('first'), _group('selected')];

      expect(
        resolveActiveExpenseGroupId(
          visibleGroups: groups,
          preferredGroupId: 'selected',
        ),
        'selected',
      );
    });
  });
}
