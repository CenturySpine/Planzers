import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_category_presentation.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Compact vote control for activity suggestions (Firestore-backed via stream refresh).
class TripActivityVoteButton extends ConsumerStatefulWidget {
  const TripActivityVoteButton({
    super.key,
    required this.tripId,
    required this.activityId,
    required this.votes,
    required this.myUid,
  });

  final String tripId;
  final String activityId;
  final List<String> votes;
  final String myUid;

  @override
  ConsumerState<TripActivityVoteButton> createState() =>
      _TripActivityVoteButtonState();
}

class _TripActivityVoteButtonState extends ConsumerState<TripActivityVoteButton> {
  bool _loading = false;

  Future<void> _toggle() async {
    if (_loading || widget.myUid.isEmpty) return;
    final hasVoted = widget.votes.contains(widget.myUid);
    setState(() => _loading = true);
    try {
      await ref.read(activitiesRepositoryProvider).voteForActivity(
            tripId: widget.tripId,
            activityId: widget.activityId,
            vote: !hasVoted,
          );
    } catch (_) {
      // stream will revert the optimistic state automatically
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVoted =
        widget.myUid.isNotEmpty && widget.votes.contains(widget.myUid);
    final count = widget.votes.length;
    final scheme = Theme.of(context).colorScheme;
    final color = hasVoted ? scheme.primary : scheme.onSurfaceVariant;
    final l10n = AppLocalizations.of(context)!;

    return Tooltip(
      message: hasVoted ? l10n.activitiesUnvote : l10n.activitiesVote,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _loading ? null : _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: _loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: color,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasVoted ? Icons.thumb_up : Icons.thumb_up_outlined,
                      size: 16,
                      color: color,
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 3),
                      Text(
                        '$count',
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// List row card for a trip activity: opens detail on tap; optional vote column.
class TripActivityCard extends StatelessWidget {
  const TripActivityCard({
    super.key,
    required this.tripId,
    required this.activity,
    required this.tripMemberPublicLabels,
    required this.usersDataById,
    required this.currentUserId,
    this.showVoteButton = false,
    this.myUid,
  });

  final String tripId;
  final TripActivity activity;
  final Map<String, String> tripMemberPublicLabels;
  final Map<String, Map<String, dynamic>> usersDataById;
  final String? currentUserId;
  final bool showVoteButton;
  final String? myUid;

  void _openDetail(BuildContext context) {
    context.push('/trips/$tripId/activities/${activity.id}');
  }

  @override
  Widget build(BuildContext context) {
    final label = activity.label.trim().isEmpty
        ? AppLocalizations.of(context)!.activitiesUntitled
        : activity.label.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Card(
            color:
                activity.done ? context.planerzColors.successContainer : null,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openDetail(context),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      activity.category.categoryIcon,
                      size: 20,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(
                              context,
                            )!.activitiesProposedBy(
                              creatorLabelForActivity(
                                activity,
                                tripMemberPublicLabels,
                                usersDataById: usersDataById,
                                currentUserId: currentUserId,
                                unknownLabel:
                                    AppLocalizations.of(context)!.roleParticipant,
                              ),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                          ),
                          if (activity.plannedAt != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              DateFormat.Hm(
                                Localizations.localeOf(context).toString(),
                              ).format(activity.plannedAt!.toLocal()),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.tertiary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    LinkPreviewThumbnail(preview: activity.linkPreview),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showVoteButton) ...[
          const SizedBox(width: 4),
          TripActivityVoteButton(
            tripId: tripId,
            activityId: activity.id,
            votes: activity.votes,
            myUid: myUid ?? '',
          ),
        ],
      ],
    );
  }
}
