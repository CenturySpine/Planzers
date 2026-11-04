import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/ai_settings/data/ai_settings.dart';
import 'package:planerz/features/ai_settings/data/ai_settings_repository.dart';

const _kProviderLabels = {
  AiProvider.google: 'Google',
  AiProvider.anthropic: 'Anthropic',
};

const _kThinkingLevelLabels = {
  AiThinkingLevel.minimal: 'Minimale',
  AiThinkingLevel.low: 'Faible',
  AiThinkingLevel.medium: 'Moyenne',
  AiThinkingLevel.high: 'Élevée',
};

/// Administration: AI provider, model and thinking level used by the AI
/// features. Changes apply only when saved.
class AdminAiSettingsPage extends ConsumerStatefulWidget {
  const AdminAiSettingsPage({super.key});

  static const String routePath = '/administration/ai-settings';

  @override
  ConsumerState<AdminAiSettingsPage> createState() =>
      _AdminAiSettingsPageState();
}

class _AdminAiSettingsPageState extends ConsumerState<AdminAiSettingsPage> {
  /// Unsaved edits; null until the first change (the form then shows the
  /// saved settings).
  AiSettings? _draft;
  bool _isSaving = false;

  Future<void> _save(AiSettings settings) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSaving = true);
    try {
      await ref.read(aiSettingsRepositoryProvider).save(settings);
      messenger.showSnackBar(
        const SnackBar(content: Text('Réglages IA enregistrés.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Échec de l\'enregistrement : $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(aiSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Intelligence artificielle'),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Impossible de charger les réglages IA : $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (saved) => _buildForm(_draft ?? saved),
      ),
    );
  }

  Widget _buildForm(AiSettings settings) {
    final provider = settings.provider;
    final model = settings.modelFor(provider);
    final models = [
      ...aiProviderModels[provider]!,
      // Keeps a saved model that is no longer offered selectable.
      if (!aiProviderModels[provider]!.contains(model)) model,
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        // Keys follow the values so the fields show external updates too.
        DropdownButtonFormField<AiProvider>(
          key: ValueKey('provider-${provider.firestoreValue}'),
          initialValue: provider,
          decoration: const InputDecoration(labelText: 'Fournisseur'),
          items: [
            for (final p in AiProvider.values)
              DropdownMenuItem(value: p, child: Text(_kProviderLabels[p]!)),
          ],
          onChanged: _isSaving
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _draft = settings.copyWith(provider: value));
                },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('model-${provider.firestoreValue}-$model'),
          initialValue: model,
          decoration: const InputDecoration(labelText: 'Modèle'),
          items: [
            for (final m in models) DropdownMenuItem(value: m, child: Text(m)),
          ],
          onChanged: _isSaving
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _draft = settings.withModel(provider, value));
                },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<AiThinkingLevel>(
          key: ValueKey('thinking-${settings.thinkingLevel.firestoreValue}'),
          initialValue: settings.thinkingLevel,
          decoration: const InputDecoration(labelText: 'Niveau de réflexion'),
          items: [
            for (final level in AiThinkingLevel.values)
              DropdownMenuItem(
                value: level,
                child: Text(_kThinkingLevelLabels[level]!),
              ),
          ],
          onChanged: _isSaving
              ? null
              : (value) {
                  if (value == null) return;
                  setState(
                    () => _draft = settings.copyWith(thinkingLevel: value),
                  );
                },
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isSaving ? null : () => _save(settings),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
