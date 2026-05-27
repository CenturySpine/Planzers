/// Firestore: `trips/{tripId}/expenses_states/{docId}`.
///
/// Trip-wide expense section settings (notification channel). Post lock lives under
/// `expenseGroups/{groupId}/state/current`.
const String kTripExpensesStatesDocId = 'default';

/// Trip expense section state (notification channel).
class TripExpensesStates {
  const TripExpensesStates({
    required this.expensesNotificationsEnabled,
  });

  final bool expensesNotificationsEnabled;

  static const defaults = TripExpensesStates(
    expensesNotificationsEnabled: true,
  );

  factory TripExpensesStates.fromMap(Map<String, dynamic> map) {
    return TripExpensesStates(
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
