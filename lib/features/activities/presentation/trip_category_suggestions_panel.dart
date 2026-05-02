import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_creators_provider.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/features/activities/presentation/trip_activity_searchable_tab_list.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Suggestions (`plannedAt == null`) for a single activity category, with search and vote.
class TripCategorySuggestionsPanel extends ConsumerStatefulWidget {
  const TripCategorySuggestionsPanel({
    super.key,
    required this.trip,
    required this.category,
    required this.emptyMessage,
    this.showVote = true,
    this.showFab = true,
    this.bottomListPaddingWhenFab = 88,
    this.bottomListPaddingWhenNoFab = 24,
  });

  final Trip trip;
  final TripActivityCategory category;
  final String emptyMessage;
  final bool showVote;
  final bool showFab;
  final double bottomListPaddingWhenFab;
  final double bottomListPaddingWhenNoFab;

  @override
  ConsumerState<TripCategorySuggestionsPanel> createState() =>
      _TripCategorySuggestionsPanelState();
}

class _TripCategorySuggestionsPanelState
    extends ConsumerState<TripCategorySuggestionsPanel> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final canSuggestActivity = canSuggestActivityForTrip(
      trip: widget.trip,
      userId: myUid,
    );
    final activitiesAsync =
        ref.watch(tripActivitiesStreamProvider(widget.trip.id));

    return activitiesAsync.when(
      data: (items) {
        final creatorIds = items
            .map((activity) => activity.createdBy.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
        final creatorIdsKey = creatorIds.join('|');
        final creatorsDataAsync = creatorIdsKey.isEmpty
            ? const AsyncValue<Map<String, Map<String, dynamic>>>.data({})
            : ref.watch(tripActivityCreatorsDataProvider(creatorIdsKey));
        final creatorsDataById =
            creatorsDataAsync.asData?.value ?? const <String, Map<String, dynamic>>{};
        final entries = buildTripActivitiesSuggestionEntries(
          items,
          query: _searchController.text,
          creatorLabelFor: (activity) => creatorLabelForActivity(
            activity,
            widget.trip.memberPublicLabels,
            usersDataById: creatorsDataById,
            currentUserId: myUid,
            unknownLabel: l10n.roleParticipant,
          ),
          categoryFilter: widget.category,
        );

        final showFab =
            widget.showFab && canSuggestActivity && myUid != null && myUid.isNotEmpty;
        final bottomPad =
            showFab ? widget.bottomListPaddingWhenFab : widget.bottomListPaddingWhenNoFab;

        return Stack(
          children: [
            Positioned.fill(
              child: TripActivitiesSearchableTabList(
                searchController: _searchController,
                onSearchChanged: (_) => setState(() {}),
                entries: entries,
                tripId: widget.trip.id,
                tripMemberPublicLabels: widget.trip.memberPublicLabels,
                usersDataById: creatorsDataById,
                currentUserId: myUid,
                emptyMessage: widget.emptyMessage,
                showVoteButton: widget.showVote,
                myUid: myUid,
                bottomListPadding: bottomPad,
              ),
            ),
            if (showFab)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: 'trip_category_suggestions_${widget.category.firestoreValue}_${widget.trip.id}',
                  tooltip: l10n.activitiesSuggestAction,
                  onPressed: () => context.push(
                    '/trips/${widget.trip.id}/activities/new?initialCategory=${widget.category.firestoreValue}',
                  ),
                  child: const Icon(Icons.add),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(e.toString()),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
