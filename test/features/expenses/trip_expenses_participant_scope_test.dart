import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/expenses/data/expense_group.dart';
import 'package:planerz/features/expenses/presentation/trip_expenses_page.dart';
import 'package:planerz/features/trips/data/participant_group.dart';
import 'package:planerz/features/trips/data/trip_member.dart';

TripMember _member(String id) => TripMember(id: id, participantName: id);

TripExpenseGroup _expensePost(List<String> visibleToMemberIds) =>
    TripExpenseGroup(
      id: 'post',
      title: 'Post',
      visibleToMemberIds: visibleToMemberIds,
      createdAt: DateTime.utc(2026),
    );

void main() {
  group('participantScopeUnitIdsForGroup', () {
    test('keeps a partially visible participant group chargeable', () {
      final scope = participantScopeUnitIdsForGroup(
        _expensePost(['alice']),
        [_member('alice'), _member('bob')],
        const [
          ParticipantGroup(
            id: 'family',
            label: 'Family',
            memberIds: ['alice', 'bob'],
            parts: 2,
          ),
        ],
      );

      expect(scope, ['family']);
    });

    test('combines fully visible groups and ungrouped members', () {
      final scope = participantScopeUnitIdsForGroup(
        _expensePost(['alice', 'bob', 'charlie']),
        [_member('alice'), _member('bob'), _member('charlie')],
        const [
          ParticipantGroup(
            id: 'family',
            label: 'Family',
            memberIds: ['alice', 'bob'],
            parts: 2,
          ),
        ],
      );

      expect(scope, ['charlie', 'family']);
    });
  });
}
