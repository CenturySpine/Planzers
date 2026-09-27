import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/core/network/connectivity_provider.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/features/wallet/data/wallet_repository.dart';
import 'package:planerz/features/wallet/presentation/wallet_barcode_view.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Keyed by storage path (a stable value) so rebuilds reuse the same request.
final _walletFileUrlProvider =
    FutureProvider.autoDispose.family<String, String>((ref, storagePath) {
  return ref.watch(walletRepositoryProvider).fileDownloadUrl(storagePath);
});

/// Full-screen view of one document. Follows the live document so an edit
/// made from the menu shows immediately; closes itself once deleted.
class WalletDocumentViewerPage extends ConsumerWidget {
  const WalletDocumentViewerPage({
    super.key,
    required this.tripId,
    required this.documentId,
  });

  final String tripId;
  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents =
        ref.watch(myWalletDocumentsStreamProvider(tripId)).asData?.value;
    final document =
        documents?.where((doc) => doc.id == documentId).firstOrNull;

    return Theme(
      data: AppTokens.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: AppTokens.scaffoldBackground,
        appBar: AppBar(
          title: Text(document?.name ?? ''),
          actions: [
            if (document != null)
              WalletDocumentActionsButton(
                tripId: tripId,
                document: document,
                onDeleted: () => Navigator.of(context).maybePop(),
              ),
          ],
        ),
        body: document == null
            ? const Center(child: CircularProgressIndicator())
            : _WalletDocumentContent(tripId: tripId, document: document),
      ),
    );
  }
}

class _WalletDocumentContent extends ConsumerWidget {
  const _WalletDocumentContent({required this.tripId, required this.document});

  final String tripId;
  final WalletDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final barcode = document.barcode;
    if (barcode != null) {
      return ColoredBox(
        color: Colors.white,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: WalletBarcodeView(barcode: barcode),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  barcode.payload,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final file = document.file;
    if (file == null) return const SizedBox.shrink();

    final key = (
      tripId: tripId,
      documentId: document.id,
      storagePath: file.storagePath,
    );
    final bytesAsync = ref.watch(_walletFileBytesProvider(key));
    return bytesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ViewerMessage(
        icon: error is WalletUnavailableOfflineException
            ? PhosphorIconsRegular.cloudSlash
            : PhosphorIconsRegular.warningCircle,
        text: error is WalletUnavailableOfflineException
            ? l10n.walletUnavailableOffline
            : l10n.walletOpenFailed,
        onRetry: () => ref.invalidate(_walletFileBytesProvider(key)),
      ),
      data: (bytes) {
        if (file.isPdf) {
          return PdfViewer.data(bytes, sourceName: 'wallet-${document.id}');
        }
        return InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              // e.g. HEIC outside Safari: let the browser/OS handle the file.
              errorBuilder: (context, _, __) => _OpenFilePanel(
                document: document,
              ),
            ),
          ),
        );
      },
    );
  }
}

typedef _WalletFileKey = ({
  String tripId,
  String documentId,
  String storagePath,
});

/// Stable string key: list updates (renames, other documents) do not reload
/// the file.
final _walletFileBytesProvider =
    FutureProvider.autoDispose.family<Uint8List, _WalletFileKey>((ref, key) {
  // Read, not watched: a document already shown must not reload (and fail)
  // when the connection drops; "Réessayer" re-reads after reconnecting.
  final offline = ref.read(isOfflineProvider);
  return ref.watch(walletRepositoryProvider).readFileBytes(
        tripId: key.tripId,
        documentId: key.documentId,
        storagePath: key.storagePath,
        allowNetwork: !offline,
      );
});

class _ViewerMessage extends StatelessWidget {
  const _ViewerMessage({
    required this.icon,
    required this.text,
    required this.onRetry,
  });

  final IconData icon;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
          ],
        ),
      ),
    );
  }
}

/// For images the app cannot render itself (e.g. HEIC outside Safari): the
/// URL is resolved beforehand so the tap opens it directly, which keeps
/// browsers from blocking the new tab as an unsolicited popup. Online only.
class _OpenFilePanel extends ConsumerWidget {
  const _OpenFilePanel({required this.document});

  final WalletDocument document;

  Future<void> _open(BuildContext context, String url) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.walletOpenFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final file = document.file;
    final resolvedUrl = file == null
        ? null
        : ref.watch(_walletFileUrlProvider(file.storagePath)).asData?.value;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(document.category.icon, size: 56),
            const SizedBox(height: 12),
            Text(
              file?.originalFileName ?? document.name,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (resolvedUrl == null)
              Text(l10n.walletOpenFailed)
            else
              FilledButton.icon(
                onPressed: () => _open(context, resolvedUrl),
                icon: const Icon(PhosphorIconsRegular.arrowSquareOut),
                label: Text(l10n.walletOpenFile),
              ),
          ],
        ),
      ),
    );
  }
}
