import 'package:planerz/app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activities_ui.dart';
import 'package:planerz/features/activities/presentation/trip_activity_category_presentation.dart';
import 'package:planerz/features/activities/presentation/trip_activity_duration.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final color =
        hasVoted ? AppTokens.primaryDark : AppTokens.onSurfaceVariant;
    final l10n = AppLocalizations.of(context)!;

    return Tooltip(
      message: hasVoted ? l10n.activitiesUnvote : l10n.activitiesVote,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: hasVoted ? AppTokens.primaryTint : AppTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            side: BorderSide(
              color: hasVoted ? AppTokens.primary : AppTokens.divider,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            onTap: _loading ? null : _toggle,
            child: SizedBox(
              width: 44,
              height: 54,
              child: Center(
                child: _loading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: color,
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasVoted
                                ? PhosphorIconsFill.thumbsUp
                                : PhosphorIconsRegular.thumbsUp,
                            size: 18,
                            color: color,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: color,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
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
    this.showVoteButton = false,
    this.myUid,
    this.showTime = true,
  });

  final String tripId;
  final TripActivity activity;
  final Map<String, String> tripMemberPublicLabels;
  final bool showVoteButton;
  final String? myUid;

  /// False when the time is already shown outside the card (agenda gutter).
  final bool showTime;

  void _openDetail(BuildContext context) {
    context.push('/trips/$tripId/activities/${activity.id}');
  }

  Future<void> _openLink(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final url = activity.linkUrl.trim();
    final parsed = Uri.tryParse(url);
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
    if (!didLaunch && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkOpenImpossible)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = activity.label.trim().isEmpty
        ? l10n.activitiesUntitled
        : activity.label.trim();
    final filterGroup = activity.category.filterGroup;
    final categoryColor = filterGroup.filterColor;
    final categoryLightBg = filterGroup.filterLightBgColor;
    final preview = activity.linkPreview;
    final imageUrl = ((preview['imageUrl'] as String?) ?? '').trim();
    final hasImage = imageUrl.isNotEmpty;
    final hasLink = activity.linkUrl.trim().isNotEmpty;

    final end = showTime ? tripActivityEndTime(context, activity) : null;
    final timeLabel = activity.plannedAt == null || end == null
        ? null
        : l10n.activitiesTimeRange(
            DateFormat.Hm(Localizations.localeOf(context).toString())
                .format(activity.plannedAt!.toLocal()),
            end.dayOffset > 0
                ? '${end.time}${l10n.activitiesEndDayOffset(end.dayOffset)}'
                : end.time,
          );

    final card = TripPlanningListCardShell(
      categoryColor: categoryColor,
      categoryLightBg: categoryLightBg,
      leadingIcon: activity.category.categoryIcon,
      subtitle: l10n.activitiesProposedBy(
        creatorLabelForActivity(
          activity,
          tripMemberPublicLabels,
          unknownLabel: l10n.roleParticipant,
        ),
      ),
      subtitleItalic: true,
      onTap: () => _openDetail(context),
      titleRow: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (timeLabel != null) ...[
            Text(
              timeLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTokens.deep,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTokens.deep,
              ),
            ),
          ),
        ],
      ),
      trailing: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinkPreviewThumbnail(preview: preview, size: 44),
            )
          : hasLink
              ? TripPlanningLinkTrailingButton(
                  onTap: () => _openLink(context),
                )
              : null,
    );

    if (!showVoteButton) return card;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: card),
        TripActivityVoteButton(
          tripId: tripId,
          activityId: activity.id,
          votes: activity.votes,
          myUid: myUid ?? '',
        ),
      ],
    );
  }
}
