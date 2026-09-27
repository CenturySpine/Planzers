import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/features/wallet/data/wallet_repository.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_form_page.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_ui.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_viewer_page.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// "Mes documents" — a personal, per-traveler document wallet (tickets,
/// booking confirmations, IDs...), visible only to its owner.
class TripWalletPage extends ConsumerWidget {
  const TripWalletPage({super.key, required this.tripId});

  final String tripId;

  Future<void> _addFile(
    BuildContext context,
    int currentCount,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (currentCount >= walletMaxDocumentsPerTrip) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.walletLimitReached(walletMaxDocumentsPerTrip)),
        ),
      );
      return;
    }
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final documentsAsync = ref.watch(myWalletDocumentsStreamProvider(tripId));
    final documentCount = documentsAsync.asData?.value.length ?? 0;

    return Theme(
      data: AppTokens.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: AppTokens.scaffoldBackground,
        appBar: AppBar(
          title: Text(l10n.tripWalletPageTitle),
          actions: [
            if (documentsAsync.hasValue)
              IconButton(
                icon: const Icon(PhosphorIconsRegular.plus),
                tooltip: l10n.tripWalletAddDocument,
                onPressed: () => _addFile(context, documentCount),
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
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: documents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _WalletDocumentCard(
                tripId: tripId,
                document: documents[index],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WalletDocumentCard extends StatelessWidget {
  const _WalletDocumentCard({required this.tripId, required this.document});

  final String tripId;
  final WalletDocument document;

  @override
  Widget build(BuildContext context) {
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
        trailing: WalletDocumentActionsButton(
          tripId: tripId,
          document: document,
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
