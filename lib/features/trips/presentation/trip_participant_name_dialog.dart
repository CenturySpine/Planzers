import 'package:flutter/material.dart';
import 'package:planerz/features/trips/presentation/trip_participant_name_editor.dart';
import 'package:planerz/l10n/app_localizations.dart';

export 'package:planerz/features/trips/presentation/trip_participant_name_editor.dart'
    show TripParticipantNameDialogResult, resolveTripParticipantDisplayName;

class TripParticipantNameDialog extends StatefulWidget {
  const TripParticipantNameDialog({
    super.key,
    required this.initialName,
    required this.initialUseProfileName,
    required this.initialIsChild,
    required this.isClaimed,
    required this.profileName,
  });

  final String initialName;
  final bool initialUseProfileName;
  final bool initialIsChild;
  final bool isClaimed;
  final String? profileName;

  @override
  State<TripParticipantNameDialog> createState() =>
      _TripParticipantNameDialogState();
}

class _TripParticipantNameDialogState extends State<TripParticipantNameDialog> {
  final GlobalKey<TripParticipantNameEditorState> _editorKey =
      GlobalKey<TripParticipantNameEditorState>();
  bool _canSave = false;

  void _save() {
    final editor = _editorKey.currentState;
    if (editor == null || !editor.canSave) return;
    Navigator.of(context).pop(editor.buildResult());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      contentPadding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text(l10n.tripParticipantsEditNameTitle),
      content: SizedBox(
        width: 400,
        child: TripParticipantNameEditor(
          key: _editorKey,
          initialName: widget.initialName,
          initialUseProfileName: widget.initialUseProfileName,
          initialIsChild: widget.initialIsChild,
          isClaimed: widget.isClaimed,
          profileName: widget.profileName,
          showSaveButton: false,
          onCanSaveChanged: (canSave) {
            if (_canSave != canSave) {
              setState(() => _canSave = canSave);
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
