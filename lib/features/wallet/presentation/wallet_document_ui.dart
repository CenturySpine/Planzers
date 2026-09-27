import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/app_icons.dart';
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

enum WalletDocumentAction { edit, delete }

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
    return PopupMenuButton<WalletDocumentAction>(
      tooltip: l10n.commonMoreActions,
      icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
      onSelected: (action) async {
        switch (action) {
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
        PopupMenuItem(
          value: WalletDocumentAction.edit,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(PhosphorIconsRegular.pencilSimple),
            title: Text(l10n.commonEdit),
          ),
        ),
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
    await ref
        .read(walletRepositoryProvider)
        .deleteDocument(tripId: tripId, document: document);
    messenger.showSnackBar(SnackBar(content: Text(l10n.walletDocumentDeleted)));
    return true;
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
    );
    return false;
  }
}
