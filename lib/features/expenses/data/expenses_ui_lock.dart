/// Firestore: `trips/{tripId}/expenses_ui_locks/{docId}`.
///
/// UI-only enforcement in the app; does not change expense permissions.
const String kTripExpensesUiLockDocId = 'default';

/// Lock flag for trip expense editing controls (FAB, post/expense actions).
class TripExpensesUiLock {
  const TripExpensesUiLock({
    required this.expensesLocked,
  });

  final bool expensesLocked;

  static const defaults = TripExpensesUiLock(expensesLocked: false);

  factory TripExpensesUiLock.fromMap(Map<String, dynamic> map) {
    return TripExpensesUiLock(
      expensesLocked: _parseBool(map['expensesLocked']),
    );
  }
}

bool _parseBool(dynamic raw) {
  if (raw is bool) return raw;
  if (raw is String) {
    return raw.trim().toLowerCase() == 'true';
  }
  return false;
}
