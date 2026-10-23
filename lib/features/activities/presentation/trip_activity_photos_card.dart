import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/activity_photo.dart';
import 'package:planerz/features/activities/data/activity_photos_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// How many of [photos] belong to activities planned on the same (local) day
/// as [day]. Each activity's current date is used, so the photos of a moved
/// activity count on its new day.
int activityPhotosCountOnDay({
  required Iterable<ActivityPhoto> photos,
  required Map<String, TripActivity> activitiesById,
  required DateTime day,
}) {
  final target = tripActivityDateOnly(day);
  return photos.where((photo) {
    final plannedAt = activitiesById[photo.activityId]?.plannedAt;
    return plannedAt != null &&
        tripActivitiesSameDay(tripActivityDateOnly(plannedAt), target);
  }).length;
}

/// The photos of an activity: the current traveler's own, then those the
/// other members shared (outlined). Adding is for planned activities only,
/// within the daily limit. Hidden for an unplanned activity without photos.
class TripActivityPhotosCard extends ConsumerStatefulWidget {
  const TripActivityPhotosCard({
    super.key,
    required this.tripId,
    required this.activity,
  });

  final String tripId;
  final TripActivity activity;

  @override
  ConsumerState<TripActivityPhotosCard> createState() =>
      _TripActivityPhotosCardState();
}

class _TripActivityPhotosCardState
    extends ConsumerState<TripActivityPhotosCard> {
  static const double _thumbExtent = 72;

  final _crossCache = CrossCache();

  /// Photos of the current batch still to upload; null when idle.
  int? _pendingUploads;

  Future<List<XFile>> _pick(int remaining) async {
    final picker = ImagePicker();
    final maxSide = activityPhotoMaxSide.toDouble();
    // The multi-picker needs a limit of at least 2.
    if (remaining >= 2) {
      return picker.pickMultiImage(
        maxWidth: maxSide,
        maxHeight: maxSide,
        imageQuality: 80,
        limit: remaining,
      );
    }
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: 80,
    );
    return [if (file != null) file];
  }

  Future<void> _addPhotos(int remaining) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final List<XFile> picked;
    try {
      picked = await _pick(remaining);
    } catch (error) {
      debugPrint('activity photo pick failed: $error');
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.activityPhotosAddFailed)));
      return;
    }
    if (picked.isEmpty || !mounted) return;
    // Some platforms ignore the picker limit.
    if (picked.length > remaining) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.activityPhotosDayLimit(activityPhotosMaxPerDay)),
        ),
      );
    }
    final files = picked.take(remaining).toList(growable: false);
    final repository = ref.read(activityPhotosRepositoryProvider);
    setState(() => _pendingUploads = files.length);
    var failed = false;
    for (final file in files) {
      try {
        await repository.addPhoto(
          tripId: widget.tripId,
          activityId: widget.activity.id,
          bytes: await file.readAsBytes(),
        );
      } catch (error) {
        debugPrint('activity photo upload failed: $error');
        failed = true;
      }
      if (mounted) {
        setState(() => _pendingUploads = (_pendingUploads ?? 1) - 1);
      }
    }
    if (mounted) setState(() => _pendingUploads = null);
    if (failed) {
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.activityPhotosAddFailed)));
    }
  }

  void _open(List<ActivityPhoto> photos, int index) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ActivityPhotoViewerPage(
          tripId: widget.tripId,
          activityId: widget.activity.id,
          initialPhotos: photos,
          initialIndex: index,
          crossCache: _crossCache,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final myUid = ref.watch(activityPhotosRepositoryProvider).currentUid;
    final myPhotos = ref
            .watch(myActivityPhotosStreamProvider(widget.tripId))
            .asData
            ?.value ??
        const <ActivityPhoto>[];
    final photos = ref
        .watch(visibleActivityPhotosProvider(widget.tripId))
        .where((photo) => photo.activityId == widget.activity.id)
        .toList(growable: false);
    final favoriteKey = ref
        .watch(
            activityFavoritePhotosProvider(widget.tripId))[widget.activity.id]
        ?.key;
    final plannedAt = widget.activity.plannedAt;
    if (plannedAt == null && photos.isEmpty) return const SizedBox.shrink();

    final activities =
        ref.watch(tripActivitiesStreamProvider(widget.tripId)).asData?.value ??
            const <TripActivity>[];
    final activitiesById = {
      for (final activity in activities) activity.id: activity,
      widget.activity.id: widget.activity,
    };
    // Only the traveler's own photos count, private ones included.
    final dayCount = plannedAt == null
        ? 0
        : activityPhotosCountOnDay(
            photos: myPhotos,
            activitiesById: activitiesById,
            day: plannedAt,
          );
    final remaining = activityPhotosMaxPerDay - dayCount;
    final pendingUploads = _pendingUploads;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.activityPhotosTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (plannedAt != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          l10n.activityPhotosDayCount(
                            dayCount,
                            activityPhotosMaxPerDay,
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    if (plannedAt != null &&
                        remaining > 0 &&
                        pendingUploads == null)
                      IconButton(
                        tooltip: l10n.activityPhotosAdd,
                        icon: const Icon(PhosphorIconsRegular.plus),
                        onPressed: () => _addPhotos(remaining),
                      )
                    else
                      // Keeps the header height when the button is hidden.
                      const SizedBox(height: 48),
                  ],
                ),
              ),
              if (photos.isNotEmpty || pendingUploads != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (index, photo) in photos.indexed)
                        _PhotoThumb(
                          photo: photo,
                          crossCache: _crossCache,
                          extent: _thumbExtent,
                          isOthers: photo.ownerId != myUid,
                          isFavorite: photo.key == favoriteKey,
                          onTap: () => _open(photos, index),
                        ),
                      for (var i = 0; i < (pendingUploads ?? 0); i++)
                        SizedBox.square(
                          dimension: _thumbExtent,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: SizedBox.square(
                                dimension: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A photo of the grid: another member's is outlined, a private one shows a
/// lock and the traveler's favorite a star.
class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.photo,
    required this.crossCache,
    required this.extent,
    required this.isOthers,
    required this.isFavorite,
    required this.onTap,
  });

  final ActivityPhoto photo;
  final CrossCache crossCache;
  final double extent;
  final bool isOthers;
  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: isOthers ? Border.all(color: cs.tertiary, width: 3) : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: ColoredBox(
            color: cs.surfaceContainerHighest,
            child: SizedBox.square(
              dimension: extent,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image(
                    image: CachedNetworkImage(photo.thumbUrl, crossCache),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      PhosphorIconsRegular.imageBroken,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (!isOthers && !photo.shared)
                    const Positioned(
                      top: 4,
                      left: 4,
                      child: _ThumbBadge(
                        icon: PhosphorIconsRegular.lock,
                        color: Colors.white,
                      ),
                    ),
                  if (isFavorite)
                    const Positioned(
                      top: 4,
                      right: 4,
                      child: _ThumbBadge(
                        icon: PhosphorIconsFill.star,
                        color: AppTokens.accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbBadge extends StatelessWidget {
  const _ThumbBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}

String photoReportReasonLabel(
  AppLocalizations l10n,
  PhotoReportReason reason,
) {
  return switch (reason) {
    PhotoReportReason.inappropriate => l10n.activityPhotosReportInappropriate,
    PhotoReportReason.notConsenting => l10n.activityPhotosReportNotConsenting,
    PhotoReportReason.other => l10n.activityPhotosReportOther,
  };
}

/// Asks to confirm deleting a photo.
Future<bool> confirmActivityPhotoDeletion(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.activityPhotosDeleteTitle),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.commonDelete),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Full-screen view of an activity's photos: swipe between them, pinch to
/// zoom (swiping pauses while zoomed in). On the traveler's own photo:
/// favorite, sharing, caption and deletion; on another member's: its author
/// and caption, favorite and report, plus deletion for trip admins.
class _ActivityPhotoViewerPage extends ConsumerStatefulWidget {
  const _ActivityPhotoViewerPage({
    required this.tripId,
    required this.activityId,
    required this.initialPhotos,
    required this.initialIndex,
    required this.crossCache,
  });

  final String tripId;
  final String activityId;

  /// Shown until the live list is available.
  final List<ActivityPhoto> initialPhotos;
  final int initialIndex;
  final CrossCache crossCache;

  @override
  ConsumerState<_ActivityPhotoViewerPage> createState() =>
      _ActivityPhotoViewerPageState();
}

class _ActivityPhotoViewerPageState
    extends ConsumerState<_ActivityPhotoViewerPage> {
  late final PageController _pageController;

  /// Zoom of the photo shown; the others always start unzoomed.
  final _transformation = TransformationController();
  late int _index;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformation.addListener(_onTransformationChanged);
  }

  @override
  void dispose() {
    _transformation.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    final zoomed = _transformation.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  ActivityPhotosRepository get _repository =>
      ref.read(activityPhotosRepositoryProvider);

  void _showError(ScaffoldMessengerState messenger, Object error) {
    final l10n = AppLocalizations.of(context)!;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
    );
  }

  /// After the photo shown left the list: close when it was the last one,
  /// otherwise the next photo takes its place, unzoomed.
  void _afterRemoval(NavigatorState navigator, {required bool isLast}) {
    if (isLast) {
      navigator.pop();
      return;
    }
    _transformation.value = Matrix4.identity();
  }

  Future<void> _forgetCachedFiles(ActivityPhoto photo) async {
    for (final url in [photo.url, photo.thumbUrl]) {
      try {
        await widget.crossCache.delete(url);
      } catch (_) {}
    }
  }

  Future<void> _delete(ActivityPhoto photo, {required bool isLast}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (!await confirmActivityPhotoDeletion(context)) return;
    try {
      await _repository.deletePhoto(tripId: widget.tripId, photo: photo);
    } catch (error) {
      _showError(messenger, error);
      return;
    }
    await _forgetCachedFiles(photo);
    _afterRemoval(navigator, isLast: isLast);
  }

  Future<void> _deleteAsModerator(
    ActivityPhoto photo, {
    required bool isLast,
    required List<PhotoReport> reports,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (!await confirmActivityPhotoDeletion(context)) return;
    try {
      await _repository.deletePhotoAsModerator(
        tripId: widget.tripId,
        ownerId: photo.ownerId,
        photoId: photo.id,
        reportIds: [
          for (final report in reports)
            if (report.photoKey == photo.key) report.id,
        ],
      );
    } catch (error) {
      _showError(messenger, error);
      return;
    }
    await _forgetCachedFiles(photo);
    _afterRemoval(navigator, isLast: isLast);
  }

  Future<void> _report(ActivityPhoto photo, {required bool isLast}) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final reason = await showModalBottomSheet<PhotoReportReason>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.activityPhotosReportTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final reason in PhotoReportReason.values)
              ListTile(
                title: Text(photoReportReasonLabel(l10n, reason)),
                onTap: () => Navigator.of(ctx).pop(reason),
              ),
          ],
        ),
      ),
    );
    if (reason == null) return;
    try {
      await _repository.reportPhoto(
        tripId: widget.tripId,
        photo: photo,
        reason: reason,
      );
    } catch (error) {
      _showError(messenger, error);
      return;
    }
    messenger
        .showSnackBar(SnackBar(content: Text(l10n.activityPhotosReported)));
    // The photo is now hidden for the reporter.
    _afterRemoval(navigator, isLast: isLast);
  }

  Future<void> _toggleFavorite(ActivityPhoto photo, bool isFavorite) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.setActivityFavorite(
        tripId: widget.tripId,
        activityId: widget.activityId,
        photo: isFavorite ? null : photo,
        myPhotos: ref
                .read(myActivityPhotosStreamProvider(widget.tripId))
                .asData
                ?.value ??
            const <ActivityPhoto>[],
      );
    } catch (error) {
      _showError(messenger, error);
    }
  }

  Future<void> _toggleShared(ActivityPhoto photo) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.setShared(
        tripId: widget.tripId,
        photo: photo,
        shared: !photo.shared,
      );
    } catch (error) {
      _showError(messenger, error);
    }
  }

  Future<void> _editCaption(ActivityPhoto photo) async {
    final messenger = ScaffoldMessenger.of(context);
    final caption = await showDialog<String>(
      context: context,
      builder: (_) => _CaptionDialog(initialCaption: photo.caption),
    );
    if (caption == null || caption.trim() == photo.caption) return;
    try {
      await _repository.updateCaption(
        tripId: widget.tripId,
        photo: photo,
        caption: caption,
      );
    } catch (error) {
      _showError(messenger, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final myUid = ref.watch(activityPhotosRepositoryProvider).currentUid;
    final loaded =
        ref.watch(myActivityPhotosStreamProvider(widget.tripId)).hasValue;
    final photos = loaded
        ? ref
            .watch(visibleActivityPhotosProvider(widget.tripId))
            .where((photo) => photo.activityId == widget.activityId)
            .toList(growable: false)
        : widget.initialPhotos;
    final favoriteKey = ref
        .watch(activityFavoritePhotosProvider(widget.tripId))[widget.activityId]
        ?.key;
    final isAdmin = ref
            .watch(tripStreamProvider(widget.tripId))
            .asData
            ?.value
            ?.isTripAdmin(myUid) ??
        false;
    final reports = isAdmin
        ? ref
                .watch(tripPhotoReportsStreamProvider(widget.tripId))
                .asData
                ?.value ??
            const <PhotoReport>[]
        : const <PhotoReport>[];
    final labels = ref.watch(tripMemberResolvedLabelsProvider(widget.tripId));
    // After a removal the pager keeps its position, now showing the next
    // photo (or the previous one when the last was removed).
    final current =
        photos.isEmpty ? null : photos[_index.clamp(0, photos.length - 1)];
    final isMine = current != null && current.ownerId == myUid;
    final isFavorite = current != null && current.key == favoriteKey;
    final isLast = photos.length == 1;
    final authorName = current == null || isMine
        ? null
        : labels[current.ownerId] ?? l10n.roleParticipant;
    final caption = current?.caption ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // The app bar theme draws ink icons and a light bottom border, both
        // meant for light backgrounds.
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        shape: const Border(),
        elevation: 0,
        actions: [
          if (current != null)
            IconButton(
              tooltip: isFavorite
                  ? l10n.activityPhotosFavoriteRemove
                  : l10n.activityPhotosFavoriteAdd,
              icon: isFavorite
                  ? const Icon(PhosphorIconsFill.star, color: AppTokens.accent)
                  : const Icon(PhosphorIconsRegular.star),
              onPressed: () => _toggleFavorite(current, isFavorite),
            ),
          if (current != null && isMine) ...[
            IconButton(
              tooltip: current.shared
                  ? l10n.activityPhotosMakePrivate
                  : l10n.activityPhotosShare,
              icon: Icon(
                current.shared
                    ? PhosphorIconsRegular.lockOpen
                    : PhosphorIconsRegular.lock,
              ),
              onPressed: () => _toggleShared(current),
            ),
            IconButton(
              tooltip: l10n.activityPhotosCaptionEdit,
              icon: const Icon(PhosphorIconsRegular.pencilSimple),
              onPressed: () => _editCaption(current),
            ),
            IconButton(
              tooltip: l10n.commonDelete,
              icon: const Icon(PhosphorIconsRegular.trash),
              onPressed: () => _delete(current, isLast: isLast),
            ),
          ],
          if (current != null && !isMine) ...[
            IconButton(
              tooltip: l10n.activityPhotosReport,
              icon: const Icon(PhosphorIconsRegular.flag),
              onPressed: () => _report(current, isLast: isLast),
            ),
            if (isAdmin)
              IconButton(
                tooltip: l10n.commonDelete,
                icon: const Icon(PhosphorIconsRegular.trash),
                onPressed: () => _deleteAsModerator(
                  current,
                  isLast: isLast,
                  reports: reports,
                ),
              ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildPager(photos)),
            if (authorName != null || caption.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.25,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    children: [
                      if (authorName != null)
                        Text(
                          authorName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (caption.isNotEmpty)
                        Text(
                          caption,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPager(List<ActivityPhoto> photos) {
    // Also lets a mouse drag the photos on the web.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: PageView.builder(
        controller: _pageController,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
        itemCount: photos.length,
        onPageChanged: (index) {
          _transformation.value = Matrix4.identity();
          setState(() => _index = index);
        },
        itemBuilder: (context, index) {
          final isShown = index == _index;
          return InteractiveViewer(
            key: ValueKey(photos[index].key),
            transformationController: isShown ? _transformation : null,
            panEnabled: isShown && _zoomed,
            minScale: 0.8,
            maxScale: 4,
            child: Center(
              child: Image(
                image: CachedNetworkImage(
                  photos[index].url,
                  widget.crossCache,
                ),
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  );
                },
                errorBuilder: (_, __, ___) => const Icon(
                  PhosphorIconsRegular.imageBroken,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Writes or changes a photo's caption. Returns the text (empty removes the
/// caption), or null when cancelled.
class _CaptionDialog extends StatefulWidget {
  const _CaptionDialog({required this.initialCaption});

  final String initialCaption;

  @override
  State<_CaptionDialog> createState() => _CaptionDialogState();
}

class _CaptionDialogState extends State<_CaptionDialog> {
  late final _controller = TextEditingController(text: widget.initialCaption);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.activityPhotosCaption),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: activityPhotoMaxCaptionLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
