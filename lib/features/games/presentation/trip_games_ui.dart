import 'package:flutter/material.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/features/trips/presentation/trip_participants_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class TripGamesTabBar extends StatelessWidget {
  const TripGamesTabBar({
    super.key,
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.scaffoldBackground,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: NeonPalette.divider)),
        ),
        child: InkWell(
          onTap: () {},
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? NeonPalette.primary
                        : NeonPalette.onSurfaceVariant,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 0,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: NeonPalette.primary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripGamesIntroCallout extends StatelessWidget {
  const TripGamesIntroCallout({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: NeonPalette.gamesCalloutBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NeonPalette.gamesCalloutBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.sports_esports_outlined,
            size: 18,
            color: NeonPalette.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: NeonPalette.deep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TripGamesSearchField extends StatelessWidget {
  const TripGamesSearchField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.clearTooltip,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String clearTooltip;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: label,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: NeonPalette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NeonPalette.divider, width: 1.5),
              boxShadow: NeonPalette.elev1,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search,
                  size: 20,
                  color: NeonPalette.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(
                      fontSize: 16,
                      color: NeonPalette.deep,
                    ),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: const TextStyle(
                        fontSize: 16,
                        color: NeonPalette.outline,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    tooltip: clearTooltip,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class TripBoardGameCard extends StatelessWidget {
  const TripBoardGameCard({
    super.key,
    required this.title,
    required this.creatorBadge,
    required this.preview,
    required this.onTap,
  });

  final String title;
  final Widget creatorBadge;
  final Map<String, dynamic> preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.surface,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: NeonPalette.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              creatorBadge,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    letterSpacing: 0.1,
                    color: NeonPalette.deep,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: preview.isEmpty
                      ? const ColoredBox(
                          color: NeonPalette.surfaceHighest,
                          child: Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 26,
                              color: NeonPalette.outline,
                            ),
                          ),
                        )
                      : LinkPreviewThumbnail(
                          preview: preview,
                          size: 64,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripGamesEmptyState extends StatelessWidget {
  const TripGamesEmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sports_esports_outlined,
            size: 40,
            color: NeonPalette.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: NeonPalette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class TripGamesFab extends StatelessWidget {
  const TripGamesFab({
    super.key,
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FloatingActionButton(
        heroTag: 'trip_games_fab',
        tooltip: tooltip,
        onPressed: onPressed,
        elevation: 2,
        highlightElevation: 3,
        backgroundColor: NeonPalette.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.add, size: 26),
      ),
    );
  }
}

class TripBoardGameDialog extends StatefulWidget {
  const TripBoardGameDialog({
    super.key,
    this.gameName,
    this.gameUrl,
    required this.canEdit,
    required this.canDelete,
    required this.isCreate,
  });

  final String? gameName;
  final String? gameUrl;
  final bool canEdit;
  final bool canDelete;
  final bool isCreate;

  @override
  State<TripBoardGameDialog> createState() => _TripBoardGameDialogState();
}

class _TripBoardGameDialogState extends State<TripBoardGameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  bool _isEditingExisting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.gameName ?? '');
    _urlController = TextEditingController(text: widget.gameUrl ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  String? _validateUrl(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final trimmedValue = (value ?? '').trim();
    if (trimmedValue.isEmpty) return null;
    final uri = Uri.tryParse(trimmedValue);
    if (uri == null || !uri.isAbsolute) return l10n.linkInvalidExample;
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return l10n.activitiesLinkMustStartHttp;
    }
    return null;
  }

  Future<void> _openLink() async {
    final l10n = AppLocalizations.of(context)!;
    final parsed = Uri.tryParse(_urlController.text.trim());
    if (parsed == null || !parsed.isAbsolute) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkInvalid)),
      );
      return;
    }

    final didLaunch = await launchUrl(
      parsed,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!didLaunch && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkOpenImpossible)),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(l10n.tripGamesDeleteTitle),
        content: Text(l10n.tripGamesDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (!mounted || shouldDelete != true) return;
    Navigator.of(context).pop(const TripBoardGameDialogResult(delete: true));
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    Navigator.of(context).pop(
      TripBoardGameDialogResult(
        name: _nameController.text.trim(),
        linkUrl: _urlController.text.trim(),
      ),
    );
  }

  void _enterEditMode() => setState(() => _isEditingExisting = true);

  void _cancelExistingEdit() {
    _nameController.text = widget.gameName ?? '';
    _urlController.text = widget.gameUrl ?? '';
    setState(() => _isEditingExisting = false);
  }

  Widget _readOnlyField({
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: NeonPalette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: NeonPalette.surface,
            border: Border.all(color: NeonPalette.divider, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: NeonPalette.deep,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEdit = !widget.isCreate;
    final canEnterEditMode = isEdit && widget.canEdit;
    final isReadOnly = isEdit && !(_isEditingExisting && canEnterEditMode);
    final titleText =
        isEdit ? l10n.tripGamesEditTitle : l10n.tripGamesAddTitle;
    final effectiveName = _nameController.text.trim().isEmpty
        ? l10n.activitiesUntitled
        : _nameController.text.trim();
    final effectiveLink = _urlController.text.trim().isEmpty
        ? l10n.commonNotProvided
        : _urlController.text.trim();
    final hasLink = _urlController.text.trim().isNotEmpty;

    return Dialog(
      backgroundColor: NeonPalette.surface,
      elevation: 8,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isCreate)
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: NeonPalette.gamesIconTileBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.sports_esports_rounded,
                        size: 24,
                        color: NeonPalette.success,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        titleText,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: NeonPalette.deep,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  titleText,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    height: 1.27,
                    color: NeonPalette.deep,
                  ),
                ),
              const SizedBox(height: 20),
              if (isReadOnly)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _readOnlyField(
                      label: l10n.commonName,
                      value: effectiveName,
                    ),
                    const SizedBox(height: 12),
                    _readOnlyField(
                      label: l10n.tripGamesUrlLabel,
                      value: effectiveLink,
                      trailing: hasLink
                          ? IconButton(
                              tooltip: l10n.linkLabel,
                              onPressed: _openLink,
                              icon: const Icon(Icons.open_in_new, size: 20),
                              visualDensity: VisualDensity.compact,
                              color: NeonPalette.primary,
                            )
                          : null,
                    ),
                  ],
                )
              else
                Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TripParticipantsInputShell(
                        height: 52,
                        icon: Icons.extension_outlined,
                        child: TextFormField(
                          controller: _nameController,
                          style: const TextStyle(
                            fontSize: 16,
                            color: NeonPalette.deep,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return l10n.commonRequired;
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      TripParticipantsInputShell(
                        height: 52,
                        icon: Icons.link,
                        child: TextFormField(
                          controller: _urlController,
                          style: const TextStyle(
                            fontSize: 16,
                            color: NeonPalette.deep,
                          ),
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            hintText: 'https://…',
                            hintStyle: TextStyle(color: NeonPalette.outline),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          validator: _validateUrl,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isEdit && widget.canDelete)
                    IconButton(
                      tooltip: l10n.commonDelete,
                      onPressed: _confirmDelete,
                      icon: const Icon(Icons.delete_outline),
                      color: NeonPalette.accent,
                    ),
                  if (isReadOnly && canEnterEditMode)
                    IconButton(
                      tooltip: l10n.commonEdit,
                      onPressed: _enterEditMode,
                      icon: const Icon(Icons.edit_outlined),
                      color: NeonPalette.primary,
                    ),
                  tripParticipantsDialogButton(
                    context: context,
                    label: (isEdit && !isReadOnly)
                        ? l10n.commonCancel
                        : l10n.commonClose,
                    onPressed: () {
                      if (!isEdit || isReadOnly) {
                        Navigator.of(context).pop();
                        return;
                      }
                      _cancelExistingEdit();
                    },
                  ),
                  if (!isReadOnly)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: FilledButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(l10n.commonSave),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
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

class TripBoardGameDialogResult {
  const TripBoardGameDialogResult({
    this.name = '',
    this.linkUrl = '',
    this.delete = false,
  });

  final String name;
  final String linkUrl;
  final bool delete;
}
