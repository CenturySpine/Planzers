import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/games/data/trip_board_game.dart';
import 'package:planerz/features/games/data/trip_games_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class TripGamesPage extends ConsumerStatefulWidget {
  const TripGamesPage({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripGamesPage> createState() => _TripGamesPageState();
}

class _TripGamesPageState extends ConsumerState<TripGamesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _searchController = TextEditingController()
      ..addListener(() {
        final nextQuery = _searchController.text.trim();
        if (nextQuery == _searchQuery) return;
        setState(() => _searchQuery = nextQuery);
      });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openBoardGameDialog({
    required String tripId,
    required bool canEdit,
    required bool canDelete,
    TripBoardGame? game,
  }) async {
    final action = await showDialog<_BoardGameDialogAction>(
      context: context,
      builder: (context) => _BoardGameDialog(
        game: game,
        canEdit: canEdit,
        canDelete: canDelete,
      ),
    );
    if (!mounted || action == null) return;

    try {
      if (action.delete && game != null) {
        await ref.read(tripGamesRepositoryProvider).deleteBoardGame(
              tripId: tripId,
              gameId: game.id,
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.tripGamesDeleted)),
        );
        return;
      }

      if (game == null) {
        await ref.read(tripGamesRepositoryProvider).addBoardGame(
              tripId: tripId,
              name: action.name,
              linkUrl: action.linkUrl,
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.tripGamesAdded)),
        );
        return;
      }

      await ref.read(tripGamesRepositoryProvider).updateBoardGame(
            tripId: tripId,
            gameId: game.id,
            name: action.name,
            linkUrl: action.linkUrl,
            resetPreview: action.linkUrl.trim() != game.linkUrl.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.tripGamesUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!
              .commonErrorWithDetails(e.toString())),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));
    final gamesAsync = ref.watch(tripBoardGamesStreamProvider(widget.tripId));
    final currentUserId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.tripGamesTitle)),
            body: Center(child: Text(l10n.tripNotFound)),
          );
        }
        final currentRole =
            resolveTripPermissionRole(trip: trip, userId: currentUserId);
        final canAdminEdit = isTripRoleAllowed(
          currentRole: currentRole,
          minRole: TripPermissionRole.admin,
        );

        return gamesAsync.when(
          data: (games) {
            final normalizedSearchQuery = _searchQuery.toLowerCase();
            final filteredGames = normalizedSearchQuery.isEmpty
                ? games
                : games
                    .where((game) =>
                        game.name.toLowerCase().contains(normalizedSearchQuery))
                    .toList(growable: false);
            final creatorIds = games
                .map((game) => game.createdBy.trim())
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList();
            final creatorIdsKey = stableUsersIdsKey(creatorIds);
            final usersById = creatorIdsKey.isEmpty
                ? const <String, Map<String, dynamic>>{}
                : ref
                        .watch(usersDataByIdsKeyStreamProvider(creatorIdsKey))
                        .asData
                        ?.value ??
                    const <String, Map<String, dynamic>>{};

            return Scaffold(
              appBar: AppBar(
                title: Text(l10n.tripGamesTitle),
                bottom: TabBar(
                  controller: _tabController,
                  tabs: [Tab(text: l10n.tripBoardGamesTab)],
                ),
              ),
              body: TabBarView(
                controller: _tabController,
                children: [
                  ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                    itemCount: filteredGames.length + 2,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Text(
                          l10n.tripGamesIntro,
                          style: Theme.of(context).textTheme.bodyMedium,
                        );
                      }
                      if (index == 1) {
                        return TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: l10n.tripGamesSearchLabel,
                            hintText: l10n.tripGamesSearchHint,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: l10n.nameSearchClear,
                                    onPressed: () => _searchController.clear(),
                                    icon: const Icon(Icons.clear),
                                  ),
                          ),
                        );
                      }
                      if (games.isEmpty) {
                        return Center(child: Text(l10n.tripGamesEmpty));
                      }
                      if (filteredGames.isEmpty) {
                        return Center(child: Text(l10n.tripGamesNoSearchMatch));
                      }

                      final game = filteredGames[index - 2];
                      final creatorLabel = resolveTripMemberDisplayLabel(
                        memberId: game.createdBy,
                        userData: usersById[game.createdBy],
                        tripMemberPublicLabels: trip.memberPublicLabels,
                        currentUserId: currentUserId,
                        emptyFallback: l10n.tripParticipantsTraveler,
                      );
                      final canDelete =
                          game.createdBy == currentUserId || canAdminEdit;
                      final canEdit = canDelete;

                      return Card(
                        child: ListTile(
                          minVerticalPadding: 8,
                          minTileHeight: 72,
                          leading: buildProfileBadge(
                            context: context,
                            displayLabel: creatorLabel,
                            userData: usersById[game.createdBy],
                            size: 30,
                          ),
                          title: Text(
                            game.name.isEmpty ? l10n.activitiesUntitled : game.name,
                          ),
                          subtitle: game.linkUrl.trim().isEmpty
                              ? null
                              : Text(
                                  game.linkUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: LinkPreviewThumbnail(preview: game.linkPreview),
                          onTap: () => _openBoardGameDialog(
                            tripId: trip.id,
                            game: game,
                            canEdit: canEdit,
                            canDelete: canDelete,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () =>
                    _openBoardGameDialog(
                      tripId: trip.id,
                      canEdit: true,
                      canDelete: false,
                    ),
                tooltip: l10n.tripGamesAdd,
                child: const Icon(Icons.add),
              ),
            );
          },
          loading: () => Scaffold(
            appBar: AppBar(title: Text(l10n.tripGamesTitle)),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            appBar: AppBar(title: Text(l10n.tripGamesTitle)),
            body: Center(
                child: Text(l10n.commonErrorWithDetails(error.toString()))),
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.tripGamesTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(l10n.tripGamesTitle)),
        body:
            Center(child: Text(l10n.commonErrorWithDetails(error.toString()))),
      ),
    );
  }
}

class _BoardGameDialog extends StatefulWidget {
  const _BoardGameDialog({
    this.game,
    required this.canEdit,
    required this.canDelete,
  });

  final TripBoardGame? game;
  final bool canEdit;
  final bool canDelete;

  @override
  State<_BoardGameDialog> createState() => _BoardGameDialogState();
}

class _BoardGameDialogState extends State<_BoardGameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  bool _isEditingExisting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.game?.name ?? '');
    _urlController = TextEditingController(text: widget.game?.linkUrl ?? '');
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
    Navigator.of(context).pop(const _BoardGameDialogAction(delete: true));
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    Navigator.of(context).pop(
      _BoardGameDialogAction(
        name: _nameController.text.trim(),
        linkUrl: _urlController.text.trim(),
      ),
    );
  }

  void _enterEditMode() {
    setState(() => _isEditingExisting = true);
  }

  void _cancelExistingEdit() {
    final existingGame = widget.game;
    if (existingGame == null) return;
    _nameController.text = existingGame.name;
    _urlController.text = existingGame.linkUrl;
    setState(() => _isEditingExisting = false);
  }

  Widget _readOnlyLabelValue({
    required String label,
    required String value,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
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
    final isEdit = widget.game != null;
    final canEnterEditMode = isEdit && widget.canEdit;
    final isReadOnly = isEdit && !(_isEditingExisting && canEnterEditMode);
    final hasLink = _urlController.text.trim().isNotEmpty;
    final effectiveName = _nameController.text.trim().isEmpty
        ? l10n.activitiesUntitled
        : _nameController.text.trim();
    final effectiveLink = _urlController.text.trim().isEmpty
        ? l10n.commonNotProvided
        : _urlController.text.trim();
    return AlertDialog(
      title: Text(isEdit ? l10n.tripGamesEditTitle : l10n.tripGamesAddTitle),
      content: SizedBox(
        width: 420,
        child: isReadOnly
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _readOnlyLabelValue(
                    label: l10n.commonName,
                    value: effectiveName,
                  ),
                  const SizedBox(height: 12),
                  _readOnlyLabelValue(
                    label: l10n.tripGamesUrlLabel,
                    value: effectiveLink,
                    trailing: hasLink
                        ? IconButton(
                            tooltip: l10n.linkLabel,
                            onPressed: _openLink,
                            icon: const Icon(Icons.open_in_new),
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                  ),
                ],
              )
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      readOnly: isReadOnly,
                      decoration: InputDecoration(
                        labelText: l10n.commonName,
                        border: const OutlineInputBorder(),
                      ),
                      validator: isReadOnly
                          ? null
                          : (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return l10n.commonRequired;
                              }
                              return null;
                            },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _urlController,
                      readOnly: isReadOnly,
                      decoration: InputDecoration(
                        labelText: l10n.tripGamesUrlLabel,
                        border: const OutlineInputBorder(),
                        hintText: 'https://...',
                      ),
                      keyboardType: TextInputType.url,
                      validator: isReadOnly ? null : _validateUrl,
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isEdit && widget.canDelete)
                IconButton.outlined(
                  tooltip: l10n.commonDelete,
                  onPressed: _confirmDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              if (isReadOnly && canEnterEditMode)
                IconButton.outlined(
                  tooltip: l10n.commonEdit,
                  onPressed: _enterEditMode,
                  icon: const Icon(Icons.edit_outlined),
                ),
              OutlinedButton(
                onPressed: () {
                  if (!isEdit || isReadOnly) {
                    Navigator.of(context).pop();
                    return;
                  }
                  _cancelExistingEdit();
                },
                child: Text(
                    (isEdit && !isReadOnly) ? l10n.commonCancel : l10n.commonClose),
              ),
              if (!isReadOnly)
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check),
                  label: Text(l10n.commonSave),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BoardGameDialogAction {
  const _BoardGameDialogAction({
    this.name = '',
    this.linkUrl = '',
    this.delete = false,
  });

  final String name;
  final String linkUrl;
  final bool delete;
}
