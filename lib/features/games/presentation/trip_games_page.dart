import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/games/data/trip_board_game.dart';
import 'package:planerz/features/games/data/trip_games_repository.dart';
import 'package:planerz/features/games/presentation/trip_games_ui.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripGamesPage extends ConsumerStatefulWidget {
  const TripGamesPage({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripGamesPage> createState() => _TripGamesPageState();
}

class _TripGamesPageState extends ConsumerState<TripGamesPage> {
  late final TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _openBoardGameDialog({
    required String tripId,
    required bool canEdit,
    required bool canDelete,
    TripBoardGame? game,
  }) async {
    final action = await showDialog<TripBoardGameDialogResult>(
      context: context,
      builder: (context) => Theme(
        data: NeonPalette.overlayOn(Theme.of(context)),
        child: TripBoardGameDialog(
          gameName: game?.name,
          gameUrl: game?.linkUrl,
          canEdit: canEdit,
          canDelete: canDelete,
          isCreate: game == null,
        ),
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
    final memberLabels =
        ref.watch(tripMemberResolvedLabelsProvider(widget.tripId));

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

            return Theme(
              data: NeonPalette.overlayOn(Theme.of(context)),
              child: Scaffold(
                backgroundColor: NeonPalette.scaffoldBackground,
                appBar: AppBar(
                  title: Text(l10n.tripGamesTitle),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(48),
                    child: TripGamesTabBar(
                      label: l10n.tripBoardGamesTab,
                      selected: true,
                    ),
                  ),
                ),
                body: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: filteredGames.length + 2 +
                      (games.isEmpty || filteredGames.isEmpty ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return TripGamesIntroCallout(message: l10n.tripGamesIntro);
                    }
                    if (index == 1) {
                      return TripGamesSearchField(
                        controller: _searchController,
                        label: l10n.tripGamesSearchLabel,
                        hint: l10n.tripGamesSearchHint,
                        clearTooltip: l10n.nameSearchClear,
                        onChanged: (value) {
                          final next = value.trim();
                          if (next != _searchQuery) {
                            setState(() => _searchQuery = next);
                          }
                        },
                      );
                    }
                    if (index == 2 && (games.isEmpty || filteredGames.isEmpty)) {
                      return TripGamesEmptyState(
                        message: games.isEmpty
                            ? l10n.tripGamesEmpty
                            : l10n.tripGamesNoSearchMatch,
                      );
                    }

                    final game = filteredGames[index - 2];
                    final creatorLabel = memberLabels[game.createdBy] ??
                        l10n.tripParticipantsTraveler;
                    final canDelete =
                        game.createdBy == currentUserId || canAdminEdit;
                    final canEdit = canDelete;
                    final title = game.name.isEmpty
                        ? l10n.activitiesUntitled
                        : game.name;

                    return TripBoardGameCard(
                      title: title,
                      preview: game.linkPreview,
                      creatorBadge: buildProfileBadge(
                        context: context,
                        displayLabel: creatorLabel,
                        userData: usersById[game.createdBy],
                        size: 36,
                      ),
                      onTap: () => _openBoardGameDialog(
                        tripId: trip.id,
                        game: game,
                        canEdit: canEdit,
                        canDelete: canDelete,
                      ),
                    );
                  },
                ),
                floatingActionButton: TripGamesFab(
                  tooltip: l10n.tripGamesAdd,
                  onPressed: () => _openBoardGameDialog(
                    tripId: trip.id,
                    canEdit: true,
                    canDelete: false,
                  ),
                ),
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
