import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/account/data/connected_apps_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

final _myConnectedAppsProvider =
    StreamProvider.autoDispose<List<ConnectedApp>>((ref) {
  return ref.read(connectedAppsRepositoryProvider).watchMyConnectedApps();
});

/// "Applications connectées" — lets a Planerz user see and revoke the
/// third-party apps (e.g. Ridgegear) they've authorized via OAuth to read
/// their trips.
class ConnectedAppsPage extends ConsumerWidget {
  const ConnectedAppsPage({super.key});

  static const String routePath = '/account/connected-apps';

  Future<void> _confirmAndRevoke(
    BuildContext context,
    WidgetRef ref,
    ConnectedApp app,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.connectedAppsRevokeDialogTitle),
        content: Text(l10n.connectedAppsRevokeDialogBody(app.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.connectedAppsRevokeAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(connectedAppsRepositoryProvider).revoke(app.clientId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.connectedAppsRevoked(app.displayName))),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final appsAsync = ref.watch(_myConnectedAppsProvider);
    final dateFormat = DateFormat('dd/MM/yyyy à HH:mm');

    return Theme(
      data: NeonPalette.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: NeonPalette.scaffoldBackground,
        appBar: AppBar(title: Text(l10n.connectedAppsTitle)),
        body: appsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(l10n.commonErrorWithDetails(error.toString())),
          ),
          data: (apps) {
            if (apps.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.connectedAppsEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: apps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final app = apps[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      backgroundImage: app.iconUrl.isNotEmpty
                          ? NetworkImage(app.iconUrl)
                          : null,
                      child: app.iconUrl.isEmpty
                          ? const Icon(Icons.apps_rounded)
                          : null,
                    ),
                    title: Text(app.displayName),
                    subtitle: Text(
                      app.lastUsedAt != null
                          ? l10n.connectedAppsLastUsed(
                              dateFormat.format(app.lastUsedAt!.toLocal()),
                            )
                          : l10n.connectedAppsNeverUsed,
                    ),
                    trailing: TextButton(
                      onPressed: () => _confirmAndRevoke(context, ref, app),
                      child: Text(l10n.connectedAppsRevokeAction),
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
