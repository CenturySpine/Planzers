import 'package:flutter/material.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activities_ui.dart';
import 'package:planerz/features/trips/data/trip_lodging.dart';
import 'package:planerz/features/trips/data/trip_lodging_plan.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// A night stands in the planning from this hour to
/// [tripLodgingNightEndHour] the next morning.
const int tripLodgingNightStartHour = 22;
const int tripLodgingNightEndHour = 8;

const String _lodgingStopIdPrefix = 'lodging:';

/// Whether [id] is the one of a night's [TripLodgingNight.stop], never the
/// id of an activity.
bool isTripLodgingStopId(String id) => id.startsWith(_lodgingStopIdPrefix);

/// A night of the trip in the planning, worked out from the trip's
/// lodgings each time it is shown.
class TripLodgingNight {
  const TripLodgingNight({required this.night, required this.lodging});

  /// The evening of the night.
  final DateTime night;

  /// Null while the night is not filled in.
  final TripLodging? lodging;

  bool get isMissing => lodging == null;

  /// The night as an accommodation planned at its lodging, for the agenda
  /// and the journey; with no place while not filled in. Like the other
  /// stops of the trip map, it goes by what the group typed (name, else
  /// address), never by content found from the link.
  TripActivity get stop => TripActivity(
        id: '$_lodgingStopIdPrefix${tripNightKey(night)}',
        label: switch (lodging) {
          final l? when l.name.trim().isNotEmpty => l.name.trim(),
          final l? => l.address.trim(),
          null => '',
        },
        category: TripActivityCategory.accommodation,
        linkUrl: lodging?.linkUrl ?? '',
        address: lodging?.address ?? '',
        freeComments: '',
        createdBy: '',
        createdAt: night,
        plannedAt: DateTime(
          night.year,
          night.month,
          night.day,
          tripLodgingNightStartHour,
        ),
        durationMinutes:
            (24 - tripLodgingNightStartHour + tripLodgingNightEndHour) * 60,
        location: lodging?.location,
      );
}

/// The trip's [nights] in the planning, except those already spent at an
/// accommodation planned among [activities].
List<TripLodgingNight> tripLodgingNightsForPlanning({
  required List<DateTime> nights,
  required List<TripLodging> lodgings,
  required Iterable<TripActivity> activities,
}) {
  final covered = {
    for (final activity in activities)
      if (activity.category == TripActivityCategory.accommodation &&
          activity.plannedAt != null)
        tripNightKey(activity.plannedAt!),
  };
  return [
    for (final night in nights)
      if (!covered.contains(tripNightKey(night)))
        TripLodgingNight(
          night: night,
          lodging: tripLodgingForNight(lodgings, tripNightKey(night)),
        ),
  ];
}

/// Agenda card of a night at its lodging.
class TripLodgingNightCard extends StatelessWidget {
  const TripLodgingNightCard({
    super.key,
    required this.lodging,
    required this.onTap,
  });

  final TripLodging lodging;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const group = ActivityFilterGroup.nuits;
    final hasImage =
        ((lodging.linkPreview['imageUrl'] as String?) ?? '').trim().isNotEmpty;
    final address = lodging.address.trim();
    return TripPlanningListCardShell(
      categoryColor: group.filterColor,
      categoryLightBg: group.filterLightBgColor,
      leadingIcon: PhosphorIconsRegular.bed,
      titleRow: Text(
        lodging.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppTokens.deep,
        ),
      ),
      subtitle: address == lodging.displayTitle ? '' : address,
      trailing: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child:
                  LinkPreviewThumbnail(preview: lodging.linkPreview, size: 44),
            )
          : null,
      onTap: onTap,
    );
  }
}

/// Agenda card standing for a night not filled in yet; tapping it opens
/// the lodging editor.
class TripMissingLodgingCard extends StatelessWidget {
  const TripMissingLodgingCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const group = ActivityFilterGroup.nuits;
    return Material(
      color: group.filterLightBgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg - 2),
        side: BorderSide(color: group.filterBorderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.bed,
                  size: 20, color: group.filterInkColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.activitiesMissingLodging,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: group.filterInkColor,
                  ),
                ),
              ),
              Icon(PhosphorIconsRegular.plus, color: group.filterInkColor),
            ],
          ),
        ),
      ),
    );
  }
}
