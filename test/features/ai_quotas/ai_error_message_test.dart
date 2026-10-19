import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_ai/firebase_ai.dart' show ServerException;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/ai_quotas/data/ai_quota_models.dart';
import 'package:planerz/features/ai_quotas/presentation/ai_error_message.dart';
import 'package:planerz/l10n/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('fr'));

  group('aiErrorMessage', () {
    test('explains an unavailable AI provider', () {
      final error = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Service IA indisponible (Gemini 402)',
      );

      expect(
        aiErrorMessage(l10n, error, AiFeature.textActivityCreate),
        l10n.aiServiceUnavailable,
      );
      expect(
        aiErrorMessage(l10n, ServerException('402'), AiFeature.recipeIngredients),
        l10n.aiServiceUnavailable,
      );
    });

    test('uses the quota limits of the feature', () {
      final error = FirebaseFunctionsException(
        code: 'resource-exhausted',
        message: 'quota-trip',
      );

      expect(
        aiErrorMessage(l10n, error, AiFeature.textActivityCreate),
        l10n.aiQuotaTripExceeded(20),
      );
    });

    test('keeps other errors readable', () {
      final error = FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Réservé au créateur',
      );

      expect(
        aiErrorMessage(l10n, error, AiFeature.documentActivityImport),
        l10n.commonErrorWithDetails('Réservé au créateur'),
      );
    });
  });
}
