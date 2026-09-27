import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/core/network/connectivity_provider.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/features/wallet/data/wallet_repository.dart';
import 'package:planerz/features/wallet/presentation/wallet_activity_link.dart';
import 'package:planerz/features/wallet/presentation/wallet_barcode_view.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Keyed by storage path (a stable value) so rebuilds reuse the same request.
final _walletFileUrlProvider =
    FutureProvider.autoDispose.family<String, String>((ref, storagePath) {
  return ref.watch(walletRepositoryProvider).fileDownloadUrl(storagePath);
});

/// Full-screen view of one document. Follows the live document so an edit
/// made from the menu shows immediately; closes itself once deleted.
///
/// An activity can be created from the document while it stays visible
/// (sheet over it on phones, side panel on wide screens); the document then
/// links to that activity, shown in a bottom bar.
class WalletDocumentViewerPage extends ConsumerStatefulWidget {
  const WalletDocumentViewerPage({
    super.key,
    required this.tripId,
    required this.documentId,
    this.openedFromActivityId,
  });

  final String tripId;
  final String documentId;

  /// Set when opened from that activity's page: opening the linked activity
  /// then just goes back to it.
  final String? openedFromActivityId;

  @override
  ConsumerState<WalletDocumentViewerPage> createState() =>
      _WalletDocumentViewerPageState();
}

enum _ActivityAction { create, link }

class _WalletDocumentViewerPageState
    extends ConsumerState<WalletDocumentViewerPage> {
  static const double _wideLayoutMinWidth = 840;
  static const double _sidePanelWidth = 400;
  static const List<double> _sheetSizes = [0.2, 0.55, 0.95];

  final _sheetController = DraggableScrollableController();
  bool _creatingActivity = false;

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _dragSheet(double deltaY, double availableHeight) {
    if (!_sheetController.isAttached || availableHeight <= 0) return;
    _sheetController.jumpTo(
      (_sheetController.size - deltaY / availableHeight)
          .clamp(_sheetSizes.first, _sheetSizes.last),
    );
  }

  void _snapSheet() {
    if (!_sheetController.isAttached) return;
    final size = _sheetController.size;
    final nearest = _sheetSizes.reduce(
      (a, b) => (a - size).abs() <= (b - size).abs() ? a : b,
    );
    _sheetController.animateTo(
      nearest,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  String get _tripId => widget.tripId;

  void _openActivity(TripActivity activity) {
    if (activity.id == widget.openedFromActivityId) {
      Navigator.of(context).maybePop();
      return;
    }
    context.push('/trips/$_tripId/activities/${activity.id}');
  }

  Future<void> _linkExisting(
    WalletDocument document,
    List<TripActivity> activities,
  ) async {
    final activityId = await pickActivityForWalletDocument(
      context,
      activities: activities,
    );
    if (activityId == null || !mounted) return;
    await linkWalletDocumentToActivity(
      context: context,
      tripId: _tripId,
      documentId: document.id,
      activityId: activityId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final documents =
        ref.watch(myWalletDocumentsStreamProvider(_tripId)).asData?.value;
    final document =
        documents?.where((doc) => doc.id == widget.documentId).firstOrNull;
    final activities =
        ref.watch(tripActivitiesStreamProvider(_tripId)).asData?.value;
    final trip = ref.watch(tripStreamProvider(_tripId)).asData?.value;
    final canCreateActivity = trip != null &&
        canSuggestActivityForTrip(
          trip: trip,
          userId: FirebaseAuth.instance.currentUser?.uid.trim(),
        );
    final linkedActivityId = document?.activityId;
    // A link to an activity deleted since is treated as no link.
    final linkedActivity = linkedActivityId == null
        ? null
        : activities?.where((a) => a.id == linkedActivityId).firstOrNull;
    final canLink = activities != null && activities.isNotEmpty;
    final showActivityMenu = document != null &&
        activities != null &&
        linkedActivity == null &&
        !_creatingActivity &&
        (canCreateActivity || canLink);

    return Theme(
      data: AppTokens.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: AppTokens.scaffoldBackground,
        appBar: AppBar(
          title: Text(document?.name ?? ''),
          actions: [
            if (showActivityMenu)
              PopupMenuButton<_ActivityAction>(
                tooltip: l10n.walletCreateActivity,
                icon: const Icon(PhosphorIconsRegular.calendarPlus),
                onSelected: (action) => switch (action) {
                  _ActivityAction.create =>
                    setState(() => _creatingActivity = true),
                  _ActivityAction.link => _linkExisting(document, activities),
                },
                itemBuilder: (context) => [
                  if (canCreateActivity)
                    PopupMenuItem(
                      value: _ActivityAction.create,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(PhosphorIconsRegular.plus),
                        title: Text(l10n.walletCreateActivity),
                      ),
                    ),
                  if (canLink)
                    PopupMenuItem(
                      value: _ActivityAction.link,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(PhosphorIconsRegular.link),
                        title: Text(l10n.walletLinkActivity),
                      ),
                    ),
                ],
              ),
            if (_creatingActivity)
              IconButton(
                tooltip: l10n.commonClose,
                icon: const Icon(PhosphorIconsRegular.x),
                onPressed: () => setState(() => _creatingActivity = false),
              ),
            if (document != null)
              WalletDocumentActionsButton(
                tripId: _tripId,
                document: document,
                onDeleted: () => Navigator.of(context).maybePop(),
              ),
          ],
        ),
        body: document == null
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final content =
                      _WalletDocumentContent(tripId: _tripId, document: document);
                  if (_creatingActivity) {
                    void onDone() => setState(() => _creatingActivity = false);
                    if (constraints.maxWidth >= _wideLayoutMinWidth) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: content),
                          const VerticalDivider(width: 1),
                          SizedBox(
                            width: _sidePanelWidth,
                            child: Material(
                              color: AppTokens.surface,
                              child: WalletCreateActivityPanel(
                                tripId: _tripId,
                                document: document,
                                onDone: onDone,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    // Not modal: the visible part of the document can still
                    // be scrolled and zoomed while filling the form.
                    return Stack(
                      children: [
                        Positioned.fill(child: content),
                        DraggableScrollableSheet(
                          controller: _sheetController,
                          initialChildSize: _sheetSizes[1],
                          minChildSize: _sheetSizes.first,
                          maxChildSize: _sheetSizes.last,
                          snap: true,
                          snapSizes: _sheetSizes,
                          builder: (context, scrollController) => Material(
                            color: AppTokens.surface,
                            elevation: 8,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(AppTokens.radiusLg),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: WalletCreateActivityPanel(
                              tripId: _tripId,
                              document: document,
                              onDone: onDone,
                              scrollController: scrollController,
                              onHandleDrag: (deltaY) => _dragSheet(
                                deltaY,
                                constraints.maxHeight,
                              ),
                              onHandleDragEnd: _snapSheet,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: content),
                      if (linkedActivity != null)
                        WalletLinkedActivityBar(
                          activity: linkedActivity,
                          onOpen: () => _openActivity(linkedActivity),
                          onUnlink: () => linkWalletDocumentToActivity(
                            context: context,
                            tripId: _tripId,
                            documentId: document.id,
                            activityId: null,
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _WalletDocumentContent extends ConsumerWidget {
  const _WalletDocumentContent({required this.tripId, required this.document});

  final String tripId;
  final WalletDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final barcode = document.barcode;
    if (barcode != null) {
      return ColoredBox(
        color: Colors.white,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: WalletBarcodeView(barcode: barcode),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  barcode.payload,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final file = document.file;
    if (file == null) return const SizedBox.shrink();

    final key = (
      tripId: tripId,
      documentId: document.id,
      storagePath: file.storagePath,
    );
    final bytesAsync = ref.watch(_walletFileBytesProvider(key));
    return bytesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ViewerMessage(
        icon: error is WalletUnavailableOfflineException
            ? PhosphorIconsRegular.cloudSlash
            : PhosphorIconsRegular.warningCircle,
        text: error is WalletUnavailableOfflineException
            ? l10n.walletUnavailableOffline
            : l10n.walletOpenFailed,
        onRetry: () => ref.invalidate(_walletFileBytesProvider(key)),
      ),
      data: (bytes) {
        if (file.isPdf) {
          return PdfViewer.data(bytes, sourceName: 'wallet-${document.id}');
        }
        return InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              // e.g. HEIC outside Safari: let the browser/OS handle the file.
              errorBuilder: (context, _, __) => _OpenFilePanel(
                document: document,
              ),
            ),
          ),
        );
      },
    );
  }
}

typedef _WalletFileKey = ({
  String tripId,
  String documentId,
  String storagePath,
});

/// Stable string key: list updates (renames, other documents) do not reload
/// the file.
final _walletFileBytesProvider =
    FutureProvider.autoDispose.family<Uint8List, _WalletFileKey>((ref, key) {
  // Read, not watched: a document already shown must not reload (and fail)
  // when the connection drops; "Réessayer" re-reads after reconnecting.
  final offline = ref.read(isOfflineProvider);
  return ref.watch(walletRepositoryProvider).readFileBytes(
        tripId: key.tripId,
        documentId: key.documentId,
        storagePath: key.storagePath,
        allowNetwork: !offline,
      );
});

class _ViewerMessage extends StatelessWidget {
  const _ViewerMessage({
    required this.icon,
    required this.text,
    required this.onRetry,
  });

  final IconData icon;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
          ],
        ),
      ),
    );
  }
}

/// For images the app cannot render itself (e.g. HEIC outside Safari): the
/// URL is resolved beforehand so the tap opens it directly, which keeps
/// browsers from blocking the new tab as an unsolicited popup. Online only.
class _OpenFilePanel extends ConsumerWidget {
  const _OpenFilePanel({required this.document});

  final WalletDocument document;

  Future<void> _open(BuildContext context, String url) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.walletOpenFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final file = document.file;
    final resolvedUrl = file == null
        ? null
        : ref.watch(_walletFileUrlProvider(file.storagePath)).asData?.value;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(document.category.icon, size: 56),
            const SizedBox(height: 12),
            Text(
              file?.originalFileName ?? document.name,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (resolvedUrl == null)
              Text(l10n.walletOpenFailed)
            else
              FilledButton.icon(
                onPressed: () => _open(context, resolvedUrl),
                icon: const Icon(PhosphorIconsRegular.arrowSquareOut),
                label: Text(l10n.walletOpenFile),
              ),
          ],
        ),
      ),
    );
  }
}
