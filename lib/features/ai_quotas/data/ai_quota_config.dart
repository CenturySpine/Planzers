import 'package:planerz/features/ai_quotas/data/ai_quota_models.dart';

/// Static per-feature quota limits.
///
/// Mirrors functions/utils/aiQuotaGate.js QUOTA_CONFIGS — keep in sync.
class AiQuotaConfig {
  const AiQuotaConfig({
    required this.perUserPerDay,
    required this.perTripPerDay,
    required this.perTripLifetime,
  });

  final int perUserPerDay;
  final int perTripPerDay;
  final int perTripLifetime;
}

const aiQuotaConfigs = <AiFeature, AiQuotaConfig>{
  AiFeature.recipeIngredients: AiQuotaConfig(
    perUserPerDay: 5,
    perTripPerDay: 10,
    perTripLifetime: 30,
  ),
  AiFeature.shoppingConsolidation: AiQuotaConfig(
    perUserPerDay: 2,
    perTripPerDay: 3,
    perTripLifetime: 10,
  ),
};
