import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/administration/data/external_providers_repository.dart';

final _externalProvidersRepositoryProvider =
    Provider.autoDispose((_) => ExternalProvidersRepository());

final _externalProvidersAdminProvider =
    FutureProvider.autoDispose<List<ExternalProviderAdminSummary>>((ref) {
  return ref.read(_externalProvidersRepositoryProvider).listProviders();
});

InputDecoration _neonFieldDecoration({
  required String label,
  String? hint,
  String? helper,
  int? helperMaxLines,
}) {
  const radius = BorderRadius.all(Radius.circular(12));
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: helperMaxLines,
    filled: true,
    fillColor: NeonPalette.surface,
    labelStyle: const TextStyle(color: NeonPalette.onSurfaceVariant),
    hintStyle: const TextStyle(color: NeonPalette.outline),
    helperStyle: const TextStyle(color: NeonPalette.onSurfaceVariant, fontSize: 12),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: NeonPalette.divider, width: 1.5),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: NeonPalette.divider, width: 1.5),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: NeonPalette.primary, width: 2),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: NeonPalette.accent, width: 1.5),
    ),
    focusedErrorBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: NeonPalette.accent, width: 2),
    ),
  );
}

/// Administration-only screen (French hardcoded, per project convention):
/// registers the ecosystem providers (Ridgegear, Killer, ...) Planerz users
/// are allowed to connect their account to. Mirror image of
/// [AdminOAuthClientsPage] — here Planerz is the OAuth *client*, not the
/// provider. Néon-styled, per the handoff rolled out since mid-June.
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
      barrierColor: Colors.black.withValues(alpha: 0.40),
      builder: (dialogContext) => Dialog(
        backgroundColor: NeonPalette.surface,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Nouveau fournisseur externe',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: NeonPalette.deep,
                  ),
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: SingleChildScrollView(
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: providerIdController,
                            decoration: _neonFieldDecoration(
                              label: 'providerId (minuscules et tirets, ex. "ridgegear")',
                            ),
                            style: const TextStyle(color: NeonPalette.deep),
                            validator: (v) =>
                                (v ?? '').trim().isEmpty ? 'Requis' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: displayNameController,
                            decoration: _neonFieldDecoration(
                              label: 'Nom affiché (ex. "Ridgegear")',
                            ),
                            style: const TextStyle(color: NeonPalette.deep),
                            validator: (v) =>
                                (v ?? '').trim().isEmpty ? 'Requis' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: iconUrlController,
                            decoration: _neonFieldDecoration(
                              label: "URL de l'icône",
                            ),
                            style: const TextStyle(color: NeonPalette.deep),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: authorizeUrlController,
                            decoration: _neonFieldDecoration(
                              label: "URL d'autorisation du fournisseur",
                              hint: 'https://ridgegear.example.com/oauth/authorize',
                            ),
                            style: const TextStyle(color: NeonPalette.deep),
                            validator: (v) =>
                                (v ?? '').trim().isEmpty ? 'Requis' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: tokenUrlController,
                            decoration: _neonFieldDecoration(
                              label: 'URL de jeton du fournisseur',
                              hint: 'https://ridgegear.example.com/oauth/token',
                            ),
                            style: const TextStyle(color: NeonPalette.deep),
                            validator: (v) =>
                                (v ?? '').trim().isEmpty ? 'Requis' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: scopeController,
                            decoration: _neonFieldDecoration(
                              label: 'Portée demandée (ex. "gear.read")',
                            ),
                            style: const TextStyle(color: NeonPalette.deep),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: clientIdController,
                            decoration: _neonFieldDecoration(
                              label: 'client_id délivré par le fournisseur',
                            ),
                            style: const TextStyle(color: NeonPalette.deep),
                            validator: (v) =>
                                (v ?? '').trim().isEmpty ? 'Requis' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: clientSecretController,
                            decoration: _neonFieldDecoration(
                              label: 'client_secret délivré par le fournisseur',
                              helper:
                                  'Écrit directement dans Secret Manager, jamais stocké en clair dans Firestore. '
                                  'Il ne sera plus jamais affiché après création.',
                              helperMaxLines: 3,
                            ),
                            style: const TextStyle(color: NeonPalette.deep),
                            obscureText: true,
                            validator: (v) =>
                                (v ?? '').trim().isEmpty ? 'Requis' : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text(
                        'Annuler',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: NeonPalette.text700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        if (formKey.currentState?.validate() != true) return;
                        Navigator.of(dialogContext).pop(true);
                      },
                      child: const Text(
                        'Créer',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: NeonPalette.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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

    return Theme(
      data: NeonPalette.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: NeonPalette.scaffoldBackground,
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
                    leading: CircleAvatar(
                      backgroundColor: NeonPalette.nameIconBackground,
                      backgroundImage: provider.iconUrl.isNotEmpty
                          ? NetworkImage(provider.iconUrl)
                          : null,
                      child: provider.iconUrl.isEmpty
                          ? const Icon(Icons.hub_outlined, color: NeonPalette.primary)
                          : null,
                    ),
                    title: Text(
                      provider.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: NeonPalette.deep,
                      ),
                    ),
                    subtitle: Text(
                      'providerId : ${provider.providerId}\n'
                      'client_id : ${provider.clientId}\n'
                      'Portée : ${provider.scope}',
                      style: const TextStyle(color: NeonPalette.onSurfaceVariant),
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: NeonPalette.accent),
                      tooltip: 'Supprimer',
                      onPressed: () => _confirmAndDelete(context, ref, provider),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
