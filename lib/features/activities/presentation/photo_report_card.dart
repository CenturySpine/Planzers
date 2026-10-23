import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/activities/data/activity_photo.dart';
import 'package:planerz/features/activities/data/activity_photos_repository.dart';
import 'package:planerz/features/messaging/presentation/chat_image_viewer.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';

/// Texts of a [PhotoReportCard], given by the caller: the administration
/// section is not localized.
typedef PhotoReportCardLabels = ({
  String reason,
  String Function(String name) author,
  String Function(String name) reporter,
  String unknownMember,
  String gone,
  String dismiss,
  String delete,
  String Function(Object error) error,
});

/// One report of a shared photo: the photo while it is still visible, who
/// shared and reported it, and the moderation actions (dismiss the report,
/// delete the photo with its reports).
class PhotoReportCard extends ConsumerWidget {
  const PhotoReportCard({
    super.key,
    required this.report,
    required this.allReports,
    required this.heading,
    required this.labels,
    required this.crossCache,
    required this.confirmDeletion,
  });

  final PhotoReport report;

  /// Every report of the trip, so deleting the photo removes all of its.
  final List<PhotoReport> allReports;

  /// The activity, or the trip and activity, the photo belongs to.
  final String heading;
  final PhotoReportCardLabels labels;
  final CrossCache crossCache;
  final Future<bool> Function(BuildContext context) confirmDeletion;

  static const double _thumbExtent = 72;

  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(activityPhotosRepositoryProvider)
          .dismissReport(tripId: report.tripId, reportId: report.id);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(labels.error(error))));
    }
  }

  Future<void> _deletePhoto(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await confirmDeletion(context)) return;
    try {
      await ref.read(activityPhotosRepositoryProvider).deletePhotoAsModerator(
        tripId: report.tripId,
        ownerId: report.photoOwnerId,
        photoId: report.photoId,
        reportIds: [
          for (final other in allReports)
            if (other.photoKey == report.photoKey) other.id,
        ],
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(labels.error(error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final photoAsync = ref.watch(activityPhotoStreamProvider((
      tripId: report.tripId,
      ownerId: report.photoOwnerId,
      photoId: report.photoId,
    )));
    // A photo made private can no longer be read: it counts as gone.
    final photo = photoAsync.asData?.value;
    final isGone = !photoAsync.isLoading && photo == null;
    final names = ref.watch(tripMemberResolvedLabelsProvider(report.tripId));
    String nameOf(String uid) => names[uid] ?? labels.unknownMember;
    final createdAt = report.createdAt;
    final reporterLine = [
      labels.reporter(nameOf(report.reporterId)),
      if (createdAt != null)
        DateFormat.yMMMd(Localizations.localeOf(context).toString())
            .add_Hm()
            .format(createdAt.toLocal()),
    ].join(' · ');

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
                      Text(labels.reason, style: textTheme.bodyMedium),
                      const SizedBox(height: 2),
                      Text(
                        labels.author(nameOf(report.photoOwnerId)),
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      Text(
                        reporterLine,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      if (isGone) ...[
                        const SizedBox(height: 4),
                        Text(
                          labels.gone,
                          style: textTheme.bodySmall?.copyWith(color: cs.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: () => _dismiss(context, ref),
                    child: Text(labels.dismiss),
                  ),
                  if (photo != null)
                    FilledButton.tonal(
                      onPressed: () => _deletePhoto(context, ref),
                      child: Text(labels.delete),
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
