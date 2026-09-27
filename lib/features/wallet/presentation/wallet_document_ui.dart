import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/core/network/connectivity_provider.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/features/wallet/data/wallet_repository.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_form_page.dart';
import 'package:planerz/l10n/app_localizations.dart';

String formatWalletDate(BuildContext context, DateTime date) {
  return DateFormat.yMMMd(Localizations.localeOf(context).toString())
      .format(date);
}

/// Category, then date when set (e.g. "Train · 12 oct. 2026").
String walletDocumentSubtitle(BuildContext context, WalletDocument document) {
  final l10n = AppLocalizations.of(context)!;
  final category = document.category.label(l10n);
  final date = document.eventDate;
  return date == null ? category : '$category · ${formatWalletDate(context, date)}';
}

enum WalletDocumentAction { download, removeFromDevice, edit, delete }

/// "⋮" menu of a document, shared by the list cards and the viewer.
class WalletDocumentActionsButton extends ConsumerWidget {
  const WalletDocumentActionsButton({
    super.key,
    required this.tripId,
    required this.document,
    this.onDeleted,
  });

  final String tripId;
  final WalletDocument document;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final offline = ref.watch(isOfflineProvider);
    final hasFile = document.file != null;
    final isOnDevice = hasFile &&
        (ref
                .watch(myWalletOfflineDocumentIdsProvider(tripId))
                .asData
                ?.value
                .contains(document.id) ??
            false);
    final isDownloading =
        ref.watch(walletDownloadingIdsProvider).contains(document.id);
    // Hidden rather than disabled: downloading and deleting need the network
    // (a delete made offline would leave the stored file behind).
    final canDownload = hasFile && !isOnDevice && !isDownloading && !offline;
    final canDelete = !offline;
    return PopupMenuButton<WalletDocumentAction>(
      tooltip: l10n.commonMoreActions,
      icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
      onSelected: (action) async {
        switch (action) {
          case WalletDocumentAction.download:
            await downloadWalletDocument(
              context: context,
              ref: ref,
              tripId: tripId,
              document: document,
            );
          case WalletDocumentAction.removeFromDevice:
            await removeWalletDocumentFromDevice(
              context: context,
              ref: ref,
              tripId: tripId,
              document: document,
            );
          case WalletDocumentAction.edit:
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WalletDocumentFormPage.edit(
                  tripId: tripId,
                  document: document,
                ),
              ),
            );
          case WalletDocumentAction.delete:
            final deleted = await confirmAndDeleteWalletDocument(
              context: context,
              ref: ref,
              tripId: tripId,
              document: document,
            );
            if (deleted) onDeleted?.call();
        }
      },
      itemBuilder: (context) => [
        if (canDownload)
          PopupMenuItem(
            value: WalletDocumentAction.download,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(PhosphorIconsRegular.downloadSimple),
              title: Text(l10n.walletDownload),
            ),
          ),
        if (isOnDevice)
          PopupMenuItem(
            value: WalletDocumentAction.removeFromDevice,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(PhosphorIconsRegular.deviceMobileSlash),
              title: Text(l10n.walletRemoveFromDevice),
            ),
          ),
        PopupMenuItem(
          value: WalletDocumentAction.edit,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(PhosphorIconsRegular.pencilSimple),
            title: Text(l10n.commonEdit),
          ),
        ),
        if (canDelete)
          PopupMenuItem(
            value: WalletDocumentAction.delete,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(PhosphorIconsRegular.trash),
              title: Text(l10n.commonDelete),
            ),
          ),
      ],
    );
  }
}

Future<bool> confirmAndDeleteWalletDocument({
  required BuildContext context,
  required WidgetRef ref,
  required String tripId,
  required WalletDocument document,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  // The card disappears once deleted: use the container, not the widget ref.
  final container = ProviderScope.containerOf(context, listen: false);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.walletDeleteTitle),
      content: Text(l10n.walletDeleteBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.commonDelete),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  try {
    await container
        .read(walletRepositoryProvider)
        .deleteDocument(tripId: tripId, document: document);
    container.invalidate(myWalletOfflineDocumentIdsProvider(tripId));
    messenger.showSnackBar(SnackBar(content: Text(l10n.walletDocumentDeleted)));
    return true;
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
    );
    return false;
  }
}

Future<void> downloadWalletDocument({
  required BuildContext context,
  required WidgetRef ref,
  required String tripId,
  required WalletDocument document,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  // The container outlives this widget, which may be disposed meanwhile
  // (user leaves the page during the download).
  final container = ProviderScope.containerOf(context, listen: false);
  final downloading = container.read(walletDownloadingIdsProvider.notifier);
  downloading.add(document.id);
  try {
    await container
        .read(walletRepositoryProvider)
        .downloadForOffline(tripId: tripId, document: document);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.walletDownloadedForOffline)),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
    );
  } finally {
    downloading.remove(document.id);
    container.invalidate(myWalletOfflineDocumentIdsProvider(tripId));
  }
}

Future<void> removeWalletDocumentFromDevice({
  required BuildContext context,
  required WidgetRef ref,
  required String tripId,
  required WalletDocument document,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container
        .read(walletRepositoryProvider)
        .removeFromDevice(tripId: tripId, documentId: document.id);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.walletRemovedFromDevice)),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
    );
  } finally {
    container.invalidate(myWalletOfflineDocumentIdsProvider(tripId));
  }
}
