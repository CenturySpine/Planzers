import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/features/wallet/data/wallet_document_category.dart';
import 'package:planerz/features/wallet/data/wallet_repository.dart';
import 'package:planerz/features/wallet/presentation/wallet_barcode_view.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Full-screen form to name and categorise a document: a file just picked
/// (uploaded on save), a code just scanned, or an existing document.
class WalletDocumentFormPage extends ConsumerStatefulWidget {
  const WalletDocumentFormPage.create({
    super.key,
    required this.tripId,
    required Uint8List this.fileBytes,
    required String this.fileName,
  })  : document = null,
        barcode = null;

  const WalletDocumentFormPage.createBarcode({
    super.key,
    required this.tripId,
    required WalletBarcode this.barcode,
  })  : document = null,
        fileBytes = null,
        fileName = null;

  const WalletDocumentFormPage.edit({
    super.key,
    required this.tripId,
    required WalletDocument this.document,
  })  : fileBytes = null,
        fileName = null,
        barcode = null;

  final String tripId;
  final WalletDocument? document;
  final Uint8List? fileBytes;
  final String? fileName;
  final WalletBarcode? barcode;

  @override
  ConsumerState<WalletDocumentFormPage> createState() =>
      _WalletDocumentFormPageState();
}

class _WalletDocumentFormPageState
    extends ConsumerState<WalletDocumentFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late WalletDocumentCategory _category;
  DateTime? _eventDate;
  bool _saving = false;
  double? _uploadProgress;

  bool get _isEdit => widget.document != null;

  @override
  void initState() {
    super.initState();
    final document = widget.document;
    _nameController = TextEditingController(
      text: document?.name ?? _nameFromFileName(widget.fileName ?? ''),
    );
    _category = document?.category ?? WalletDocumentCategory.other;
    _eventDate = document?.eventDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static String _nameFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final trimmed = base.trim();
    return trimmed.length > walletMaxNameLength
        ? trimmed.substring(0, walletMaxNameLength)
        : trimmed;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    setState(() => _eventDate = picked);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repository = ref.read(walletRepositoryProvider);
    setState(() {
      _saving = true;
      _uploadProgress = null;
    });
    try {
      final document = widget.document;
      if (document != null) {
        await repository.updateDocumentMetadata(
          tripId: widget.tripId,
          documentId: document.id,
          name: _nameController.text,
          category: _category,
          eventDate: _eventDate,
        );
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.walletDocumentUpdated)),
        );
      } else if (widget.barcode != null) {
        await repository.addBarcodeDocument(
          tripId: widget.tripId,
          name: _nameController.text,
          category: _category,
          eventDate: _eventDate,
          barcode: widget.barcode!,
        );
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.walletDocumentAdded)),
        );
      } else {
        await repository.addFileDocument(
          tripId: widget.tripId,
          name: _nameController.text,
          category: _category,
          eventDate: _eventDate,
          bytes: widget.fileBytes!,
          originalFileName: widget.fileName!,
          onUploadProgress: (progress) {
            if (mounted) setState(() => _uploadProgress = progress);
          },
        );
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.walletDocumentAdded)),
        );
      }
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      final message = switch (error) {
        WalletUnsupportedFileException() => l10n.walletFileUnsupported,
        WalletFileTooLargeException() => l10n.walletFileTooLarge,
        _ => l10n.commonErrorWithDetails(error.toString()),
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final eventDate = _eventDate;
    final fileName = widget.document?.file?.originalFileName ?? widget.fileName;
    final barcode = widget.barcode ?? widget.document?.barcode;

    return Theme(
      data: AppTokens.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: AppTokens.scaffoldBackground,
        appBar: AppBar(
          title: Text(
            _isEdit ? l10n.walletFormEditTitle : l10n.walletFormCreateTitle,
          ),
          actions: [
            IconButton(
              tooltip: l10n.commonSave,
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsRegular.check),
            ),
          ],
          bottom: _saving && !_isEdit && widget.barcode == null
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(value: _uploadProgress),
                )
              : null,
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              if (fileName != null && fileName.isNotEmpty) ...[
                Card(
                  child: ListTile(
                    leading: Icon(_category.icon),
                    title: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (barcode != null) ...[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: WalletBarcodeView(barcode: barcode),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameController,
                enabled: !_saving,
                maxLength: walletMaxNameLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.commonName),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? l10n.commonRequired
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<WalletDocumentCategory>(
                initialValue: _category,
                decoration:
                    InputDecoration(labelText: l10n.walletFormCategoryLabel),
                items: [
                  for (final category in WalletDocumentCategory.values)
                    DropdownMenuItem(
                      value: category,
                      child: Row(
                        children: [
                          Icon(category.icon, size: 20),
                          const SizedBox(width: 12),
                          Text(category.label(l10n)),
                        ],
                      ),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _category = value);
                      },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(PhosphorIconsRegular.calendarBlank),
                title: Text(l10n.commonDate),
                subtitle: eventDate == null
                    ? null
                    : Text(formatWalletDate(context, eventDate)),
                onTap: _saving ? null : _pickDate,
                trailing: eventDate == null || _saving
                    ? null
                    : IconButton(
                        tooltip: l10n.walletFormClearDate,
                        icon: const Icon(PhosphorIconsRegular.x),
                        onPressed: () => setState(() => _eventDate = null),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
