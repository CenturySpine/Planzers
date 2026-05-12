/// Firestore: `trips/{tripId}/shopping_list_locks/{docId}`.
///
/// UI-only enforcement in the app for now; Firestore rules will follow.
const String kTripShoppingListLocksDocId = 'default';

/// Lock flags for trip shopping list tabs.
class TripShoppingListLocks {
  const TripShoppingListLocks({
    required this.manualListLocked,
    required this.consolidatedListLocked,
  });

  final bool manualListLocked;
  final bool consolidatedListLocked;

  static const defaults = TripShoppingListLocks(
    manualListLocked: false,
    consolidatedListLocked: false,
  );

  factory TripShoppingListLocks.fromMap(Map<String, dynamic> map) {
    return TripShoppingListLocks(
      manualListLocked: _parseBool(map['manualListLocked']),
      consolidatedListLocked: _parseBool(map['consolidatedListLocked']),
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
