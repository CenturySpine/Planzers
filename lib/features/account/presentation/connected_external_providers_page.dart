import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/account/data/connected_external_providers_repository.dart';
import 'package:planerz/features/oauth/data/external_connection_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

final _externalProvidersListProvider =
    FutureProvider.autoDispose<List<ExternalProviderPublicInfo>>((ref) {
  return ref.read(externalConnectionRepositoryProvider).listProviders();
});

final _myConnectedExternalProvidersProvider =
    StreamProvider.autoDispose<List<ConnectedExternalProvider>>((ref) {
  return ref
      .read(connectedExternalProvidersRepositoryProvider)
      .watchMyConnectedProviders();
});

/// "Comptes externes connectés" — Planerz acting as an OAuth *client* this
/// time: lets a user connect their account with an ecosystem provider (e.g.
/// Ridgegear) and see/revoke existing connections. Mirror image of
/// [ConnectedAppsPage].
class ConnectedExternalProvidersPage extends ConsumerStatefulWidget {
  const ConnectedExternalProvidersPage({super.key});

  static const String routePath = '/account/external-connections';

  @override
  ConsumerState<ConnectedExternalProvidersPage> createState() =>
      _ConnectedExternalProvidersPageState();
}

class _ConnectedExternalProvidersPageState
    extends ConsumerState<ConnectedExternalProvidersPage> {
  String? _connectingProviderId;

  Future<void> _connect(ExternalProviderPublicInfo provider) async {
    if (_connectingProviderId != null) return;
    setState(() => _connectingProviderId = provider.providerId);
    try {
      final redirectUri = '${Uri.base.origin}/external/callback';
      final authorizeUrl = await ref
          .read(externalConnectionRepositoryProvider)
          .beginConnection(
            providerId: provider.providerId,
            redirectUri: redirectUri,
          );
      if (!mounted || authorizeUrl.isEmpty) return;
      await launchUrl(
        Uri.parse(authorizeUrl),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _connectingProviderId = null);
    }
  }

  Future<void> _confirmAndRevoke(ConnectedExternalProvider connected) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.externalConnectionRevokeDialogTitle),
        content: Text(
          l10n.externalConnectionRevokeDialogBody(connected.displayName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.externalConnectionDisconnect),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(connectedExternalProvidersRepositoryProvider)
          .revoke(connected.providerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.externalConnectionRevoked(connected.displayName),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final providersAsync = ref.watch(_externalProvidersListProvider);
    final connectedAsync = ref.watch(_myConnectedExternalProvidersProvider);
    final dateFormat = DateFormat('dd/MM/yyyy à HH:mm');

    return Theme(
      data: NeonPalette.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: NeonPalette.scaffoldBackground,
        appBar: AppBar(title: Text(l10n.connectedExternalProvidersTitle)),
        body: providersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(l10n.commonErrorWithDetails(error.toString())),
          ),
          data: (providers) {
            if (providers.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.connectedExternalProvidersEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              );
            }
            final connectedList = connectedAsync.maybeWhen(
              data: (list) => list,
              orElse: () => const <ConnectedExternalProvider>[],
            );
            final connectedByProviderId = <String, ConnectedExternalProvider>{
              for (final c in connectedList) c.providerId: c,
            };
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: providers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final provider = providers[index];
                final connected = connectedByProviderId[provider.providerId];
                final isConnecting = _connectingProviderId == provider.providerId;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      backgroundImage: provider.iconUrl.isNotEmpty
                          ? NetworkImage(provider.iconUrl)
                          : null,
                      child: provider.iconUrl.isEmpty
                          ? const Icon(Icons.apps_rounded)
                          : null,
                    ),
                    title: Text(provider.displayName),
                    subtitle: Text(
                      connected == null
                          ? l10n.externalConnectionNotConnected
                          : (connected.lastUsedAt != null
                              ? l10n.connectedAppsLastUsed(
                                  dateFormat.format(
                                    connected.lastUsedAt!.toLocal(),
                                  ),
                                )
                              : l10n.connectedAppsNeverUsed),
                    ),
                    trailing: connected == null
                        ? FilledButton(
                            onPressed:
                                isConnecting ? null : () => _connect(provider),
                            child: isConnecting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(l10n.externalConnectionConnect),
                          )
                        : TextButton(
                            onPressed: () => _confirmAndRevoke(connected),
                            child: Text(l10n.externalConnectionDisconnect),
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
