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
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Suggestions (`plannedAt == null`) for one or more activity categories, with search and vote.
///
/// When [onActivitySelected] is provided the panel enters **selection mode**:
/// a checkbox appears on each row, selecting one hides all others, and the
/// chosen [TripActivity] (or `null` when deselected) is reported via the
/// callback. Pass [preSelectedActivityId] to pre-select the activity whose
/// [TripActivity.id] matches on first data load.
class TripCategorySuggestionsPanel extends ConsumerStatefulWidget {
  const TripCategorySuggestionsPanel({
    super.key,
    required this.trip,
    required this.categories,
    required this.emptyMessage,
    this.showVote = true,
    this.showFab = true,
    this.bottomListPaddingWhenFab = 88,
    this.bottomListPaddingWhenNoFab = 24,
    this.onActivitySelected,
    this.preSelectedActivityId,
  });

  final Trip trip;
  final List<TripActivityCategory> categories;
  final String emptyMessage;
  final bool showVote;
  final bool showFab;
  final double bottomListPaddingWhenFab;
  final double bottomListPaddingWhenNoFab;
  final ValueChanged<TripActivity?>? onActivitySelected;
  final String? preSelectedActivityId;

  @override
  ConsumerState<TripCategorySuggestionsPanel> createState() =>
      _TripCategorySuggestionsPanelState();
}

class _TripCategorySuggestionsPanelState
    extends ConsumerState<TripCategorySuggestionsPanel> {
  final TextEditingController _searchController = TextEditingController();
  TripActivity? _selectedActivity;
  bool _preSelectionApplied = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyPreSelection(List<TripActivity> items) {
    if (_preSelectionApplied) return;
    _preSelectionApplied = true;
    final id = (widget.preSelectedActivityId ?? '').trim();
    if (id.isEmpty) return;
    final match = items.where((a) => a.id.trim() == id).firstOrNull;
    if (match != null) {
      _selectedActivity = match;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final canSuggestActivity = canSuggestActivityForTrip(
      trip: widget.trip,
      userId: myUid,
    );
    final selectionMode = widget.onActivitySelected != null;
    final participants = ref
            .watch(tripParticipantsStreamProvider(widget.trip.id))
            .asData
            ?.value ??
        [];
    final memberLabels = <String, String>{
      for (final m in participants) ...<String, String>{
        m.id: m.participantName,
        if (m.userId != null) m.userId!: m.participantName,
      },
    };
    final activitiesAsync =
        ref.watch(tripActivitiesStreamProvider(widget.trip.id));

    return activitiesAsync.when(
      data: (items) {
        _applyPreSelection(items);

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

        final allEntries = buildTripActivitiesSuggestionEntries(
          items,
          query: _searchController.text,
          creatorLabelFor: (activity) => creatorLabelForActivity(
            activity,
            memberLabels,
            unknownLabel: l10n.roleParticipant,
          ),
          categoryFilter: widget.categories,
        );

        // In selection mode, hide all others once one is chosen.
        final entries = (selectionMode && _selectedActivity != null)
            ? allEntries
                .where((e) => e.activity?.id == _selectedActivity!.id)
                .toList(growable: false)
            : allEntries;

        final showFab =
            widget.showFab && canSuggestActivity && myUid != null && myUid.isNotEmpty;
        final bottomPad =
            showFab ? widget.bottomListPaddingWhenFab : widget.bottomListPaddingWhenNoFab;

        Widget? Function(TripActivity)? leadingBuilder;
        if (selectionMode) {
          leadingBuilder = (activity) => Checkbox(
                value: _selectedActivity?.id == activity.id,
                onChanged: (checked) {
                  setState(() {
                    _selectedActivity = (checked == true) ? activity : null;
                  });
                  widget.onActivitySelected!(
                    (checked == true) ? activity : null,
                  );
                },
              );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: TripActivitiesSearchableTabList(
                searchController: _searchController,
                onSearchChanged: (_) => setState(() {}),
                entries: entries,
                tripId: widget.trip.id,
                tripMemberPublicLabels: memberLabels,
                usersDataById: creatorsDataById,
                currentUserId: myUid,
                emptyMessage: widget.emptyMessage,
                showVoteButton: widget.showVote && !selectionMode,
                myUid: myUid,
                bottomListPadding: bottomPad,
                activityLeadingBuilder: leadingBuilder,
              ),
            ),
            if (showFab)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: 'trip_category_suggestions_${widget.categories.map((c) => c.firestoreValue).join('_')}_${widget.trip.id}',
                  tooltip: l10n.activitiesSuggestAction,
                  onPressed: () => context.push(
                    '/trips/${widget.trip.id}/activities/new?initialCategory=${widget.categories.map((c) => c.firestoreValue).join(',')}',
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
