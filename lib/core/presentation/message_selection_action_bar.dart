import 'dart:async';

import 'package:flutter/material.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Action bar shown at the top of a screen when a message/item is selected
/// (long-press pattern). Provides close, edit, delete and optional copy actions.
class MessageSelectionActionBar extends StatelessWidget {
  const MessageSelectionActionBar({
    super.key,
    required this.onClose,
    this.onEdit,
    this.onDelete,
    this.onCopy,
  });

  final VoidCallback onClose;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Material(
      elevation: 3,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.commonClose,
                onPressed: onClose,
              ),
              const Spacer(),
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: l10n.commonEdit,
                  onPressed: () => unawaited(onEdit!()),
                ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  tooltip: l10n.commonDelete,
                  onPressed: () => unawaited(onDelete!()),
                ),
              if (onCopy != null)
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: l10n.chatCopy,
                  onPressed: onCopy,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog for editing a short text. Returns the trimmed new text, or null if
/// the user cancelled. Displays a multi-line text field pre-filled with
/// [initialText].
class EditTextDialog extends StatefulWidget {
  const EditTextDialog({
    super.key,
    required this.initialText,
    required this.title,
    this.maxLength = 4000,
  });

  final String initialText;
  final String title;
  final int maxLength;

  @override
  State<EditTextDialog> createState() => _EditTextDialogState();
}

class _EditTextDialogState extends State<EditTextDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        maxLength: widget.maxLength,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final t = _controller.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(context, t);
          },
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
