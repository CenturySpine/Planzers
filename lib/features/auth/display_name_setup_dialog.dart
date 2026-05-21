import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/auth/data/display_name_length.dart';
import 'package:planerz/l10n/app_localizations.dart';

// Matches phone numbers: starts with '+' or digit, followed by 5+ digit/space/punctuation chars.
final _phoneRegex = RegExp(r'^[+\d][\d\s\-(). ]{5,}$');

bool accountNameNeedsSetup(String? name) {
  if (name == null || name.trim().isEmpty) return true;
  return _phoneRegex.hasMatch(name.trim());
}

/// Shows the display-name setup dialog. Returns true if the name was saved,
/// false if the user cancelled (caller must sign out).
Future<bool> showDisplayNameSetupDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DisplayNameSetupDialog(),
  ).then((result) => result ?? false);
}

class _DisplayNameSetupDialog extends ConsumerStatefulWidget {
  const _DisplayNameSetupDialog();

  @override
  ConsumerState<_DisplayNameSetupDialog> createState() =>
      _DisplayNameSetupDialogState();
}

class _DisplayNameSetupDialogState
    extends ConsumerState<_DisplayNameSetupDialog> {
  final _controller = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isValid => isDisplayNameLengthValid(_controller.text);

  Future<void> _save() async {
    final name = _controller.text.trim();
    setState(() => _isSaving = true);
    try {
      await ref.read(accountRepositoryProvider).updateAccountName(name);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('DisplayNameSetupDialog save error: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.profileNameDialogTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: kDisplayNameMaxLength,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          if (_isValid && !_isSaving) _save();
        },
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: l10n.profileNameDialogFieldLabel,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: (_isValid && !_isSaving) ? _save : null,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
