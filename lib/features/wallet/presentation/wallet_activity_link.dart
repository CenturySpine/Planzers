import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_category_presentation.dart';
import 'package:planerz/features/activities/presentation/trip_activity_create_form.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/features/wallet/data/wallet_document_category.dart';
import 'package:planerz/features/wallet/data/wallet_repository.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Planning categories offered when creating an activity from a document:
/// the same groups as the planning "+" menu, picked from the document type.
({List<TripActivityCategory> allowed, TripActivityCategory initial})
    activityCategoriesForWalletDocument(WalletDocumentCategory category) {
  switch (category) {
    case WalletDocumentCategory.plane:
    case WalletDocumentCategory.train:
    case WalletDocumentCategory.bus:
    case WalletDocumentCategory.boat:
    case WalletDocumentCategory.vehicleRental:
      return (
        allowed: const [TripActivityCategory.transport],
        initial: TripActivityCategory.transport,
      );
    case WalletDocumentCategory.lodging:
      return (
        allowed: const [TripActivityCategory.accommodation],
        initial: TripActivityCategory.accommodation,
      );
    case WalletDocumentCategory.activity:
    case WalletDocumentCategory.identity:
    case WalletDocumentCategory.insurance:
    case WalletDocumentCategory.other:
      return (
        allowed: TripActivityCategory.values
            .where((c) =>
                c != TripActivityCategory.accommodation &&
                c != TripActivityCategory.transport)
            .toList(growable: false),
        initial: TripActivityCategory.visit,
      );
  }
}

/// Adds ([linked] true) or removes a document–activity link, with feedback.
Future<void> linkWalletDocumentToActivity({
  required BuildContext context,
  required String tripId,
  required WalletDocument document,
  required String activityId,
  required bool linked,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(walletRepositoryProvider).setDocumentActivityLink(
          tripId: tripId,
          document: document,
          activityId: activityId,
          linked: linked,
        );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          linked ? l10n.walletActivityLinked : l10n.walletActivityUnlinked,
        ),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
    );
  }
}

String? _plannedLabel(BuildContext context, TripActivity activity) {
  final plannedAt = activity.plannedAt;
  if (plannedAt == null) return null;
  return DateFormat.yMMMEd(Localizations.localeOf(context).toString())
      .add_Hm()
      .format(plannedAt.toLocal());
}

/// Planned activities first (chronological), then the others by label.
List<TripActivity> _sortedForPicker(List<TripActivity> activities) {
  final sorted = [...activities];
  sorted.sort((a, b) {
    final aAt = a.plannedAt;
    final bAt = b.plannedAt;
    if (aAt != null && bAt != null) return aAt.compareTo(bAt);
    if (aAt != null) return -1;
    if (bAt != null) return 1;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return sorted;
}

/// Returns the chosen activity id, or null when dismissed.
Future<String?> pickActivityForWalletDocument(
  BuildContext context, {
  required List<TripActivity> activities,
}) {
  final l10n = AppLocalizations.of(context)!;
  return _showPickerSheet(
    context,
    title: l10n.walletLinkActivityPickerTitle,
    emptyLabel: l10n.walletNoActivityToLink,
    tiles: [
      for (final activity in _sortedForPicker(activities))
        (
          id: activity.id,
          leading: _ActivityCategoryAvatar(activity: activity),
          title: activity.label.trim().isEmpty
              ? l10n.activitiesUntitled
              : activity.label.trim(),
          subtitle: _plannedLabel(context, activity),
        ),
    ],
  );
}

/// Returns the chosen document id, or null when dismissed.
Future<String?> pickWalletDocumentForActivity(
  BuildContext context, {
  required List<WalletDocument> documents,
}) {
  final l10n = AppLocalizations.of(context)!;
  return _showPickerSheet(
    context,
    title: l10n.walletLinkDocumentPickerTitle,
    emptyLabel: l10n.walletEmpty,
    tiles: [
      for (final document in documents)
        (
          id: document.id,
          leading: Icon(document.category.icon),
          title: document.name,
          subtitle: walletDocumentSubtitle(context, document),
        ),
    ],
  );
}

typedef _PickerTile = ({
  String id,
  Widget leading,
  String title,
  String? subtitle,
});

Future<String?> _showPickerSheet(
  BuildContext context, {
  required String title,
  required String emptyLabel,
  required List<_PickerTile> tiles,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (tiles.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(emptyLabel),
            ),
          for (final tile in tiles)
            ListTile(
              leading: tile.leading,
              title: Text(tile.title),
              subtitle: switch (tile.subtitle) {
                final String label => Text(label),
                null => null,
              },
              onTap: () => Navigator.of(sheetContext).pop(tile.id),
            ),
        ],
      ),
    ),
  );
}

class _ActivityCategoryAvatar extends StatelessWidget {
  const _ActivityCategoryAvatar({required this.activity});

  final TripActivity activity;

  @override
  Widget build(BuildContext context) {
    final group = activity.category.filterGroup;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: group.filterLightBgColor,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Icon(
        activity.category.categoryIcon,
        size: 20,
        color: group.filterColor,
      ),
    );
  }
}

/// Bottom area of the document viewer listing the linked activities: tap
/// one to open it, or remove its link. Scrolls past a few entries so the
/// document keeps most of the screen.
class WalletLinkedActivitiesBar extends StatelessWidget {
  const WalletLinkedActivitiesBar({
    super.key,
    required this.activities,
    required this.onOpen,
    required this.onUnlink,
  });

  final List<TripActivity> activities;
  final ValueChanged<TripActivity> onOpen;
  final ValueChanged<TripActivity> onUnlink;

  static const double _maxHeight = 3.5 * 64;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: AppTokens.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTokens.divider)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final activity in _sortedForPicker(activities))
                  ListTile(
                    leading: _ActivityCategoryAvatar(activity: activity),
                    title: Text(
                      activity.label.trim().isEmpty
                          ? l10n.activitiesUntitled
                          : activity.label.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: switch (_plannedLabel(context, activity)) {
                      final String label => Text(label),
                      null => null,
                    },
                    onTap: () => onOpen(activity),
                    trailing: IconButton(
                      tooltip: l10n.walletUnlinkActivity,
                      icon: const Icon(PhosphorIconsRegular.linkBreak),
                      onPressed: () => onUnlink(activity),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Activity creation panel shown over (phone) or beside (wide screen) an
/// open document, so its details stay readable while filling the form.
/// The new activity is linked to the document.
class WalletCreateActivityPanel extends StatelessWidget {
  const WalletCreateActivityPanel({
    super.key,
    required this.tripId,
    required this.document,
    required this.onDone,
    this.scrollController,
    this.onHandleDrag,
    this.onHandleDragEnd,
  });

  final String tripId;
  final WalletDocument document;
  final VoidCallback onDone;
  final ScrollController? scrollController;

  /// Set for the phone sheet: the handle resizes it (vertical delta in
  /// pixels), including with a mouse, which does not drag scrollables.
  final ValueChanged<double>? onHandleDrag;
  final VoidCallback? onHandleDragEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final categories = activityCategoriesForWalletDocument(document.category);
    final eventDate = document.eventDate;
    return TripActivityCreateForm(
      tripId: tripId,
      allowedCategories: categories.allowed,
      initialCategory: categories.initial,
      initialLabel: document.name,
      initialPlannedDay:
          eventDate == null ? null : tripActivityDateOnly(eventDate.toLocal()),
      scrollController: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onHandleDrag != null)
              MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) =>
                      onHandleDrag!(details.delta.dy),
                  onVerticalDragEnd: (_) => onHandleDragEnd?.call(),
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTokens.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 16),
            Text(
              l10n.activitiesNewActivity,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
      onCreated: (activityId) async {
        final messenger = ScaffoldMessenger.of(context);
        final container = ProviderScope.containerOf(context, listen: false);
        onDone();
        try {
          await container.read(walletRepositoryProvider).setDocumentActivityLink(
                tripId: tripId,
                document: document,
                activityId: activityId,
                linked: true,
              );
          messenger.showSnackBar(SnackBar(content: Text(l10n.activitiesAdded)));
        } catch (error) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.commonErrorWithDetails(error.toString())),
            ),
          );
        }
      },
    );
  }
}
