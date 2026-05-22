/// Firestore: `trips/{tripId}/expenses_states/{docId}`.
///
/// UI-only enforcement in the app; does not change expense permissions.
const String kTripExpensesStatesDocId = 'default';

/// Trip expense section state (lock + notification channel).
class TripExpensesStates {
  const TripExpensesStates({
    required this.expensesLocked,
    required this.expensesNotificationsEnabled,
  });

  final bool expensesLocked;
  final bool expensesNotificationsEnabled;

  static const defaults = TripExpensesStates(
    expensesLocked: false,
    expensesNotificationsEnabled: true,
  );

  factory TripExpensesStates.fromMap(Map<String, dynamic> map) {
    return TripExpensesStates(
      expensesLocked: _parseBool(map['expensesLocked']),
      expensesNotificationsEnabled: _parseBool(
        map['expensesNotificationsEnabled'],
        defaultValue: true,
      ),
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
