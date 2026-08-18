import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/administration/data/oauth_clients_repository.dart';

final _oauthClientsRepositoryProvider =
    Provider.autoDispose((_) => OAuthClientsRepository());

final _oauthClientsProvider =
    FutureProvider.autoDispose<List<OAuthClientSummary>>((ref) {
  return ref.read(_oauthClientsRepositoryProvider).listClients();
});

/// Administration-only screen (French hardcoded, per project convention):
/// registers third-party apps (e.g. Ridgegear) allowed to use the OAuth
/// consent flow to read a user's trips via the public API.
class AdminOAuthClientsPage extends ConsumerWidget {
  const AdminOAuthClientsPage({super.key});

  static const String routePath = '/administration/oauth-clients';

  Future<void> _openCreateDialog(BuildContext context, WidgetRef ref) async {
    final clientIdController = TextEditingController();
    final displayNameController = TextEditingController();
    final iconUrlController = TextEditingController();
    final redirectUriController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvelle application tierce'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: clientIdController,
                  decoration: const InputDecoration(
                    labelText: 'client_id (technique, ex. "ridgegear")',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Requis' : null,
                ),
                TextFormField(
                  controller: displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom affiché à l\'utilisateur (ex. "Ridgegear")',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Requis' : null,
                ),
                TextFormField(
                  controller: iconUrlController,
                  decoration: const InputDecoration(
                    labelText: 'URL de l\'icône (affichée sur l\'écran de consentement)',
                  ),
                ),
                TextFormField(
                  controller: redirectUriController,
                  decoration: const InputDecoration(
                    labelText: 'Redirect URI autorisée',
                    hintText: 'https://ridgegear.example.com/api/planerz/callback',
                  ),
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
      final secret = await ref.read(_oauthClientsRepositoryProvider).createClient(
            clientId: clientIdController.text.trim(),
            displayName: displayNameController.text.trim(),
            iconUrl: iconUrlController.text.trim(),
            redirectUris: [redirectUriController.text.trim()],
            scopesAllowed: const ['trips.read'],
          );
      if (!context.mounted) return;
      ref.invalidate(_oauthClientsProvider);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('client_secret généré'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ce secret ne sera plus jamais affiché. Copie-le maintenant '
                'et transmets-le à l\'équipe de l\'application tierce.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                secret,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: secret));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Secret copié')),
                  );
                }
              },
              child: const Text('Copier'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
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
    OAuthClientSummary client,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer cette application ?'),
        content: Text(
          '"${client.displayName}" ne pourra plus obtenir de nouveaux jetons. '
          'Les utilisateurs devront redonner leur consentement si elle est ré-enregistrée.',
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
          .read(_oauthClientsRepositoryProvider)
          .deleteClient(client.clientId);
      ref.invalidate(_oauthClientsProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec de la suppression : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.watch(_oauthClientsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Applications tierces (OAuth)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Enregistrer une application',
            onPressed: () => _openCreateDialog(context, ref),
          ),
        ],
      ),
      body: clientsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (clients) {
          if (clients.isEmpty) {
            return const Center(
              child: Text('Aucune application tierce enregistrée.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: clients.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final client = clients[index];
              return Card(
                child: ListTile(
                  title: Text(client.displayName),
                  subtitle: Text(
                    'client_id : ${client.clientId}\n'
                    'Redirect : ${client.redirectUris.join(', ')}\n'
                    'Portées : ${client.scopesAllowed.join(', ')}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Supprimer',
                    onPressed: () => _confirmAndDelete(context, ref, client),
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
