import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/activity_photo.dart';
import 'package:planerz/features/activities/data/activity_photos_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/photo_report_card.dart';
import 'package:planerz/features/activities/presentation/trip_activity_photos_card.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// The photos the members of a trip reported, for its admins: delete the
/// photo or dismiss the report.
class TripPhotoReportsPage extends ConsumerStatefulWidget {
  const TripPhotoReportsPage({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripPhotoReportsPage> createState() =>
      _TripPhotoReportsPageState();
}

class _TripPhotoReportsPageState extends ConsumerState<TripPhotoReportsPage> {
  final _crossCache = CrossCache();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final myUid = ref.watch(activityPhotosRepositoryProvider).currentUid;
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));
    final isAdmin = tripAsync.asData?.value?.isTripAdmin(myUid) ?? false;

    Widget body;
    if (tripAsync.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!isAdmin) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.tripNotFoundOrNoAccess, textAlign: TextAlign.center),
        ),
      );
    } else {
      body = _ReportsList(
        tripId: widget.tripId,
        crossCache: _crossCache,
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tripPhotoReportsTitle)),
      body: body,
    );
  }
}

class _ReportsList extends ConsumerWidget {
  const _ReportsList({required this.tripId, required this.crossCache});

  final String tripId;
  final CrossCache crossCache;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final reportsAsync = ref.watch(tripPhotoReportsStreamProvider(tripId));
    final activities =
        ref.watch(tripActivitiesStreamProvider(tripId)).asData?.value ??
            const <TripActivity>[];
    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.commonErrorWithDetails(error.toString()),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (reports) {
        final pending = reports
            .where((report) => !report.dismissed)
            .toList(growable: false);
        if (pending.isEmpty) {
          return Center(child: Text(l10n.tripPhotoReportsEmpty));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: pending.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final report = pending[index];
            final label = activities
                .where((activity) => activity.id == report.activityId)
                .map((activity) => activity.label.trim())
                .firstOrNull;
            return PhotoReportCard(
              key: ValueKey(report.id),
              report: report,
              allReports: reports,
              heading: label == null || label.isEmpty
                  ? l10n.activitiesUntitled
                  : label,
              crossCache: crossCache,
              confirmDeletion: confirmActivityPhotoDeletion,
              labels: (
                reason: photoReportReasonLabel(l10n, report.reason),
                author: l10n.tripPhotoReportsAuthor,
                reporter: l10n.tripPhotoReportsBy,
                unknownMember: l10n.roleParticipant,
                gone: l10n.tripPhotoReportsGone,
                dismiss: l10n.tripPhotoReportsDismiss,
                delete: l10n.tripPhotoReportsDeletePhoto,
                error: (error) => l10n.commonErrorWithDetails(error.toString()),
              ),
            );
          },
        );
      },
    );
  }
}

/// Pending reports of a trip (for the settings entry of its admins).
int pendingPhotoReportsCount(List<PhotoReport> reports) =>
    reports.where((report) => !report.dismissed).length;
