import 'package:flutter/material.dart';
import 'package:planerz/features/auth/data/display_name_length.dart';
import 'package:planerz/features/trips/presentation/trip_create_neon_palette.dart';
import 'package:planerz/features/trips/presentation/trip_participant_name_dialog.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Néon-styled name presentation dialog for [TripCreatePage].
Future<TripParticipantNameDialogResult?> showTripCreateCreatorNameDialog({
  required BuildContext context,
  required String initialCustomName,
  required bool initialUseProfileName,
  required String? profileName,
}) {
  return showDialog<TripParticipantNameDialogResult>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.40),
    builder: (dialogContext) => _TripCreateCreatorNameDialog(
      initialCustomName: initialCustomName,
      initialUseProfileName: initialUseProfileName,
      profileName: profileName,
    ),
  );
}

class _TripCreateCreatorNameDialog extends StatefulWidget {
  const _TripCreateCreatorNameDialog({
    required this.initialCustomName,
    required this.initialUseProfileName,
    required this.profileName,
  });

  final String initialCustomName;
  final bool initialUseProfileName;
  final String? profileName;

  @override
  State<_TripCreateCreatorNameDialog> createState() =>
      _TripCreateCreatorNameDialogState();
}

class _TripCreateCreatorNameDialogState
    extends State<_TripCreateCreatorNameDialog> {
  late final TextEditingController _customNameController;
  late final FocusNode _customNameFocusNode;
  late bool _useProfileName;

  bool get _profileOptionEnabled =>
      isDisplayNameLengthValid(widget.profileName ?? '');

  bool get _canSave {
    if (_useProfileName) {
      return _profileOptionEnabled;
    }
    return isDisplayNameLengthValid(_customNameController.text);
  }

  @override
  void initState() {
    super.initState();
    _customNameController = TextEditingController(text: widget.initialCustomName);
    _customNameFocusNode = FocusNode();
    _useProfileName =
        widget.initialUseProfileName && _profileOptionEnabled;
    if (!_useProfileName) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _customNameFocusNode.requestFocus();
      });
    }
    _customNameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _customNameController.dispose();
    _customNameFocusNode.dispose();
    super.dispose();
  }

  void _selectCustom() {
    setState(() => _useProfileName = false);
    _customNameFocusNode.requestFocus();
  }

  void _selectProfile() {
    if (!_profileOptionEnabled) return;
    setState(() => _useProfileName = true);
  }

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(
      TripParticipantNameDialogResult(
        name: _customNameController.text.trim(),
        useProfileName: _useProfileName,
        isChild: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: TripCreateNeonPalette.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.tripParticipantsEditNameTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: TripCreateNeonPalette.deep,
                ),
              ),
              const SizedBox(height: 18),
              _NameOptionCard(
                selected: !_useProfileName,
                icon: Icons.edit_outlined,
                title: l10n.tripParticipantsEditNameModeCustom,
                onTap: _selectCustom,
              ),
              if (!_useProfileName) ...[
                const SizedBox(height: 10),
                _DialogInputShell(
                  focusNode: _customNameFocusNode,
                  child: TextField(
                    controller: _customNameController,
                    focusNode: _customNameFocusNode,
                    style: const TextStyle(
                      fontSize: 15,
                      color: TripCreateNeonPalette.deep,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.tripCreateCreatorNameCustomPlaceholder,
                      hintStyle: const TextStyle(
                        color: TripCreateNeonPalette.outline,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (_canSave) _save();
                    },
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _NameOptionCard(
                selected: _useProfileName,
                icon: Icons.badge_outlined,
                title: l10n.tripParticipantsEditNameModeProfile,
                subtitle: widget.profileName != null
                    ? l10n.tripParticipantsProfileNameDisplay(
                        widget.profileName!,
                      )
                    : l10n.tripParticipantsNoProfileNameHint,
                enabled: _profileOptionEnabled,
                onTap: _selectProfile,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      l10n.commonCancel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: TripCreateNeonPalette.text700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _canSave ? _save : null,
                    child: Text(
                      l10n.commonSave,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _canSave
                            ? TripCreateNeonPalette.primary
                            : TripCreateNeonPalette.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameOptionCard extends StatelessWidget {
  const _NameOptionCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? TripCreateNeonPalette.primary
        : TripCreateNeonPalette.divider;
    final borderWidth = selected ? 2.0 : 1.5;
    final padding = selected ? 13.0 : 14.0;

    return Material(
      color: selected
          ? TripCreateNeonPalette.nameOptionActiveBackground
          : TripCreateNeonPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: TripCreateNeonPalette.nameIconBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(
                    icon,
                    size: 20,
                    color: enabled
                        ? TripCreateNeonPalette.primary
                        : TripCreateNeonPalette.outline,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? TripCreateNeonPalette.deep
                            : TripCreateNeonPalette.outline,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: enabled
                              ? TripCreateNeonPalette.onSurfaceVariant
                              : TripCreateNeonPalette.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _NeonRadioIndicator(selected: selected && enabled),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeonRadioIndicator extends StatelessWidget {
  const _NeonRadioIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? TripCreateNeonPalette.primary
              : TripCreateNeonPalette.outline,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: TripCreateNeonPalette.primary,
                ),
              ),
            )
          : null,
    );
  }
}

class _DialogInputShell extends StatefulWidget {
  const _DialogInputShell({
    required this.child,
    required this.focusNode,
  });

  final Widget child;
  final FocusNode focusNode;

  @override
  State<_DialogInputShell> createState() => _DialogInputShellState();
}

class _DialogInputShellState extends State<_DialogInputShell> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: TripCreateNeonPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focused
              ? TripCreateNeonPalette.primary
              : TripCreateNeonPalette.divider,
          width: focused ? 2 : 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.edit_outlined,
            size: 18,
            color: focused
                ? TripCreateNeonPalette.primary
                : TripCreateNeonPalette.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

/// Tappable name summary card on the trip-create form.
class TripCreateCreatorNameField extends StatefulWidget {
  const TripCreateCreatorNameField({
    super.key,
    required this.displayName,
    required this.useProfileName,
    required this.enabled,
    required this.onTap,
  });

  final String? displayName;
  final bool useProfileName;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<TripCreateCreatorNameField> createState() =>
      _TripCreateCreatorNameFieldState();
}

class _TripCreateCreatorNameFieldState extends State<TripCreateCreatorNameField> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasValue = widget.displayName?.trim().isNotEmpty == true;
    final borderColor = _hovered && widget.enabled
        ? TripCreateNeonPalette.dateBorderSet
        : TripCreateNeonPalette.divider;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: TripCreateNeonPalette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: TripCreateNeonPalette.nameIconBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(
                      widget.useProfileName
                          ? Icons.badge_outlined
                          : Icons.edit_outlined,
                      size: 20,
                      color: TripCreateNeonPalette.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasValue
                            ? widget.displayName!.trim()
                            : l10n.tripCreateCreatorNameEmpty,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              hasValue ? FontWeight.w600 : FontWeight.w400,
                          color: hasValue
                              ? TripCreateNeonPalette.deep
                              : TripCreateNeonPalette.outline,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.useProfileName
                            ? l10n.tripCreateCreatorNameHintProfile
                            : l10n.tripCreateCreatorNameHintCustom,
                        style: const TextStyle(
                          fontSize: 12,
                          color: TripCreateNeonPalette.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TripCreateNeonPalette.nameEditPillBackground,
                  ),
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: TripCreateNeonPalette.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
