import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/administration/data/external_providers_repository.dart';

final _externalProvidersRepositoryProvider =
    Provider.autoDispose((_) => ExternalProvidersRepository());

final _externalProvidersAdminProvider =
    FutureProvider.autoDispose<List<ExternalProviderAdminSummary>>((ref) {
  return ref.read(_externalProvidersRepositoryProvider).listProviders();
});

/// Administration-only screen (French hardcoded, per project convention):
/// registers the ecosystem providers (Ridgegear, Killer, ...) Planerz users
/// are allowed to connect their account to. Mirror image of
/// [AdminOAuthClientsPage] — here Planerz is the OAuth *client*, not the
/// provider.
class AdminExternalProvidersPage extends ConsumerWidget {
  const AdminExternalProvidersPage({super.key});

  static const String routePath = '/administration/external-providers';

  Future<void> _openCreateDialog(BuildContext context, WidgetRef ref) async {
    final providerIdController = TextEditingController();
    final displayNameController = TextEditingController();
    final iconUrlController = TextEditingController();
    final authorizeUrlController = TextEditingController();
    final tokenUrlController = TextEditingController();
    final scopeController = TextEditingController();
    final clientIdController = TextEditingController();
    final clientSecretController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouveau fournisseur externe'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: providerIdController,
                  decoration: const InputDecoration(
                    labelText: 'providerId (minuscules et tirets, ex. "ridgegear")',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Requis' : null,
                ),
                TextFormField(
                  controller: displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom affiché (ex. "Ridgegear")',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Requis' : null,
                ),
                TextFormField(
                  controller: iconUrlController,
                  decoration: const InputDecoration(
                    labelText: "URL de l'icône",
                  ),
                ),
                TextFormField(
                  controller: authorizeUrlController,
                  decoration: const InputDecoration(
                    labelText: "URL d'autorisation du fournisseur",
                    hintText: 'https://ridgegear.example.com/oauth/authorize',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Requis' : null,
                ),
                TextFormField(
                  controller: tokenUrlController,
                  decoration: const InputDecoration(
                    labelText: 'URL de jeton du fournisseur',
                    hintText: 'https://ridgegear.example.com/oauth/token',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Requis' : null,
                ),
                TextFormField(
                  controller: scopeController,
                  decoration: const InputDecoration(
                    labelText: 'Portée demandée (ex. "gear.read")',
                  ),
                ),
                TextFormField(
                  controller: clientIdController,
                  decoration: const InputDecoration(
                    labelText: 'client_id délivré par le fournisseur',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Requis' : null,
                ),
                TextFormField(
                  controller: clientSecretController,
                  decoration: const InputDecoration(
                    labelText: 'client_secret délivré par le fournisseur',
                    helperText:
                        'Écrit directement dans Secret Manager, jamais stocké en clair dans Firestore. '
                        'Il ne sera plus jamais affiché après création.',
                    helperMaxLines: 3,
                  ),
                  obscureText: true,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Requis' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (created != true) return;

    try {
      await ref.read(_externalProvidersRepositoryProvider).createProvider(
            providerId: providerIdController.text.trim().toLowerCase(),
            displayName: displayNameController.text.trim(),
            iconUrl: iconUrlController.text.trim(),
            authorizeUrl: authorizeUrlController.text.trim(),
            tokenUrl: tokenUrlController.text.trim(),
            scope: scopeController.text.trim(),
            clientId: clientIdController.text.trim(),
            clientSecret: clientSecretController.text.trim(),
          );
      if (!context.mounted) return;
      ref.invalidate(_externalProvidersAdminProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fournisseur créé')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec de la création : $e')),
      );
    }
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    WidgetRef ref,
    ExternalProviderAdminSummary provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce fournisseur ?'),
        content: Text(
          'Les utilisateurs ne pourront plus connecter leur compte à '
          '"${provider.displayName}". Les connexions déjà existantes ne '
          'sont pas automatiquement révoquées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(_externalProvidersRepositoryProvider)
          .deleteProvider(provider.providerId);
      ref.invalidate(_externalProvidersAdminProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec de la suppression : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(_externalProvidersAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fournisseurs externes (OAuth)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Enregistrer un fournisseur',
            onPressed: () => _openCreateDialog(context, ref),
          ),
        ],
      ),
      body: providersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (providers) {
          if (providers.isEmpty) {
            return const Center(
              child: Text('Aucun fournisseur externe enregistré.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: providers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final provider = providers[index];
              return Card(
                child: ListTile(
                  title: Text(provider.displayName),
                  subtitle: Text(
                    'providerId : ${provider.providerId}\n'
                    'client_id : ${provider.clientId}\n'
                    'Portée : ${provider.scope}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Supprimer',
                    onPressed: () => _confirmAndDelete(context, ref, provider),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
