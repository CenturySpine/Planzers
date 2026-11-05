import 'dart:typed_data';

import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/data/activity_photo.dart';
import 'package:planerz/features/expenses/data/expense_attachment.dart';
import 'package:planerz/features/expenses/data/expense_attachments_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

const double _thumbExtent = 72;

/// Picks up to [remaining] receipt photos, from the camera (where the device
/// has one) or the gallery, already reduced like activity photos. Returns
/// their bytes; empty when cancelled or on failure (then reported).
Future<List<Uint8List>> pickExpenseAttachmentPhotos(
  BuildContext context, {
  required int remaining,
}) async {
  if (remaining <= 0) return const [];
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final picker = ImagePicker();
  var source = ImageSource.gallery;
  if (picker.supportsImageSource(ImageSource.camera)) {
    final chosen = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(PhosphorIconsRegular.camera),
              title: Text(l10n.accountTakePhoto),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.images),
              title: Text(l10n.accountChooseFromGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return const [];
    source = chosen;
  }
  final maxSide = activityPhotoMaxSide.toDouble();
  try {
    final List<XFile> picked;
    // The multi-picker needs a limit of at least 2.
    if (source == ImageSource.gallery && remaining >= 2) {
      picked = await picker.pickMultiImage(
        maxWidth: maxSide,
        maxHeight: maxSide,
        imageQuality: 80,
        limit: remaining,
      );
    } else {
      final file = await picker.pickImage(
        source: source,
        maxWidth: maxSide,
        maxHeight: maxSide,
        imageQuality: 80,
      );
      picked = [if (file != null) file];
    }
    // Some platforms ignore the picker limit.
    if (picked.length > remaining) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.expensesAttachmentsLimit(expenseAttachmentsMaxPerExpense),
          ),
        ),
      );
    }
    return [
      for (final file in picked.take(remaining)) await file.readAsBytes(),
    ];
  } catch (error) {
    debugPrint('expense attachment pick failed: $error');
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.expensesAttachmentsAddFailed)),
    );
    return const [];
  }
}

/// The receipts of a saved expense, seen by everyone who sees it. Those who
/// may edit the expense (post not locked) add them, uploaded right away, and
/// delete them from the full-screen view. Hidden for the others while the
/// expense has none.
class ExpenseAttachmentsSection extends ConsumerStatefulWidget {
  const ExpenseAttachmentsSection({
    super.key,
    required this.tripId,
    required this.expenseId,
    required this.canEdit,
  });

  final String tripId;
  final String expenseId;
  final bool canEdit;

  @override
  ConsumerState<ExpenseAttachmentsSection> createState() =>
      _ExpenseAttachmentsSectionState();
}

class _ExpenseAttachmentsSectionState
    extends ConsumerState<ExpenseAttachmentsSection> {
  final _crossCache = CrossCache();

  /// Receipts of the current batch still to upload; null when idle.
  int? _pendingUploads;

  ExpenseAttachmentsScope get _scope =>
      (tripId: widget.tripId, expenseId: widget.expenseId);

  Future<void> _add(int remaining) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final photos =
        await pickExpenseAttachmentPhotos(context, remaining: remaining);
    if (photos.isEmpty || !mounted) return;
    final repository = ref.read(expenseAttachmentsRepositoryProvider);
    setState(() => _pendingUploads = photos.length);
    var failed = false;
    for (final bytes in photos) {
      try {
        await repository.addAttachment(
          tripId: widget.tripId,
          expenseId: widget.expenseId,
          bytes: bytes,
        );
      } catch (error) {
        debugPrint('expense attachment upload failed: $error');
        failed = true;
      }
      if (mounted) {
        setState(() => _pendingUploads = (_pendingUploads ?? 1) - 1);
      }
    }
    if (mounted) setState(() => _pendingUploads = null);
    if (failed) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.expensesAttachmentsAddFailed)),
      );
    }
  }

  void _open(List<ExpenseAttachment> attachments, int index) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ExpenseAttachmentViewerPage(
          tripId: widget.tripId,
          expenseId: widget.expenseId,
          initialAttachments: attachments,
          initialIndex: index,
          crossCache: _crossCache,
          canDelete: widget.canEdit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attachments =
        ref.watch(expenseAttachmentsStreamProvider(_scope)).asData?.value ??
            const <ExpenseAttachment>[];
    final pendingUploads = _pendingUploads;
    if (!widget.canEdit && attachments.isEmpty && pendingUploads == null) {
      return const SizedBox.shrink();
    }
    final remaining = expenseAttachmentsMaxPerExpense - attachments.length;
    return _AttachmentsBlock(
      onAdd: widget.canEdit && remaining > 0 && pendingUploads == null
          ? () => _add(remaining)
          : null,
      children: [
        for (final (index, attachment) in attachments.indexed)
          _AttachmentThumb(
            image: CachedNetworkImage(attachment.thumbUrl, _crossCache),
            onTap: () => _open(attachments, index),
          ),
        for (var i = 0; i < (pendingUploads ?? 0); i++) const _UploadingThumb(),
      ],
    );
  }
}

/// The receipts picked for an expense not saved yet (uploaded once it is):
/// added with [onAdd], each removed with its cross.
class PendingExpenseAttachments extends StatelessWidget {
  const PendingExpenseAttachments({
    super.key,
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  final List<Uint8List> photos;

  /// Null hides the add button (limit reached, or saving).
  final VoidCallback? onAdd;

  /// Null while saving.
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _AttachmentsBlock(
      onAdd: onAdd,
      children: [
        for (final (index, bytes) in photos.indexed)
          Stack(
            clipBehavior: Clip.none,
            children: [
              _AttachmentThumb(image: MemoryImage(bytes)),
              if (onRemove != null)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => onRemove!(index),
                      child: Tooltip(
                        message: l10n.commonDelete,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            PhosphorIconsRegular.x,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Title, add button and the thumbnails of the receipts.
class _AttachmentsBlock extends StatelessWidget {
  const _AttachmentsBlock({required this.onAdd, required this.children});

  final VoidCallback? onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.expensesAttachmentsTitle,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (onAdd != null)
              IconButton(
                tooltip: l10n.expensesAttachmentsAdd,
                icon: const Icon(PhosphorIconsRegular.plus),
                onPressed: onAdd,
              )
            else
              // Keeps the header height when the button is hidden.
              const SizedBox(height: 48),
          ],
        ),
        if (children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 8, runSpacing: 8, children: children),
          ),
      ],
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({required this.image, this.onTap});

  final ImageProvider image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SizedBox.square(
            dimension: _thumbExtent,
            child: Image(
              image: image,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                PhosphorIconsRegular.imageBroken,
                color: AppTokens.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadingThumb extends StatelessWidget {
  const _UploadingThumb();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _thumbExtent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

/// Full-screen view of an expense's receipts: swipe between them, pinch to
/// zoom (swiping pauses while zoomed in), and delete for those who may edit
/// the expense.
class _ExpenseAttachmentViewerPage extends ConsumerStatefulWidget {
  const _ExpenseAttachmentViewerPage({
    required this.tripId,
    required this.expenseId,
    required this.initialAttachments,
    required this.initialIndex,
    required this.crossCache,
    required this.canDelete,
  });

  final String tripId;
  final String expenseId;

  /// Shown until the live list is available.
  final List<ExpenseAttachment> initialAttachments;
  final int initialIndex;
  final CrossCache crossCache;
  final bool canDelete;

  @override
  ConsumerState<_ExpenseAttachmentViewerPage> createState() =>
      _ExpenseAttachmentViewerPageState();
}

class _ExpenseAttachmentViewerPageState
    extends ConsumerState<_ExpenseAttachmentViewerPage> {
  late final PageController _pageController;

  /// Zoom of the receipt shown; the others always start unzoomed.
  final _transformation = TransformationController();
  late int _index;
  bool _zoomed = false;

  ExpenseAttachmentsScope get _scope =>
      (tripId: widget.tripId, expenseId: widget.expenseId);

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

  Future<void> _delete(
    ExpenseAttachment attachment, {
    required bool isLast,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.expensesAttachmentsDeleteTitle),
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
    if (confirmed != true) return;
    try {
      await ref.read(expenseAttachmentsRepositoryProvider).deleteAttachment(
            tripId: widget.tripId,
            expenseId: widget.expenseId,
            attachment: attachment,
          );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
      );
      return;
    }
    for (final url in [attachment.url, attachment.thumbUrl]) {
      try {
        await widget.crossCache.delete(url);
      } catch (_) {}
    }
    if (isLast) {
      navigator.pop();
      return;
    }
    // The pager keeps its position, now showing the next receipt.
    _transformation.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final live = ref.watch(expenseAttachmentsStreamProvider(_scope));
    final attachments = live.asData?.value ?? widget.initialAttachments;
    final current = attachments.isEmpty
        ? null
        : attachments[_index.clamp(0, attachments.length - 1)];

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
          if (current != null && widget.canDelete)
            IconButton(
              tooltip: l10n.commonDelete,
              icon: const Icon(PhosphorIconsRegular.trash),
              onPressed: () =>
                  _delete(current, isLast: attachments.length == 1),
            ),
        ],
      ),
      body: SafeArea(
        // Also lets a mouse drag the receipts on the web.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context)
              .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
          child: PageView.builder(
            controller: _pageController,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            itemCount: attachments.length,
            onPageChanged: (index) {
              _transformation.value = Matrix4.identity();
              setState(() => _index = index);
            },
            itemBuilder: (context, index) {
              final isShown = index == _index;
              return InteractiveViewer(
                key: ValueKey(attachments[index].id),
                transformationController: isShown ? _transformation : null,
                panEnabled: isShown && _zoomed,
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: Image(
                    image: CachedNetworkImage(
                      attachments[index].url,
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
        ),
      ),
    );
  }
}
