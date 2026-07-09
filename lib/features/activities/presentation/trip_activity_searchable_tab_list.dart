import 'package:flutter/material.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activities_ui.dart';
import 'package:planerz/features/activities/presentation/trip_activity_card.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/features/meals/presentation/trip_meal_card.dart';
import 'package:planerz/l10n/app_localizations.dart';

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
    this.activityLeadingBuilder,
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
  final Widget? Function(TripActivity)? activityLeadingBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TripActivitiesSearchField(
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
                          : AppLocalizations.of(context)!.activitiesSearchEmpty,
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
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: tripActivitiesCardGap),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final dayLabel = entry.daySeparatorLabel;
                    if (dayLabel != null) {
                      return TripActivityDaySeparatorRail(label: dayLabel);
                    }
                    final activity = entry.activity;
                    if (activity == null) {
                      final meal = entry.meal;
                      if (meal == null) {
                        return const SizedBox.shrink();
                      }
                      return TripMealCard(
                        tripId: tripId,
                        meal: meal,
                        memberLabels: tripMemberPublicLabels,
                      );
                    }
                    final card = TripActivityCard(
                      tripId: tripId,
                      activity: activity,
                      tripMemberPublicLabels: tripMemberPublicLabels,
                      showVoteButton: showVoteButton,
                      myUid: myUid,
                    );
                    final leading = activityLeadingBuilder?.call(activity);
                    if (leading != null) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          leading,
                          Expanded(child: card),
                        ],
                      );
                    }
                    return card;
                  },
                ),
        ),
      ],
    );
  }
}
