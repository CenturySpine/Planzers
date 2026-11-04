/// AI provider used by shopping list consolidation.
///
/// Recipe generation always calls Google and uses [AiSettings.googleModel],
/// whatever the selected provider.
enum AiProvider {
  google('google'),
  anthropic('anthropic');

  const AiProvider(this.firestoreValue);

  final String firestoreValue;
}

/// Provider-agnostic thinking level, translated into each provider's own
/// values by the Cloud Functions (see functions/ai_settings.js).
enum AiThinkingLevel {
  minimal('minimal'),
  low('low'),
  medium('medium'),
  high('high');

  const AiThinkingLevel(this.firestoreValue);

  final String firestoreValue;
}

/// Models offered in the administration for each provider. Every model listed
/// here must accept all [AiThinkingLevel] values once translated.
const aiProviderModels = <AiProvider, List<String>>{
  AiProvider.google: [
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
    'gemini-3.6-flash',
  ],
  AiProvider.anthropic: [
    'claude-haiku-5-5',
    'claude-sonnet-5-5',
    'claude-opus-5-5',
  ],
};

/// AI settings chosen in the administration (Firestore `system/aiSettings`).
///
/// One model is remembered per provider, so switching provider keeps the
/// previous choice of the other one.
///
/// Mirrors functions/ai_settings.js (fields and defaults) — keep in sync.
class AiSettings {
  const AiSettings({
    required this.provider,
    required this.googleModel,
    required this.anthropicModel,
    required this.thinkingLevel,
  });

  static const AiSettings defaults = AiSettings(
    provider: AiProvider.google,
    googleModel: 'gemini-3.5-flash-lite',
    anthropicModel: 'claude-haiku-5-5',
    thinkingLevel: AiThinkingLevel.minimal,
  );

  final AiProvider provider;
  final String googleModel;
  final String anthropicModel;
  final AiThinkingLevel thinkingLevel;

  /// Reads a Firestore document; missing or unknown values fall back to
  /// [defaults].
  factory AiSettings.fromFirestore(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return AiSettings(
      provider: AiProvider.values.firstWhere(
        (p) => p.firestoreValue == map['provider'],
        orElse: () => defaults.provider,
      ),
      googleModel: _modelOrDefault(map['googleModel'], defaults.googleModel),
      anthropicModel:
          _modelOrDefault(map['anthropicModel'], defaults.anthropicModel),
      thinkingLevel: AiThinkingLevel.values.firstWhere(
        (l) => l.firestoreValue == map['thinkingLevel'],
        orElse: () => defaults.thinkingLevel,
      ),
    );
  }

  static String _modelOrDefault(Object? value, String fallback) {
    final model = value is String ? value.trim() : '';
    return model.isEmpty ? fallback : model;
  }

  Map<String, dynamic> toFirestore() => {
        'provider': provider.firestoreValue,
        'googleModel': googleModel,
        'anthropicModel': anthropicModel,
        'thinkingLevel': thinkingLevel.firestoreValue,
      };

  /// Model remembered for [provider].
  String modelFor(AiProvider provider) => switch (provider) {
        AiProvider.google => googleModel,
        AiProvider.anthropic => anthropicModel,
      };

  /// Copy where the model of [provider] is [model].
  AiSettings withModel(AiProvider provider, String model) => AiSettings(
        provider: this.provider,
        googleModel: provider == AiProvider.google ? model : googleModel,
        anthropicModel:
            provider == AiProvider.anthropic ? model : anthropicModel,
        thinkingLevel: thinkingLevel,
      );

  AiSettings copyWith({
    AiProvider? provider,
    AiThinkingLevel? thinkingLevel,
  }) =>
      AiSettings(
        provider: provider ?? this.provider,
        googleModel: googleModel,
        anthropicModel: anthropicModel,
        thinkingLevel: thinkingLevel ?? this.thinkingLevel,
      );
}
