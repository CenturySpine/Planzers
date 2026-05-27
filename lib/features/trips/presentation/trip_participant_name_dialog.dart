import 'package:flutter/material.dart';
import 'package:planerz/features/auth/data/display_name_length.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
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

/// Resolves the display name chosen in [TripParticipantNameDialog].
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
  late final TextEditingController _nameController;
  late bool _useProfileName;
  late bool _isChild;

  bool get _profileOptionEnabled =>
      widget.isClaimed && widget.profileName != null;

  bool get _canSave {
    if (_useProfileName) {
      return _profileOptionEnabled;
    }
    return isDisplayNameLengthValid(_nameController.text);
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _useProfileName = widget.initialUseProfileName && _profileOptionEnabled;
    _isChild = widget.initialIsChild && !widget.isClaimed;
    _nameController.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
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

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(
      TripParticipantNameDialogResult(
        name: _nameController.text.trim(),
        useProfileName: _useProfileName,
        isChild: _isChild,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final useCustomName = !_useProfileName;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<bool>(
              groupValue: _useProfileName,
              onChanged: (value) {
                if (value == null) return;
                if (value && !_profileOptionEnabled) return;
                setState(() => _useProfileName = value);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ParticipantNameSourceOption(
                    title: l10n.tripParticipantsEditNameModeCustom,
                    icon: Icons.edit_outlined,
                    value: false,
                    selected: !_useProfileName,
                    onTap: () => setState(() => _useProfileName = false),
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
                        ? () => setState(() => _useProfileName = true)
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (useCustomName)
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.commonName,
                  border: const OutlineInputBorder(),
                  errorText: _customNameError,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (_canSave) _save();
                },
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      size: 22,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.profileName ?? '',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
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
                secondary: Text(
                  tripMemberChildLabelEmoji,
                  style: theme.textTheme.headlineSmall,
                ),
                title: Text(l10n.tripParticipantsIsChildLabel),
                subtitle: Text(l10n.tripParticipantsIsChildSubtitle),
                value: _isChild,
                onChanged: (value) => setState(() => _isChild = value),
              ),
            ],
          ],
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveOnTap = enabled ? onTap : null;
    final borderColor = selected
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    final foreground = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.38);

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : colorScheme.surface,
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
                color: enabled ? colorScheme.primary : colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: enabled
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
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
