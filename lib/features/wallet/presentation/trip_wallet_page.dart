import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/core/network/connectivity_provider.dart';
import 'package:planerz/core/presentation/pz_components.dart';
import 'package:planerz/features/trips/data/trip_lifecycle.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/wallet/data/wallet_barcode_decoder.dart';
import 'package:planerz/features/wallet/data/wallet_pdf_barcode_decoder.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/features/wallet/data/wallet_repository.dart';
import 'package:planerz/features/wallet/presentation/wallet_barcode_scan_page.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_form_page.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_ui.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_viewer_page.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// "Mes documents" — a personal, per-traveler document wallet (tickets,
/// booking confirmations, IDs...), visible only to its owner.
class TripWalletPage extends ConsumerWidget {
  const TripWalletPage({super.key, required this.tripId});

  final String tripId;

  bool _checkLimit(BuildContext context, int currentCount) {
    if (currentCount < walletMaxDocumentsPerTrip) return true;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.walletLimitReached(walletMaxDocumentsPerTrip)),
      ),
    );
    return false;
  }

  Future<void> _scanCode(BuildContext context, int currentCount) async {
    if (!_checkLimit(context, currentCount)) return;
    final navigator = Navigator.of(context);
    final barcode = await navigator.push<WalletBarcode>(
      MaterialPageRoute(builder: (_) => const WalletBarcodeScanPage()),
    );
    if (barcode == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => WalletDocumentFormPage.createBarcode(
          tripId: tripId,
          barcode: barcode,
        ),
      ),
    );
  }

  Future<void> _addFile(
    BuildContext context,
    int currentCount,
  ) async {
    if (!_checkLimit(context, currentCount)) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: walletContentTypeByExtension.keys.toList(),
    );
    if (picked == null) return;
    if (!walletContentTypeByExtension
        .containsKey(walletFileExtension(picked.name))) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.walletFileUnsupported)));
      return;
    }
    final size = await picked.length();
    if (size != null && size > walletMaxFileSizeBytes) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.walletFileTooLarge)));
      return;
    }
    final bytes = await picked.readAsBytes();
    if (bytes.lengthInBytes > walletMaxFileSizeBytes) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.walletFileTooLarge)));
      return;
    }
    // A screenshot, photo or PDF of a ticket: offer to keep only its code,
    // which is lighter and redrawn sharp for the inspector's reader.
    final contentType =
        walletContentTypeByExtension[walletFileExtension(picked.name)]!;
    if (context.mounted) {
      final barcode = await _detectBarcode(context, bytes, contentType, picked.path);
      if (barcode != null && context.mounted) {
        final saveCode = await _askSaveCodeOnly(context);
        if (saveCode == null) return;
        if (saveCode) {
          await navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => WalletDocumentFormPage.createBarcode(
                tripId: tripId,
                barcode: barcode,
              ),
            ),
          );
          return;
        }
      }
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => WalletDocumentFormPage.create(
          tripId: tripId,
          fileBytes: bytes,
          fileName: picked.name,
        ),
      ),
    );
  }

  /// Decoding a large screenshot can take a moment: block the page meanwhile.
  Future<WalletBarcode?> _detectBarcode(
    BuildContext context,
    Uint8List bytes,
    String contentType,
    String? filePath,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      if (contentType == 'application/pdf') {
        return await decodeWalletBarcodeFromPdf(bytes);
      }
      return await decodeWalletBarcodeFromImage(
        bytes: bytes,
        contentType: contentType,
        filePath: filePath,
      );
    } finally {
      navigator.pop();
    }
  }

  /// true: keep only the code; false: keep the image; null: cancelled.
  Future<bool?> _askSaveCodeOnly(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.walletCodeDetectedTitle),
        content: Text(l10n.walletCodeDetectedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.walletCodeDetectedKeepFile),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.walletCodeDetectedSaveCode),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final documentsAsync = ref.watch(myWalletDocumentsStreamProvider(tripId));
    final documentCount = documentsAsync.asData?.value.length ?? 0;
    // Adding needs the network (upload, server write): hidden offline.
    final offline = ref.watch(isOfflineProvider);
    final trip = ref.watch(tripStreamProvider(tripId)).asData?.value;
    // Ended trip: documents are deleted by the daily job 60 days after the
    // trip's last day; nothing more is added once that day is reached.
    final deletionDaysLeft =
        trip == null ? null : daysUntilTripDocumentsDeletion(trip, DateTime.now());
    final deletionDue = deletionDaysLeft == 0;

    return Theme(
      data: AppTokens.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: AppTokens.scaffoldBackground,
        appBar: AppBar(
          title: Text(l10n.tripWalletPageTitle),
          actions: [
            if (documentsAsync.hasValue && !offline && !deletionDue)
              PopupMenuButton<_AddAction>(
                icon: const Icon(PhosphorIconsRegular.plus),
                tooltip: l10n.tripWalletAddDocument,
                onSelected: (action) => switch (action) {
                  _AddAction.importFile => _addFile(context, documentCount),
                  _AddAction.scanCode => _scanCode(context, documentCount),
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _AddAction.importFile,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(PhosphorIconsRegular.folderPlus),
                      title: Text(l10n.walletAddImportFile),
                    ),
                  ),
                  PopupMenuItem(
                    value: _AddAction.scanCode,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(PhosphorIconsRegular.qrCode),
                      title: Text(l10n.walletAddScanCode),
                    ),
                  ),
                ],
              ),
          ],
        ),
        body: documentsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l10n.commonErrorWithDetails(error.toString())),
            ),
          ),
          data: (documents) {
            if (documents.isEmpty) {
              return Center(child: Text(l10n.walletEmpty));
            }
            final hasFiles = documents.any((document) => document.file != null);
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              children: [
                if (deletionDaysLeft != null) ...[
                  PzCallout(
                    tone: PzCalloutTone.warning,
                    icon: PhosphorIconsRegular.trash,
                    message: l10n.walletAutoDeletionNotice(deletionDaysLeft),
                  ),
                  const SizedBox(height: 12),
                ],
                if (hasFiles) ...[
                  PzCallout(
                    tone: PzCalloutTone.info,
                    message: l10n.walletOfflineHint,
                  ),
                  const SizedBox(height: 16),
                ],
                for (final (index, document) in documents.indexed) ...[
                  if (index > 0) const SizedBox(height: 12),
                  _WalletDocumentCard(tripId: tripId, document: document),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _AddAction { importFile, scanCode }

class _WalletDocumentCard extends ConsumerWidget {
  const _WalletDocumentCard({required this.tripId, required this.document});

  final String tripId;
  final WalletDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isDownloading =
        ref.watch(walletDownloadingIdsProvider).contains(document.id);
    final isOnDevice = document.file != null &&
        (ref
                .watch(myWalletOfflineDocumentIdsProvider(tripId))
                .asData
                ?.value
                .contains(document.id) ??
            false);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: ActivityFilterGroup.trajets.filterLightBgColor,
          child: Icon(
            document.category.icon,
            color: ActivityFilterGroup.trajets.filterInkColor,
          ),
        ),
        title: Text(document.name),
        subtitle: Text(walletDocumentSubtitle(context, document)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDownloading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (isOnDevice)
              Tooltip(
                message: l10n.walletAvailableOffline,
                child: const Icon(PhosphorIconsRegular.cloudCheck, size: 20),
              ),
            WalletDocumentActionsButton(tripId: tripId, document: document),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WalletDocumentViewerPage(
              tripId: tripId,
              documentId: document.id,
            ),
          ),
        ),
      ),
    );
  }
}
