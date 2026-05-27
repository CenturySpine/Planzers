/// Firestore: `trips/{tripId}/expenseGroups/{groupId}/state/current`.
///
/// UI-only lock for a single expense post; does not change expense permissions.
const String kExpenseGroupStateDocId = 'current';

/// Per expense post state (lock).
class TripExpenseGroupState {
  const TripExpenseGroupState({
    required this.expensesLocked,
  });

  final bool expensesLocked;

  static const defaults = TripExpenseGroupState(
    expensesLocked: false,
  );

  factory TripExpenseGroupState.fromMap(Map<String, dynamic> map) {
    return TripExpenseGroupState(
      expensesLocked: _parseBool(map['expensesLocked']),
    );
  }
}

bool _parseBool(dynamic raw, {bool defaultValue = false}) {
  if (raw == null) return defaultValue;
  if (raw is bool) return raw;
  if (raw is String) {
    return raw.trim().toLowerCase() == 'true';
  }
  return defaultValue;
}
