import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/ai_quotas/data/ai_quota_models.dart';
import 'package:planerz/features/ai_quotas/data/ai_quotas_repository.dart';

final aiQuotaGateProvider = Provider<AiQuotaGate>(
  (ref) => AiQuotaGate(ref.read(aiQuotasRepositoryProvider)),
);

/// Single entry point for any AI call subject to quota enforcement.
///
/// - Application owners bypass all quota checks entirely.
/// - For everyone else: atomically reserves quota before the call, and
///   automatically refunds on exception (best-effort).
/// - Throws [AiQuotaExceededException] if the reservation is rejected.
class AiQuotaGate {
  AiQuotaGate(this._repo);

  final AiQuotasRepository _repo;

  Future<T> call<T>({
    required AiFeature feature,
    required String uid,
    required String tripId,
    required bool isApplicationOwner,
    required Future<T> Function() aiCall,
  }) async {
    if (isApplicationOwner) return aiCall();
    await _repo.reserve(feature: feature, uid: uid, tripId: tripId);
    try {
      return await aiCall();
    } catch (e) {
      await _repo.refund(feature: feature, uid: uid, tripId: tripId);
      rethrow;
    }
  }
}
