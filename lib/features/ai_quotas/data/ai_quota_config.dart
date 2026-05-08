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
    perUserPerDay: 30,
    perTripPerDay: 50,
    perTripLifetime: 200,
  ),
  AiFeature.shoppingConsolidation: AiQuotaConfig(
    perUserPerDay: 10,
    perTripPerDay: 20,
    perTripLifetime: 100,
  ),
};
