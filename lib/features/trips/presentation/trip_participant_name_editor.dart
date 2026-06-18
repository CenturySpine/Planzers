import 'package:flutter/material.dart';
import 'package:planerz/features/auth/data/display_name_length.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/trips/presentation/trip_participants_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripParticipantNameDialogResult {
  const TripParticipantNameDialogResult({
    required this.name,
    required this.useProfileName,
    required this.isChild,
  });

  final String name;
  final bool useProfileName;
  final bool isChild;
}

/// Resolves the display name chosen in [TripParticipantNameEditor].
String? resolveTripParticipantDisplayName({
  required TripParticipantNameDialogResult result,
  required String? profileName,
}) {
  if (result.useProfileName) {
    final fromProfile = profileName?.trim();
    if (fromProfile == null || fromProfile.isEmpty) return null;
    return fromProfile;
  }
  final custom = result.name.trim();
  if (!isDisplayNameLengthValid(custom)) return null;
  return custom;
}

class TripParticipantNameEditor extends StatefulWidget {
  const TripParticipantNameEditor({
    super.key,
    required this.initialName,
    required this.initialUseProfileName,
    required this.initialIsChild,
    required this.isClaimed,
    required this.profileName,
    this.showSaveButton = true,
    this.onSave,
    this.onCanSaveChanged,
  });

  final String initialName;
  final bool initialUseProfileName;
  final bool initialIsChild;
  final bool isClaimed;
  final String? profileName;
  final bool showSaveButton;
  final Future<void> Function(TripParticipantNameDialogResult result)? onSave;
  final ValueChanged<bool>? onCanSaveChanged;

  @override
  TripParticipantNameEditorState createState() =>
      TripParticipantNameEditorState();
}

class TripParticipantNameEditorState extends State<TripParticipantNameEditor> {
  late final TextEditingController _nameController;
  late bool _useProfileName;
  late bool _isChild;
  bool _isSaving = false;

  bool get canSave {
    if (_isSaving) return false;
    if (_useProfileName) {
      return _profileOptionEnabled;
    }
    return isDisplayNameLengthValid(_nameController.text);
  }

  bool get _profileOptionEnabled =>
      widget.isClaimed && widget.profileName != null;

  bool _resolveUseProfileNameFromWidget() {
    if (!widget.isClaimed) return false;
    if (widget.initialUseProfileName) return true;
    return _profileOptionEnabled && widget.initialName.trim().isEmpty;
  }

  void _syncFieldsFromWidget(TripParticipantNameEditor oldWidget) {
    if (_isSaving) return;

    final resolvedUseProfileName = _resolveUseProfileNameFromWidget();
    final participantFieldsChanged = oldWidget.initialUseProfileName !=
            widget.initialUseProfileName ||
        oldWidget.profileName != widget.profileName ||
        oldWidget.isClaimed != widget.isClaimed ||
        oldWidget.initialIsChild != widget.initialIsChild;

    var needsRebuild = false;
    if (participantFieldsChanged &&
        _useProfileName != resolvedUseProfileName) {
      _useProfileName = resolvedUseProfileName;
      needsRebuild = true;
    }

    if (oldWidget.initialName != widget.initialName &&
        _nameController.text.trim() == oldWidget.initialName.trim()) {
      _nameController.text = widget.initialName;
      needsRebuild = true;
    }

    final resolvedIsChild = widget.initialIsChild && !widget.isClaimed;
    if (oldWidget.initialIsChild != widget.initialIsChild &&
        _isChild != resolvedIsChild) {
      _isChild = resolvedIsChild;
      needsRebuild = true;
    }

    if (needsRebuild) {
      setState(() {});
      widget.onCanSaveChanged?.call(canSave);
    }
  }

  TripParticipantNameDialogResult buildResult() {
    return TripParticipantNameDialogResult(
      name: _nameController.text.trim(),
      useProfileName: _useProfileName,
      isChild: _isChild,
    );
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _useProfileName = _resolveUseProfileNameFromWidget();
    _isChild = widget.initialIsChild && !widget.isClaimed;
    _nameController.addListener(_onNameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCanSaveChanged?.call(canSave);
    });
  }

  @override
  void didUpdateWidget(covariant TripParticipantNameEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFieldsFromWidget(oldWidget);
  }

  void _onNameChanged() {
    if (!mounted) return;
    setState(() {});
    widget.onCanSaveChanged?.call(canSave);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  String? get _profileOptionSubtitle {
    final l10n = AppLocalizations.of(context)!;
    if (!widget.isClaimed) {
      return l10n.tripParticipantsEditNameProfileRequiresClaim;
    }
    if (widget.profileName != null) {
      return l10n.tripParticipantsProfileNameDisplay(widget.profileName!);
    }
    return l10n.tripParticipantsNoProfileNameHint;
  }

  String? get _customNameError {
    if (_useProfileName) return null;
    if (isDisplayNameLengthValid(_nameController.text)) return null;
    return AppLocalizations.of(context)!.inviteBypassFirstNameInvalid;
  }

  Future<void> _save() async {
    if (!canSave || widget.onSave == null) return;
    setState(() => _isSaving = true);
    widget.onCanSaveChanged?.call(canSave);
    try {
      await widget.onSave!(buildResult());
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        widget.onCanSaveChanged?.call(canSave);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final useCustomName = !_useProfileName;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<bool>(
          groupValue: _useProfileName,
          onChanged: (value) {
            if (value == null) return;
            if (value && !_profileOptionEnabled) return;
            setState(() => _useProfileName = value);
            widget.onCanSaveChanged?.call(canSave);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ParticipantNameSourceOption(
                title: l10n.tripParticipantsEditNameModeCustom,
                icon: Icons.edit_outlined,
                value: false,
                selected: !_useProfileName,
                onTap: () {
                  setState(() => _useProfileName = false);
                  widget.onCanSaveChanged?.call(canSave);
                },
              ),
              const SizedBox(height: 12),
              _ParticipantNameSourceOption(
                title: l10n.tripParticipantsEditNameModeProfile,
                icon: Icons.badge_outlined,
                value: true,
                selected: _useProfileName,
                enabled: _profileOptionEnabled,
                subtitle: _profileOptionSubtitle,
                onTap: _profileOptionEnabled
                    ? () {
                        setState(() => _useProfileName = true);
                        widget.onCanSaveChanged?.call(canSave);
                      }
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (useCustomName)
          TextField(
            controller: _nameController,
            autofocus: !widget.showSaveButton,
            decoration: InputDecoration(
              labelText: l10n.commonName,
              border: const OutlineInputBorder(),
              errorText: _customNameError,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (canSave) _save();
            },
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: NeonPalette.participantsAvatarBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NeonPalette.divider),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.badge_outlined,
                  size: 22,
                  color: NeonPalette.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.profileName ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: NeonPalette.deep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (!widget.isClaimed) ...[
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const TripChildCareIcon(),
            title: Text(l10n.tripParticipantsIsChildLabel),
            subtitle: Text(l10n.tripParticipantsIsChildSubtitle),
            value: _isChild,
            onChanged: (value) => setState(() => _isChild = value),
          ),
        ],
        if (widget.showSaveButton) ...[
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: canSave ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.commonSave),
            ),
          ),
        ],
      ],
    );

    if (!widget.showSaveButton) {
      return content;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.tripParticipantsEditNameTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: NeonPalette.deep,
              ),
            ),
            const SizedBox(height: 16),
            content,
          ],
        ),
      ),
    );
  }
}

class _ParticipantNameSourceOption extends StatelessWidget {
  const _ParticipantNameSourceOption({
    required this.title,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final IconData icon;
  final bool value;
  final bool selected;
  final VoidCallback? onTap;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final effectiveOnTap = enabled ? onTap : null;
    final borderColor = selected ? NeonPalette.primary : NeonPalette.divider;
    final foreground = enabled
        ? NeonPalette.deep
        : NeonPalette.deep.withValues(alpha: 0.38);

    return Material(
      color: selected ? NeonPalette.nameOptionActiveBackground : NeonPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: borderColor,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: effectiveOnTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 22,
                color: enabled ? NeonPalette.primary : NeonPalette.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: enabled
                              ? NeonPalette.onSurfaceVariant
                              : NeonPalette.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Radio<bool>(
                value: value,
                enabled: enabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
