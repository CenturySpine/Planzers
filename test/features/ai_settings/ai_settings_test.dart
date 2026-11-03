import 'package:firebase_ai/firebase_ai.dart' show ThinkingLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/ai_settings/data/ai_settings.dart';

void main() {
  group('AiSettings.fromFirestore', () {
    test('uses the defaults when the document does not exist', () {
      final settings = AiSettings.fromFirestore(null);

      expect(settings.provider, AiProvider.google);
      expect(settings.googleModel, 'gemini-3.5-flash-lite');
      expect(settings.anthropicModel, 'claude-haiku-5-5');
      expect(settings.thinkingLevel, AiThinkingLevel.minimal);
    });

    test('replaces unknown or empty values by the defaults', () {
      final settings = AiSettings.fromFirestore({
        'provider': 'openai',
        'googleModel': '  ',
        'anthropicModel': 42,
        'thinkingLevel': 'max',
      });

      expect(settings.toFirestore(), AiSettings.defaults.toFirestore());
    });

    test('round-trips through Firestore', () {
      const settings = AiSettings(
        provider: AiProvider.anthropic,
        googleModel: 'gemini-3.6-flash',
        anthropicModel: 'claude-sonnet-5-5',
        thinkingLevel: AiThinkingLevel.high,
      );

      expect(
        AiSettings.fromFirestore(settings.toFirestore()).toFirestore(),
        settings.toFirestore(),
      );
    });
  });

  test('remembers one model per provider', () {
    final settings = AiSettings.defaults
        .withModel(AiProvider.anthropic, 'claude-sonnet-5-5')
        .copyWith(provider: AiProvider.anthropic);

    expect(settings.modelFor(AiProvider.anthropic), 'claude-sonnet-5-5');
    expect(settings.modelFor(AiProvider.google), 'gemini-3.5-flash-lite');
  });

  test('offers the default models', () {
    expect(
      aiProviderModels[AiProvider.google],
      contains(AiSettings.defaults.googleModel),
    );
    expect(
      aiProviderModels[AiProvider.anthropic],
      contains(AiSettings.defaults.anthropicModel),
    );
  });

  test('maps the generic thinking levels to Gemini levels', () {
    expect(AiThinkingLevel.minimal.geminiThinkingLevel, ThinkingLevel.minimal);
    expect(AiThinkingLevel.low.geminiThinkingLevel, ThinkingLevel.low);
    expect(AiThinkingLevel.medium.geminiThinkingLevel, ThinkingLevel.medium);
    expect(AiThinkingLevel.high.geminiThinkingLevel, ThinkingLevel.high);
  });
}
