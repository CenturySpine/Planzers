import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/core/presentation/osm_map.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_missing_transport.dart';
import 'package:planerz/features/activities/presentation/trip_transport_mode_presentation.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// `850 m`, `1,2 km` (in the user's language) or `12 km`.
String formatTripDistance(BuildContext context, double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final kilometers = meters / 1000;
  if (kilometers >= 10) return '${kilometers.round()} km';
  final locale = Localizations.localeOf(context).toString();
  return '${NumberFormat('0.0', locale).format(kilometers)} km';
}

/// `Borgo degli Ulivi → Cava Carosello · ≈ 15 km`.
String tripMissingTransportRouteText(
  BuildContext context,
  TripMissingTransport missing,
) {
  final l10n = AppLocalizations.of(context)!;
  String name(String value) => value.isEmpty ? l10n.activitiesUntitled : value;
  return l10n.activitiesMissingTransportRoute(
    name(missing.fromName),
    name(missing.toName),
    formatTripDistance(context, missing.distanceMeters),
  );
}

/// Asks for the mode of [missing], then adds the transport from one place
/// to the other, arriving as the next activity starts.
Future<void> showTripMissingTransportSheet(
  BuildContext context, {
  required String tripId,
  required TripMissingTransport missing,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final mode = await showModalBottomSheet<TripTransportMode>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.activitiesMissingTransport,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              tripMissingTransportRouteText(sheetContext, missing),
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in TripTransportMode.values)
                  ActionChip(
                    avatar: Icon(mode.icon, size: 18),
                    label: Text(mode.label(l10n)),
                    onPressed: () => Navigator.of(sheetContext).pop(mode),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (mode == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final schedule = missing.schedule(mode);
  String name(String value) => value.isEmpty ? l10n.activitiesUntitled : value;
  try {
    await ProviderScope.containerOf(context, listen: false)
        .read(activitiesRepositoryProvider)
        .addActivity(
          tripId: tripId,
          label: l10n.activitiesMissingTransportLabel(
            name(missing.fromName),
            name(missing.toName),
          ),
          category: TripActivityCategory.transport,
          linkUrl: '',
          address: missing.toAddress,
          freeComments: '',
          plannedAt: schedule.start,
          durationMinutes: schedule.minutes,
          location: missing.toPoint.toGeoPoint(),
          departureAddress: missing.fromAddress,
          departureLocation: missing.fromPoint.toGeoPoint(),
          transportMode: mode,
        );
    messenger.showSnackBar(SnackBar(content: Text(l10n.activitiesAdded)));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
    );
  }
}

/// Agenda card standing for a transport not planned yet; tapping it asks
/// for the mode.
class TripMissingTransportCard extends StatelessWidget {
  const TripMissingTransportCard({
    super.key,
    required this.missing,
    required this.onTap,
  });

  final TripMissingTransport missing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const group = ActivityFilterGroup.trajets;
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
              Icon(PhosphorIconsRegular.path,
                  size: 20, color: group.filterInkColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.activitiesMissingTransport,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: group.filterInkColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tripMissingTransportRouteText(context, missing),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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
