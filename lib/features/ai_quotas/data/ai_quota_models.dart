/// AI features subject to quota enforcement.
///
/// The [firestoreKey] value is used as the document ID in Firestore quota
/// subcollections and must match the keys in functions/utils/aiQuotaGate.js.
enum AiFeature {
  recipeIngredients('recipeIngredients'),
  shoppingConsolidation('shoppingConsolidation');

  const AiFeature(this.firestoreKey);
  final String firestoreKey;
}

/// Why a quota reservation was rejected.
enum AiQuotaExceededReason {
  userDaily,
  tripDaily,
  tripLifetime,
  circuitBreaker,
}

/// Thrown by [AiQuotaGate] when the AI call cannot proceed due to quota.
class AiQuotaExceededException implements Exception {
  const AiQuotaExceededException(this.reason);
  final AiQuotaExceededReason reason;

  @override
  String toString() => 'AiQuotaExceededException($reason)';
}

/// Point-in-time snapshot of quota counters for a (user, trip, feature) tuple.
class AiQuotaSnapshot {
  const AiQuotaSnapshot({
    required this.userDayCount,
    required this.tripDayCount,
    required this.tripLifetimeCount,
  });

  const AiQuotaSnapshot.zero()
      : userDayCount = 0,
        tripDayCount = 0,
        tripLifetimeCount = 0;

  final int userDayCount;
  final int tripDayCount;
  final int tripLifetimeCount;
}
