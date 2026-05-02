import 'package:flutter/material.dart';
import 'package:planerz/features/activities/presentation/trip_activity_card.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/features/trips/presentation/name_list_search.dart';

/// Search field + scrollable list of [TripActivitiesListEntry] rows (activity cards
/// and optional day separators).
class TripActivitiesSearchableTabList extends StatelessWidget {
  const TripActivitiesSearchableTabList({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.entries,
    required this.tripId,
    required this.tripMemberPublicLabels,
    required this.usersDataById,
    required this.currentUserId,
    required this.emptyMessage,
    this.showVoteButton = false,
    this.myUid,
    this.bottomListPadding = 88,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final List<TripActivitiesListEntry> entries;
  final String tripId;
  final Map<String, String> tripMemberPublicLabels;
  final Map<String, Map<String, dynamic>> usersDataById;
  final String? currentUserId;
  final String emptyMessage;
  final bool showVoteButton;
  final String? myUid;
  final double bottomListPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: NameListSearchTextField(
            controller: searchController,
            onChanged: onSearchChanged,
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      searchController.text.trim().isEmpty
                          ? emptyMessage
                          : nameListSearchEmptyMessage(context),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, bottomListPadding),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final dayLabel = entry.daySeparatorLabel;
                    if (dayLabel != null) {
                      return TripActivityDaySeparatorPill(label: dayLabel);
                    }
                    final activity = entry.activity;
                    if (activity == null) {
                      return const SizedBox.shrink();
                    }
                    return TripActivityCard(
                      tripId: tripId,
                      activity: activity,
                      tripMemberPublicLabels: tripMemberPublicLabels,
                      usersDataById: usersDataById,
                      currentUserId: currentUserId,
                      showVoteButton: showVoteButton,
                      myUid: myUid,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class TripActivityDaySeparatorPill extends StatelessWidget {
  const TripActivityDaySeparatorPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
