import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/features/ai_quotas/data/ai_quota_models.dart';

final aiQuotasRepositoryProvider = Provider<AiQuotasRepository>((ref) {
  return AiQuotasRepository(firestore: FirebaseFirestore.instance);
});

/// Provides the live (user day count, trip day count, trip lifetime count)
/// for a given feature, user, and trip. Combines two Firestore streams.
///
/// The key is a record: (uid, tripId, featureKey).
final aiQuotaSnapshotProvider = StreamProvider.autoDispose
    .family<AiQuotaSnapshot, ({String uid, String tripId, String featureKey})>(
  (ref, key) => ref
      .watch(aiQuotasRepositoryProvider)
      .watchQuotas(uid: key.uid, tripId: key.tripId, featureKey: key.featureKey),
);

/// Streams `true` when the global AI circuit breaker is tripped for today.
final aiCircuitBreakerTrippedProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref.watch(aiQuotasRepositoryProvider).watchCircuitBreakerTripped(),
);

class AiQuotasRepository {
  AiQuotasRepository({required this.firestore});

  final FirebaseFirestore firestore;

  String _todayUtcKey() {
    final now = DateTime.now().toUtc();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  int _dayCount(Map<String, dynamic> data) {
    final today = _todayUtcKey();
    if (data['currentDayKey'] != today) return 0;
    return (data['currentDayCount'] as num?)?.toInt() ?? 0;
  }

  /// Calls the CF `reserveAiQuota`. Throws [AiQuotaExceededException] if any
  /// quota is exceeded; maps the typed error codes from the CF.
  Future<void> reserve({
    required AiFeature feature,
    required String uid,
    required String tripId,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: kFirebaseFunctionsRegion,
      ).httpsCallable('reserveAiQuota');
      await callable.call<Map<String, dynamic>>({
        'featureKey': feature.firestoreKey,
        'tripId': tripId,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        final reason = switch (e.message) {
          'quota-user' => AiQuotaExceededReason.userDaily,
          'quota-trip' => AiQuotaExceededReason.tripDaily,
          'quota-trip-lifetime' => AiQuotaExceededReason.tripLifetime,
          'circuit-breaker' => AiQuotaExceededReason.circuitBreaker,
          _ => AiQuotaExceededReason.userDaily,
        };
        throw AiQuotaExceededException(reason);
      }
      rethrow;
    }
  }

  /// Calls the CF `refundAiQuota`. Best-effort: errors are swallowed.
  Future<void> refund({
    required AiFeature feature,
    required String uid,
    required String tripId,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: kFirebaseFunctionsRegion,
      ).httpsCallable('refundAiQuota');
      await callable.call<Map<String, dynamic>>({
        'featureKey': feature.firestoreKey,
        'tripId': tripId,
      });
    } catch (_) {
      // Best-effort: refund failure is not critical.
    }
  }

  /// Combines user and trip quota streams into a single [AiQuotaSnapshot].
  Stream<AiQuotaSnapshot> watchQuotas({
    required String uid,
    required String tripId,
    required String featureKey,
  }) {
    final userRef = firestore
        .collection('users')
        .doc(uid)
        .collection('aiQuotas')
        .doc(featureKey);
    final tripRef = firestore
        .collection('trips')
        .doc(tripId)
        .collection('aiQuotas')
        .doc(featureKey);

    final userStream = userRef
        .snapshots()
        .map((s) => s.data() ?? <String, dynamic>{});
    final tripStream = tripRef
        .snapshots()
        .map((s) => s.data() ?? <String, dynamic>{});

    // Merge the two streams manually without external dependencies.
    Map<String, dynamic>? lastUser;
    Map<String, dynamic>? lastTrip;

    return Stream<AiQuotaSnapshot>.multi((controller) {
      final userSub = userStream.listen(
        (data) {
          lastUser = data;
          if (lastTrip != null) {
            controller.add(_buildSnapshot(lastUser!, lastTrip!));
          }
        },
        onError: controller.addError,
      );
      final tripSub = tripStream.listen(
        (data) {
          lastTrip = data;
          if (lastUser != null) {
            controller.add(_buildSnapshot(lastUser!, lastTrip!));
          }
        },
        onError: controller.addError,
      );
      controller.onCancel = () {
        userSub.cancel();
        tripSub.cancel();
      };
    });
  }

  AiQuotaSnapshot _buildSnapshot(
    Map<String, dynamic> userData,
    Map<String, dynamic> tripData,
  ) {
    return AiQuotaSnapshot(
      userDayCount: _dayCount(userData),
      tripDayCount: _dayCount(tripData),
      tripLifetimeCount: (tripData['lifetimeCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Streams `true` when the global circuit breaker is tripped.
  Stream<bool> watchCircuitBreakerTripped() {
    return firestore
        .collection('system')
        .doc('aiCircuitBreaker')
        .snapshots()
        .map((snap) {
      if (!snap.exists) return false;
      final data = snap.data() ?? {};
      return data['tripped'] == true;
    });
  }
}
