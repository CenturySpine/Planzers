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

Future<void> linkWalletDocumentToActivity({
  required BuildContext context,
  required String tripId,
  required String documentId,
  required String? activityId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(walletRepositoryProvider).setDocumentActivity(
          tripId: tripId,
          documentId: documentId,
          activityId: activityId,
        );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          activityId == null
              ? l10n.walletActivityUnlinked
              : l10n.walletActivityLinked,
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
  final sorted = _sortedForPicker(activities);
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
              l10n.walletLinkActivityPickerTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l10n.walletNoActivityToLink),
            ),
          for (final activity in sorted)
            ListTile(
              leading: _ActivityCategoryAvatar(activity: activity),
              title: Text(
                activity.label.trim().isEmpty
                    ? l10n.activitiesUntitled
                    : activity.label.trim(),
              ),
              subtitle: switch (_plannedLabel(context, activity)) {
                final String label => Text(label),
                null => null,
              },
              onTap: () => Navigator.of(sheetContext).pop(activity.id),
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

/// Bottom bar of the document viewer showing the linked activity: tap to
/// open it, or remove the link.
class WalletLinkedActivityBar extends StatelessWidget {
  const WalletLinkedActivityBar({
    super.key,
    required this.activity,
    required this.onOpen,
    required this.onUnlink,
  });

  final TripActivity activity;
  final VoidCallback onOpen;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final plannedLabel = _plannedLabel(context, activity);
    return Material(
      color: AppTokens.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTokens.divider)),
          ),
          child: ListTile(
            leading: _ActivityCategoryAvatar(activity: activity),
            title: Text(
              activity.label.trim().isEmpty
                  ? l10n.activitiesUntitled
                  : activity.label.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: plannedLabel == null ? null : Text(plannedLabel),
            onTap: onOpen,
            trailing: IconButton(
              tooltip: l10n.walletUnlinkActivity,
              icon: const Icon(PhosphorIconsRegular.linkBreak),
              onPressed: onUnlink,
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
          await container.read(walletRepositoryProvider).setDocumentActivity(
                tripId: tripId,
                documentId: document.id,
                activityId: activityId,
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
