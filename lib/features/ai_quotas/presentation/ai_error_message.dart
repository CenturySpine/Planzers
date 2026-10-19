import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_ai/firebase_ai.dart' show QuotaExceeded, ServerException;
import 'package:planerz/features/ai_quotas/data/ai_quota_config.dart';
import 'package:planerz/features/ai_quotas/data/ai_quota_models.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// User-facing message for a failed AI call of [feature]: quota reached, AI
/// provider unavailable (outage, prepaid credits used up...), or the error
/// itself.
String aiErrorMessage(
  AppLocalizations l10n,
  Object error,
  AiFeature feature,
) {
  if (error is FirebaseFunctionsException) {
    if (error.code == 'resource-exhausted') {
      final config = aiQuotaConfigs[feature]!;
      return switch (error.message) {
        'quota-trip' => l10n.aiQuotaTripExceeded(config.perTripPerDay),
        'quota-trip-lifetime' =>
          l10n.aiQuotaTripLifetimeExceeded(config.perTripLifetime),
        'circuit-breaker' => l10n.aiQuotaCircuitBreakerTripped,
        _ => l10n.aiQuotaUserExceeded(config.perUserPerDay),
      };
    }
    // Cloud Functions report any provider failure (HTTP 402, 429, 5xx) so.
    if (error.code == 'unavailable') return l10n.aiServiceUnavailable;
    return l10n.commonErrorWithDetails(error.message ?? error.code);
  }
  // Same failures when the app calls the provider directly (Firebase AI).
  if (error is ServerException || error is QuotaExceeded) {
    return l10n.aiServiceUnavailable;
  }
  return l10n.commonErrorWithDetails(error.toString());
}
