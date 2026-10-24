import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/activity_photo.dart';
import 'package:planerz/features/activities/data/activity_photos_repository.dart';
import 'package:planerz/features/messaging/presentation/chat_image_viewer.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';

/// The photos reported in every trip, for the application owner only: one
/// entry per photo with its reports and their outcome, and what each
/// reporter's reports became.
class AdminPhotoReportsPage extends ConsumerStatefulWidget {
  const AdminPhotoReportsPage({super.key});

  static const String routePath = '/administration/photo-reports';

  @override
  ConsumerState<AdminPhotoReportsPage> createState() =>
      _AdminPhotoReportsPageState();
}

class _AdminPhotoReportsPageState extends ConsumerState<AdminPhotoReportsPage> {
  final _crossCache = CrossCache();
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(allPhotoReportsStreamProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Photos signalées'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Photos'), Tab(text: 'Signaleurs')],
          ),
        ),
        body: reportsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Erreur : $error', textAlign: TextAlign.center),
            ),
          ),
          data: (reports) => TabBarView(
            children: [
              _PhotosTab(
                reports: reports,
                showHistory: _showHistory,
                onShowHistoryChanged: (value) =>
                    setState(() => _showHistory = value),
                crossCache: _crossCache,
              ),
              _ReportersTab(reports: reports),
            ],
          ),
        ),
      ),
    );
  }
}

String _count(int n, String one, String many) => '$n ${n <= 1 ? one : many}';

String _reasonText(PhotoReportReason reason) => switch (reason) {
      PhotoReportReason.inappropriate => 'Contenu inapproprié',
      PhotoReportReason.notConsenting =>
        'La personne est sur la photo et ne le souhaite pas',
      PhotoReportReason.other => 'Autre',
    };

String _outcomeText(PhotoReportResolution? resolution) => switch (resolution) {
      null => 'En attente',
      PhotoReportResolution.dismissed => 'Ignoré',
      PhotoReportResolution.photoRemoved => 'Photo retirée',
    };

/// A small colored label.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.background, required this.foreground});

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _PhotosTab extends StatelessWidget {
  const _PhotosTab({
    required this.reports,
    required this.showHistory,
    required this.onShowHistoryChanged,
    required this.crossCache,
  });

  final List<PhotoReport> reports;
  final bool showHistory;
  final ValueChanged<bool> onShowHistoryChanged;
  final CrossCache crossCache;

  @override
  Widget build(BuildContext context) {
    final groups = groupPhotoReports(reports)
        .where((group) => showHistory || group.pending.isNotEmpty)
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilterChip(
            label: const Text('Afficher l\'historique'),
            selected: showHistory,
            onSelected: onShowHistoryChanged,
          ),
        ),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(
              child: Text(
                reports.isEmpty
                    ? 'Aucune photo signalée'
                    : 'Aucune photo à traiter',
              ),
            ),
          ),
        for (final group in groups) ...[
          _PhotoGroupCard(
            key: ValueKey(
                '${group.tripId}/${group.photoOwnerId}/${group.photoId}'),
            group: group,
            crossCache: crossCache,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PhotoGroupCard extends ConsumerWidget {
  const _PhotoGroupCard({
    super.key,
    required this.group,
    required this.crossCache,
  });

  final PhotoReportGroup group;
  final CrossCache crossCache;

  static const double _thumbExtent = 72;

  Future<bool> _confirmDeletion(BuildContext context) async {
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

  Future<void> _run(
      BuildContext context, Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur : $error')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final repository = ref.read(activityPhotosRepositoryProvider);
    final photoAsync = ref.watch(activityPhotoStreamProvider((
      tripId: group.tripId,
      ownerId: group.photoOwnerId,
      photoId: group.photoId,
    )));
    // A photo made private can no longer be read: it counts as gone.
    final photo = photoAsync.asData?.value;
    final isGone = !photoAsync.isLoading && photo == null;
    final trip = ref.watch(tripStreamProvider(group.tripId)).asData?.value;
    final memberCount = trip?.memberUserIds.length;
    final otherMembers = memberCount == null
        ? null
        : memberCount <= 1
            ? 0
            : memberCount - 1;
    final activityLabel = ref
        .watch(tripActivitiesStreamProvider(group.tripId))
        .asData
        ?.value
        .where((activity) => activity.id == group.activityId)
        .map((activity) => activity.displayLabel)
        .firstOrNull;
    final names = ref.watch(tripMemberResolvedLabelsProvider(group.tripId));
    String nameOf(String uid) => names[uid] ?? 'Participant inconnu';
    final tripTitle = trip?.title.trim() ?? '';
    final heading = [
      tripTitle.isEmpty ? 'Voyage' : tripTitle,
      if (activityLabel != null && activityLabel.isNotEmpty) activityLabel,
    ].join(' · ');
    final pending = group.pending;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: cs.surfaceContainerHighest,
                    child: SizedBox.square(
                      dimension: _thumbExtent,
                      child: photo == null
                          ? Icon(
                              isGone
                                  ? PhosphorIconsRegular.imageBroken
                                  : PhosphorIconsRegular.image,
                              color: cs.onSurfaceVariant,
                            )
                          : InkWell(
                              onTap: () => showChatImageViewer(
                                context: context,
                                crossCache: crossCache,
                                imageUrl: photo.url,
                                caption: photo.caption,
                              ),
                              child: Image(
                                image: CachedNetworkImage(
                                  photo.thumbUrl,
                                  crossCache,
                                ),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  PhosphorIconsRegular.imageBroken,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(heading, style: textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        'Photo de ${nameOf(group.photoOwnerId)}',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          _count(
                            group.reports.length,
                            'signalement',
                            'signalements',
                          ),
                          if (otherMembers != null)
                            'sur ${_count(otherMembers, 'autre participant', 'autres participants')}',
                        ].join(' '),
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (group.thresholdReached)
                            _Tag(
                              'Seuil de $photoReportThreshold atteint',
                              background: cs.errorContainer,
                              foreground: cs.onErrorContainer,
                            ),
                          if (pending.isNotEmpty)
                            _Tag(
                              '${pending.length} en attente',
                              background: cs.secondaryContainer,
                              foreground: cs.onSecondaryContainer,
                            ),
                          if (isGone)
                            _Tag(
                              'Photo supprimée ou devenue privée',
                              background: cs.surfaceContainerHighest,
                              foreground: cs.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            for (final report in group.reports)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_reasonText(report.reason),
                              style: textTheme.bodyMedium),
                          Text(
                            [
                              nameOf(report.reporterId),
                              if (report.createdAt != null)
                                dateFormat.format(report.createdAt!.toLocal()),
                            ].join(' · '),
                            style: textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Tag(
                      _outcomeText(report.resolution),
                      background: report.isPending
                          ? cs.secondaryContainer
                          : cs.surfaceContainerHighest,
                      foreground: report.isPending
                          ? cs.onSecondaryContainer
                          : cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            if (pending.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => _run(
                        context,
                        () => repository.resolveReports(
                          tripId: group.tripId,
                          reportIds: [for (final r in pending) r.id],
                          resolution: PhotoReportResolution.dismissed,
                        ),
                      ),
                      child: const Text('Ignorer'),
                    ),
                    if (photo != null)
                      FilledButton.tonal(
                        onPressed: () async {
                          if (!await _confirmDeletion(context)) return;
                          if (!context.mounted) return;
                          await _run(
                            context,
                            () => repository.deletePhotoAsModerator(
                              tripId: group.tripId,
                              ownerId: group.photoOwnerId,
                              photoId: group.photoId,
                              pendingReportIds: [for (final r in pending) r.id],
                            ),
                          );
                        },
                        child: const Text('Supprimer la photo'),
                      ),
                    if (isGone)
                      FilledButton.tonal(
                        onPressed: () => _run(
                          context,
                          () => repository.resolveReports(
                            tripId: group.tripId,
                            reportIds: [for (final r in pending) r.id],
                            resolution: PhotoReportResolution.photoRemoved,
                          ),
                        ),
                        child: const Text('Clore'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportersTab extends StatelessWidget {
  const _ReportersTab({required this.reports});

  final List<PhotoReport> reports;

  @override
  Widget build(BuildContext context) {
    final stats = photoReporterStats(reports);
    if (stats.isEmpty) {
      return const Center(child: Text('Aucun signalement'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: stats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _ReporterCard(stats: stats[index]),
    );
  }
}

class _ReporterCard extends ConsumerWidget {
  const _ReporterCard({required this.stats});

  final PhotoReporterStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = ref.watch(
          tripMemberResolvedLabelsProvider(stats.latestTripId),
        )[stats.reporterId] ??
        'Participant inconnu';
    final oftenDismissed = stats.dismissed >= photoReportThreshold &&
        stats.dismissed > stats.photoRemoved;
    final singleTarget =
        stats.total >= photoReportThreshold && stats.distinctAuthors == 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              '${_count(stats.total, 'signalement', 'signalements')} · '
              '${_count(stats.distinctAuthors, 'auteur visé', 'auteurs visés')}',
              style: textTheme.bodyMedium,
            ),
            Text(
              '${stats.pending} en attente · '
              '${_count(stats.dismissed, 'ignoré', 'ignorés')} · '
              '${_count(stats.photoRemoved, 'photo retirée', 'photos retirées')}',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (oftenDismissed || singleTarget) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (oftenDismissed)
                    _Tag(
                      'Signalements souvent ignorés',
                      background: cs.errorContainer,
                      foreground: cs.onErrorContainer,
                    ),
                  if (singleTarget)
                    _Tag(
                      'Vise toujours le même auteur',
                      background: cs.errorContainer,
                      foreground: cs.onErrorContainer,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
