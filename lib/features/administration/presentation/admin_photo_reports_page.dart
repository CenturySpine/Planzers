import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/activity_photo.dart';
import 'package:planerz/features/activities/data/activity_photos_repository.dart';
import 'package:planerz/features/activities/presentation/photo_report_card.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';

/// The photos reported in every trip, for the application owner: delete the
/// photo or dismiss the report.
class AdminPhotoReportsPage extends ConsumerStatefulWidget {
  const AdminPhotoReportsPage({super.key});

  static const String routePath = '/administration/photo-reports';

  @override
  ConsumerState<AdminPhotoReportsPage> createState() =>
      _AdminPhotoReportsPageState();
}

class _AdminPhotoReportsPageState extends ConsumerState<AdminPhotoReportsPage> {
  final _crossCache = CrossCache();

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(allPhotoReportsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Photos signalées')),
      body: reportsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Erreur : $error', textAlign: TextAlign.center),
          ),
        ),
        data: (reports) {
          final pending = reports
              .where((report) => !report.dismissed)
              .toList(growable: false);
          if (pending.isEmpty) {
            return const Center(child: Text('Aucune photo signalée'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: pending.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _AdminReportCard(
              key: ValueKey('${pending[index].tripId}/${pending[index].id}'),
              report: pending[index],
              tripReports: [
                for (final report in reports)
                  if (report.tripId == pending[index].tripId) report,
              ],
              crossCache: _crossCache,
            ),
          );
        },
      ),
    );
  }
}

class _AdminReportCard extends ConsumerWidget {
  const _AdminReportCard({
    super.key,
    required this.report,
    required this.tripReports,
    required this.crossCache,
  });

  final PhotoReport report;
  final List<PhotoReport> tripReports;
  final CrossCache crossCache;

  static String _reason(PhotoReportReason reason) => switch (reason) {
        PhotoReportReason.inappropriate => 'Contenu inapproprié',
        PhotoReportReason.notConsenting =>
          'La personne est sur la photo et ne le souhaite pas',
        PhotoReportReason.other => 'Autre',
      };

  static Future<bool> _confirmDeletion(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette photo ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripTitle = ref
        .watch(tripStreamProvider(report.tripId))
        .asData
        ?.value
        ?.title
        .trim();
    final activityLabel = ref
        .watch(tripActivitiesStreamProvider(report.tripId))
        .asData
        ?.value
        .where((activity) => activity.id == report.activityId)
        .map((activity) => activity.label.trim())
        .firstOrNull;
    final heading = [
      if (tripTitle != null && tripTitle.isNotEmpty) tripTitle else 'Voyage',
      if (activityLabel != null && activityLabel.isNotEmpty) activityLabel,
    ].join(' · ');
    return PhotoReportCard(
      report: report,
      allReports: tripReports,
      heading: heading,
      crossCache: crossCache,
      confirmDeletion: _confirmDeletion,
      labels: (
        reason: _reason(report.reason),
        author: (name) => 'Photo de $name',
        reporter: (name) => 'Signalée par $name',
        unknownMember: 'un participant',
        gone: 'Photo supprimée ou devenue privée',
        dismiss: 'Ignorer',
        delete: 'Supprimer la photo',
        error: (error) => 'Erreur : $error',
      ),
    );
  }
}
