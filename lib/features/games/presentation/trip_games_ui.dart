import 'package:planerz/app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/core/presentation/pz_components.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/features/trips/presentation/trip_participants_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class TripGamesIntroCallout extends StatelessWidget {
  const TripGamesIntroCallout({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PzCallout(
      tone: PzCalloutTone.brand,
      icon: PhosphorIconsRegular.diceFive,
      message: message,
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
          return TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, size: 20),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(PhosphorIconsRegular.x, size: 18),
                      tooltip: clearTooltip,
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
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
    this.subtitle,
  });

  final String title;
  final Widget creatorBadge;
  final Map<String, dynamic> preview;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final group = ActivityFilterGroup.loisirs;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: preview.isEmpty
                      ? ColoredBox(
                          color: group.filterLightBgColor,
                          child: Icon(
                            PhosphorIconsRegular.diceFive,
                            size: 22,
                            color: group.filterColor,
                          ),
                        )
                      : LinkPreviewThumbnail(preview: preview, size: 44),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          creatorBadge,
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(PhosphorIconsRegular.caretRight, color: AppTokens.outline),
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
    return PzEmptyState(icon: PhosphorIconsRegular.diceFive, title: message);
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
    return FloatingActionButton(
      heroTag: 'trip_games_fab',
      tooltip: tooltip,
      onPressed: onPressed,
      child: const Icon(PhosphorIconsRegular.plus, size: 26),
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
            color: AppTokens.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTokens.surface,
            border: Border.all(color: AppTokens.divider, width: 1.5),
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
                    color: AppTokens.deep,
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
      backgroundColor: AppTokens.surface,
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
                        color: AppTokens.gamesIconTileBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        PhosphorIconsRegular.gameController,
                        size: 24,
                        color: AppTokens.success,
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
                          color: AppTokens.deep,
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
                    color: AppTokens.deep,
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
                              icon: const Icon(PhosphorIconsRegular.arrowSquareOut, size: 20),
                              visualDensity: VisualDensity.compact,
                              color: AppTokens.primary,
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
                        icon: PhosphorIconsRegular.puzzlePiece,
                        child: TextFormField(
                          controller: _nameController,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppTokens.deep,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
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
                        icon: PhosphorIconsRegular.link,
                        child: TextFormField(
                          controller: _urlController,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppTokens.deep,
                          ),
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            hintText: 'https://…',
                            hintStyle: TextStyle(color: AppTokens.outline),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
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
                      icon: const Icon(PhosphorIconsRegular.trash),
                      color: AppTokens.error,
                    ),
                  if (isReadOnly && canEnterEditMode)
                    IconButton(
                      tooltip: l10n.commonEdit,
                      onPressed: _enterEditMode,
                      icon: const Icon(PhosphorIconsRegular.pencilSimple),
                      color: AppTokens.primary,
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
                        icon: const Icon(PhosphorIconsRegular.check, size: 18),
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
