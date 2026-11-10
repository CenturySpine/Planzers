import 'dart:async';

import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:planerz/core/presentation/pz_components.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/presentation/ai_billed_support_banner.dart';
import 'package:planerz/features/ai_quotas/data/ai_quota_models.dart';
import 'package:planerz/features/ai_quotas/data/ai_quotas_repository.dart';
import 'package:planerz/features/ai_quotas/presentation/ai_error_message.dart';
import 'package:planerz/features/auth/data/users_repository.dart'
    show
        stableUsersIdsKey,
        usersDataByIdsKeyStreamProvider,
        usersRepositoryProvider;
import 'package:planerz/features/ingredients/presentation/ingredient_line_editor.dart';
import 'package:planerz/features/packing/data/packing_repository.dart';
import 'package:planerz/features/shopping/data/shopping_category.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';
import 'package:planerz/features/shopping/data/shopping_list_locks.dart';
import 'package:planerz/features/shopping/data/shopping_repository.dart';
import 'package:planerz/features/shopping/presentation/widgets/shopping_assignee_dialog.dart';
import 'package:planerz/features/shopping/presentation/widgets/shopping_item_row.dart';
import 'package:planerz/features/shopping/presentation/widgets/shopping_list_status_filter.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_member.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/presentation/name_list_search.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Reserved Firestore category id for consolidated rows added from the app (manual add).
const String kUnassignedConsolidatedCategoryId = '999';

const ConsolidatedShoppingCategory kUnassignedConsolidatedCategoryMeta =
    ConsolidatedShoppingCategory(
  id: '999',
  fr: 'Non assigné',
  en: 'Unassigned',
);

class TripShoppingPage extends ConsumerWidget {
  const TripShoppingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = TripScope.of(context);
    final itemsAsync = ref.watch(tripShoppingItemsStreamProvider(trip.id));
    // The current user's private items join the shared ones in the free list.
    // They never hold the page back: the shared list shows on its own.
    final privateItems = ref
            .watch(tripPrivateShoppingItemsStreamProvider(trip.id))
            .asData
            ?.value ??
        const <ShoppingItem>[];

    return itemsAsync.when(
      data: (items) => _ShoppingList(
        tripId: trip.id,
        items: _withPrivateItems(items, privateItems),
        trip: trip,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(AppLocalizations.of(context)!.commonErrorWithDetails(e.toString())),
        ),
      ),
    );
  }
}

/// The free list as the current user sees it: shared and private items in
/// one order. While an item moves between the two lists it may briefly be in
/// both: the private copy wins.
List<ShoppingItem> _withPrivateItems(
  List<ShoppingItem> sharedItems,
  List<ShoppingItem> privateItems,
) {
  if (privateItems.isEmpty) return sharedItems;
  final privateIds = {for (final item in privateItems) item.id};
  return [
    ...sharedItems.where((item) => !privateIds.contains(item.id)),
    ...privateItems,
  ]..sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });
}

class _ShoppingList extends ConsumerStatefulWidget {
  const _ShoppingList({
    required this.tripId,
    required this.items,
    required this.trip,
  });

  final String tripId;
  final List<ShoppingItem> items;
  final Trip trip;

  @override
  ConsumerState<_ShoppingList> createState() => _ShoppingListState();
}

class _ShoppingListState extends ConsumerState<_ShoppingList>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _searchController;
  late final TabController _tabController;
  int _currentTabIndex = 0;
  ShoppingListStatusFilter _manualListStatusFilter = ShoppingListStatusFilter.all;
  bool _manualOnlyClaimedByMe = false;
  bool _manualOnlyPrivate = false;
  ShoppingListStatusFilter _consolidatedListStatusFilter =
      ShoppingListStatusFilter.all;
  bool _consolidatedOnlyClaimedByMe = false;
  String? _pendingAutofocusItemId;
  bool _isConsolidating = false;
  bool _suppressRemoteConsolidatedSync = false;
  bool _isSavingConsolidated = false;
  String? _appliedRemoteConsolidatedFingerprint;
  ConsolidatedShoppingResult? _consolidationResult;
  List<_ConsolidatedEditableItem> _consolidatedItems = const [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_onTabChanged);
  }

  /// The add button depends on the tab, so it is rebuilt on tab changes.
  void _onTabChanged() {
    if (_tabController.index == _currentTabIndex) return;
    setState(() => _currentTabIndex = _tabController.index);
  }

  @override
  void didUpdateWidget(covariant _ShoppingList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripId != widget.tripId) {
      _suppressRemoteConsolidatedSync = false;
      _isSavingConsolidated = false;
      _appliedRemoteConsolidatedFingerprint = null;
      _consolidationResult = null;
      _consolidatedItems = const [];
      _manualListStatusFilter = ShoppingListStatusFilter.all;
      _manualOnlyClaimedByMe = false;
      _manualOnlyPrivate = false;
      _consolidatedListStatusFilter = ShoppingListStatusFilter.all;
      _consolidatedOnlyClaimedByMe = false;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _addFromFabAddItem(
    BuildContext context, {
    required bool manualLockRestrictsEditing,
    required bool consolidatedLockRestrictsEditing,
  }) async {
    if (_tabController.index == 0) {
      // The lock only covers the shared list: private items can still be
      // added, so there is nothing to choose.
      final isPrivate = manualLockRestrictsEditing
          ? true
          : await _pickManualItemVisibility(context);
      if (isPrivate == null) return;
      await _addManualListItem(isPrivate: isPrivate);
      return;
    }
    await _addConsolidatedListItem(
      context,
      consolidatedLockRestrictsEditing: consolidatedLockRestrictsEditing,
    );
  }

  /// Asks whether the new free-list item is shared or private (true); null
  /// when the sheet is dismissed.
  Future<bool?> _pickManualItemVisibility(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        Widget option(IconData icon, String label, bool isPrivate) => ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(label),
              trailing: const Icon(PhosphorIconsRegular.plus),
              onTap: () => Navigator.of(sheetContext).pop(isPrivate),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Text(
                    l10n.commonAdd,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                option(
                  PhosphorIconsRegular.users,
                  l10n.shoppingAddSharedItem,
                  false,
                ),
                option(
                  PhosphorIconsRegular.lock,
                  l10n.shoppingAddPrivateItem,
                  true,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addManualListItem({required bool isPrivate}) async {
    final topOrder = widget.items.isEmpty ? 0 : (widget.items.first.order - 1);
    final newItemId = await ref.read(shoppingRepositoryProvider).addItem(
          tripId: widget.tripId,
          label: '',
          order: topOrder,
          isPrivate: isPrivate,
        );
    if (!mounted) return;
    setState(() {
      // A shared item would be hidden by the « private » filter.
      if (!isPrivate) _manualOnlyPrivate = false;
      _pendingAutofocusItemId = newItemId;
    });
  }

  Future<void> _addConsolidatedListItem(
    BuildContext context, {
    required bool consolidatedLockRestrictsEditing,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (consolidatedLockRestrictsEditing) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.shoppingConsolidatedAddBlockedWhenLocked)),
      );
      return;
    }
    if (!mounted) return;
    final now = DateTime.now();
    final newId = 'consolidated_manual_${now.microsecondsSinceEpoch}';
    final topOrder = _consolidatedItems.isEmpty
        ? 0
        : _consolidatedItems
                .map((e) => e.item.order)
                .reduce((a, b) => a < b ? a : b) -
            1;
    final newEntry = _ConsolidatedEditableItem(
      categoryId: kUnassignedConsolidatedCategoryId,
      item: ShoppingItem(
        id: newId,
        label: '',
        checked: false,
        quantityValue: 1.0,
        quantityUnit: ShoppingUnit.unit,
        createdAt: now,
        order: topOrder,
      ),
    );
    setState(() {
      _suppressRemoteConsolidatedSync = true;
      _consolidationResult ??= ConsolidatedShoppingResult(
        items: const [],
        summary: ConsolidatedShoppingSummary.empty,
        categories: const [],
      );
      final list = List<_ConsolidatedEditableItem>.from(_consolidatedItems);
      final insertAt = list.indexWhere(
        (e) => e.categoryId.trim() == kUnassignedConsolidatedCategoryId,
      );
      if (insertAt == -1) {
        list.add(newEntry);
      } else {
        list.insert(insertAt, newEntry);
      }
      _consolidatedItems = list;
      _pendingAutofocusItemId = newId;
    });
  }

  Future<void> _consolidateWithAi(
    BuildContext context,
    _ConsolidationMode mode,
  ) async {
    if (_isConsolidating) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isConsolidating = true);
    try {
      final result = await ref
          .read(shoppingRepositoryProvider)
          .consolidateWithAi(
            tripId: widget.tripId,
            mode: mode == _ConsolidationMode.full ? 'full' : 'manual_only',
          );
      if (!mounted) return;
      setState(() {
        _suppressRemoteConsolidatedSync = true;
        _consolidationResult = result;
        _consolidatedItems = _buildConsolidatedEditableItems(result.items);
      });
      _tabController.animateTo(1);
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            aiErrorMessage(l10n, e, AiFeature.shoppingConsolidation),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isConsolidating = false);
    }
  }

  Future<void> _setManualListLocked(BuildContext context, bool locked) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shoppingRepositoryProvider).setShoppingListLockFlags(
            tripId: widget.tripId,
            manualListLocked: locked,
          );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  Future<void> _setConsolidatedListLocked(
    BuildContext context,
    bool locked,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shoppingRepositoryProvider).setShoppingListLockFlags(
            tripId: widget.tripId,
            consolidatedListLocked: locked,
          );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  Future<void> _showConsolidateOptionsDialog(
    BuildContext context,
    bool isApplicationOwner,
  ) async {
    final mode = await showDialog<_ConsolidationMode>(
      context: context,
      builder: (dialogContext) => _ConsolidationOptionsDialog(
        isApplicationOwner: isApplicationOwner,
      ),
    );
    if (mode == null || !context.mounted) return;
    await _consolidateWithAi(context, mode);
  }

  Future<void> _confirmAndDeleteChecked(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final checkedCount = widget.items.where((item) => item.checked).length;
    if (checkedCount == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.shoppingDeleteCheckedTitle),
          content: Text(
            l10n.shoppingDeleteCheckedContent(checkedCount),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        );
      },
    );

    if (confirm != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deletedCount = await ref
          .read(shoppingRepositoryProvider)
          .deleteCheckedItems(tripId: widget.tripId);
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.shoppingDeletedCount(deletedCount)),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final checkedCount = widget.items.where((item) => item.checked).length;
    final currentRole = resolveTripPermissionRole(
      trip: widget.trip,
      userId: currentUid,
    );
    final isAdminOrAbove = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: TripPermissionRole.admin,
    );
    // Items are held by a user id, or by a participant id for participants
    // without an account (assigned by an admin).
    final participants =
        ref.watch(tripParticipantsStreamProvider(widget.tripId)).asData?.value ??
            const <TripMember>[];
    final participantLabels =
        ref.watch(tripMemberResolvedLabelsProvider(widget.tripId));
    final currentParticipantId =
        ref.watch(myTripMemberStreamProvider(widget.tripId)).asData?.value?.id ??
            '';
    // Private items can go to the current traveler's "À emporter" list;
    // those already there are flagged on their row.
    final packingParticipantId =
        ref.watch(myPackingParticipantIdProvider(widget.tripId));
    final packedShoppingItemIds = <String>{
      for (final packingItem
          in ref.watch(myPackingItemsStreamProvider(widget.tripId)).asData?.value ??
              const [])
        if ((packingItem.sourceShoppingItemId ?? '').isNotEmpty)
          packingItem.sourceShoppingItemId!,
    };
    // Admins prepare who buys what: assign items or whole categories, and tick
    // or untick items held by any participant.
    final assignees = isAdminOrAbove
        ? shoppingAssigneesFor(
            participants: participants,
            memberUserIds: widget.trip.memberUserIds,
            labelsById: participantLabels,
            photoUrlsByUserId:
                ref.watch(tripMemberPhotoUrlsProvider(widget.tripId)),
          )
        : const <ShoppingAssignee>[];
    final checkableOnBehalfIds = isAdminOrAbove
        ? {
            for (final participant in participants) ...[
              participant.id,
              if ((participant.userId?.trim() ?? '').isNotEmpty)
                participant.userId!.trim(),
            ],
            ...widget.trip.memberUserIds,
          }
        : const <String>{};
    final locks = ref
            .watch(tripShoppingListLocksStreamProvider(widget.tripId))
            .asData
            ?.value ??
        TripShoppingListLocks.defaults;
    final manualLockRestrictsEditing =
        locks.manualListLocked && !isAdminOrAbove;
    final consolidatedLockRestrictsEditing =
        locks.consolidatedListLocked && !isAdminOrAbove;
    final canDeleteCheckedItems = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: widget.trip.shoppingPermissions.deleteCheckedItemsMinRole,
    );
    final circuitBreakerTripped =
        ref.watch(aiCircuitBreakerTrippedProvider).asData?.value ?? false;
    final canConsolidateWithAi = !circuitBreakerTripped &&
        !locks.consolidatedListLocked &&
        isTripRoleAllowed(
          currentRole: currentRole,
          minRole: TripPermissionRole.admin,
        );
    final showShoppingFab = isAdminOrAbove || !locks.manualListLocked;
    // On the free list, private items can be added even when it is locked.
    final showAddItemFab = _currentTabIndex == 0 || showShoppingFab;
    final currentUserOwnerAsync = ref.watch(
      usersDataByIdsKeyStreamProvider(stableUsersIdsKey([currentUid])),
    );
    final ownerData = currentUserOwnerAsync.asData?.value;
    final ownerFlagReady = ownerData != null;
    final isApplicationOwner =
        ownerData?[currentUid]?['isApplicationOwner'] == true;
    final searchQuery = _searchController.text;
    final consolidatedRemoteAsync =
        ref.watch(tripConsolidatedShoppingListStreamProvider(widget.tripId));
    _ensureRemoteConsolidatedSynced(consolidatedRemoteAsync);

    final searchFilteredItems = widget.items
        .where((item) => displayNameMatchesNameSearch(item.label, searchQuery))
        .toList(growable: false);
    final filteredItems = searchFilteredItems
        .where(
          (item) => shoppingItemMatchesShoppingListFilters(
            item,
            statusFilter: _manualListStatusFilter,
            onlyClaimedByMe: _manualOnlyClaimedByMe,
            currentUid: currentUid,
            currentParticipantId: currentParticipantId,
            onlyPrivate: _manualOnlyPrivate,
          ),
        )
        .toList(growable: false);
    final manualGroups = _groupManualItemsByCategory(filteredItems);
    final claimedByIds = <String>{
      ...widget.items
          .map((item) => item.claimedBy?.trim() ?? '')
          .where((id) => id.isNotEmpty),
      ..._consolidatedItems
          .map((entry) => entry.item.claimedBy?.trim() ?? '')
          .where((id) => id.isNotEmpty),
    }.toList(growable: false);

    final normalizedLabelCounts = <String, int>{};
    for (final item in widget.items) {
      final normalized = _normalizeItemLabel(item.label);
      if (normalized.isEmpty) continue;
      normalizedLabelCounts[normalized] =
          (normalizedLabelCounts[normalized] ?? 0) + 1;
    }
    final consolidatedLabelCounts = <String, int>{};
    for (final entry in _consolidatedItems) {
      final normalized = _normalizeItemLabel(entry.item.label);
      if (normalized.isEmpty) continue;
      consolidatedLabelCounts[normalized] =
          (consolidatedLabelCounts[normalized] ?? 0) + 1;
    }

    final usersDataStream =
        ref.read(usersRepositoryProvider).watchUsersDataByIds(claimedByIds);

    final languageCode = Localizations.localeOf(context).languageCode;

    final showDeleteCheckedAction = showShoppingFab && canDeleteCheckedItems;
    final showConsolidateAction = showShoppingFab && canConsolidateWithAi;
    Widget buildListActionsMenu({bool showClearConsolidated = false}) =>
        PopupMenuButton<String>(
          tooltip: l10n.commonMoreActions,
          icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
          onSelected: (value) {
            switch (value) {
              case 'help':
                _showFilterHelp(context);
              case 'consolidate':
                _showConsolidateOptionsDialog(context, isApplicationOwner);
              case 'delete_checked':
                _confirmAndDeleteChecked(context);
              case 'clear_consolidated':
                _confirmAndClearConsolidated(context);
            }
          },
          itemBuilder: (context) {
            final errorColor = Theme.of(context).colorScheme.error;
            return [
              PopupMenuItem<String>(
                value: 'help',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(PhosphorIconsRegular.question),
                  title: Text(l10n.shoppingFilterHelpTooltip),
                ),
              ),
              if (showConsolidateAction)
                PopupMenuItem<String>(
                  value: 'consolidate',
                  enabled: !_isConsolidating && ownerFlagReady,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(PhosphorIconsRegular.sparkle),
                    title: Text(l10n.shoppingActionConsolidateAi),
                  ),
                ),
              if (showClearConsolidated)
                PopupMenuItem<String>(
                  value: 'clear_consolidated',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(PhosphorIconsRegular.stackMinus),
                    title: Text(l10n.shoppingConsolidatedClear),
                  ),
                ),
              if (showDeleteCheckedAction)
                PopupMenuItem<String>(
                  value: 'delete_checked',
                  enabled: checkedCount > 0,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        Icon(PhosphorIconsRegular.trash, color: errorColor),
                    title: Text(
                      l10n.shoppingActionDeleteChecked,
                      style: TextStyle(color: errorColor),
                    ),
                  ),
                ),
            ];
          },
        );
    final Widget listActionsMenu = buildListActionsMenu();
    final Widget consolidatedActionsMenu = buildListActionsMenu(
      showClearConsolidated: isAdminOrAbove &&
          !locks.consolidatedListLocked &&
          _consolidatedItems.isNotEmpty,
    );

    return StreamBuilder<Map<String, Map<String, dynamic>>>(
      stream: usersDataStream,
      builder: (context, usersSnap) {
        final usersDataById = usersSnap.data ?? const <String, Map<String, dynamic>>{};
        Widget buildManualItemRow(ShoppingItem item) => ShoppingItemRow(
              key: ValueKey(item.id),
              tripId: widget.tripId,
              item: item,
              usersDataById: usersDataById,
              normalizedLabelCounts: normalizedLabelCounts,
              // The lock is about the shared list: private items stay
              // editable by their owner.
              structureLocked: !item.isPrivate && manualLockRestrictsEditing,
              currentParticipantId: currentParticipantId,
              checkableOnBehalfIds: checkableOnBehalfIds,
              claimLabelsById: participantLabels,
              addedToPackingList: packedShoppingItemIds.contains(item.id),
              customMenuItems: _manualItemMenuItems(
                l10n,
                item,
                canAssign: assignees.isNotEmpty,
                isMine: _isHeldBy(item, currentUid, currentParticipantId),
                canShare: !manualLockRestrictsEditing,
                canAddToPacking: packingParticipantId != null &&
                    !packedShoppingItemIds.contains(item.id),
              ),
              onCustomMenuAction: (actionId) {
                switch (actionId) {
                  case _changeManualCategoryActionId:
                    unawaited(_changeManualItemCategory(context, item));
                  case _assignItemActionId:
                    unawaited(_assignManualItem(context, item, assignees));
                  case _makePrivateActionId:
                    unawaited(_setItemPrivate(context, item, true));
                  case _makeSharedActionId:
                    unawaited(_setItemPrivate(context, item, false));
                  case _addToPackingActionId:
                    if (packingParticipantId != null) {
                      unawaited(
                        _addToPackingList(context, item, packingParticipantId),
                      );
                    }
                }
              },
              autoFocusLabel: item.id == _pendingAutofocusItemId,
              onAutoFocusHandled: () {
                if (!mounted) return;
                if (_pendingAutofocusItemId != item.id) return;
                setState(() => _pendingAutofocusItemId = null);
              },
            );
        return Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              l10n.shoppingTabList,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 2),
                          if (isAdminOrAbove)
                            IconButton(
                              iconSize: 18,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              tooltip: locks.manualListLocked
                                  ? l10n.shoppingTooltipUnlockManualList
                                  : l10n.shoppingTooltipLockManualList,
                              onPressed: () => _setManualListLocked(
                                context,
                                !locks.manualListLocked,
                              ),
                              icon: Icon(
                                locks.manualListLocked
                                    ? PhosphorIconsRegular.lock
                                    : PhosphorIconsRegular.lockOpen,
                              ),
                            )
                          else if (locks.manualListLocked)
                            Icon(
                              PhosphorIconsRegular.lock,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              l10n.shoppingTabConsolidated,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 2),
                          if (isAdminOrAbove)
                            IconButton(
                              iconSize: 18,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              tooltip: locks.consolidatedListLocked
                                  ? l10n.shoppingTooltipUnlockConsolidatedList
                                  : l10n.shoppingTooltipLockConsolidatedList,
                              onPressed: () => _setConsolidatedListLocked(
                                context,
                                !locks.consolidatedListLocked,
                              ),
                              icon: Icon(
                                locks.consolidatedListLocked
                                    ? PhosphorIconsRegular.lock
                                    : PhosphorIconsRegular.lockOpen,
                              ),
                            )
                          else if (locks.consolidatedListLocked)
                            Icon(
                              PhosphorIconsRegular.lock,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 0 — manual list
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: NameListSearchTextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                            child: ShoppingListFilterBar(
                              selectedStatus: _manualListStatusFilter,
                              onlyClaimedByMe: _manualOnlyClaimedByMe,
                              onStatusChanged: (f) =>
                                  setState(() => _manualListStatusFilter = f),
                              onOnlyClaimedByMeChanged: (v) =>
                                  setState(() => _manualOnlyClaimedByMe = v),
                              onlyPrivate: _manualOnlyPrivate,
                              onOnlyPrivateChanged: (v) =>
                                  setState(() => _manualOnlyPrivate = v),
                            ),
                          ),
                          PzProgressBar(
                            done: checkedCount,
                            total: widget.items.length,
                            trailing: [listActionsMenu],
                          ),
                          Expanded(
                            child: widget.items.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          PhosphorIconsRegular.shoppingCartSimple,
                                          size: 48,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          l10n.shoppingEmptyTitle,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          l10n.shoppingEmptySubtitle,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  )
                                : filteredItems.isEmpty
                                    ? Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Text(
                                            nameListSearchEmptyMessage(context),
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 4, 12, 88),
                                        itemCount: manualGroups.length,
                                        itemBuilder: (context, index) {
                                          final group = manualGroups[index];
                                          return _ShoppingCategoryCard(
                                            key: ValueKey(
                                              'manual_category_${group.key}',
                                            ),
                                            label: group.key.isEmpty
                                                ? l10n.shoppingCategoryNone
                                                : shoppingCategoryLabel(
                                                    l10n,
                                                    group.key,
                                                  ),
                                            checkedCount: group.value
                                                .where((item) => item.checked)
                                                .length,
                                            total: group.value.length,
                                            children: [
                                              for (final item in group.value)
                                                buildManualItemRow(item),
                                            ],
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
                      // Tab 1 — consolidated list
                      _buildConsolidatedTab(
                        context,
                        l10n,
                        languageCode,
                        usersDataById,
                        consolidatedLabelCounts,
                        activeStatusFilter: _consolidatedListStatusFilter,
                        onlyClaimedByMe: _consolidatedOnlyClaimedByMe,
                        currentUid: currentUid,
                        currentParticipantId: currentParticipantId,
                        checkableOnBehalfIds: checkableOnBehalfIds,
                        claimLabelsById: participantLabels,
                        onStatusFilterChanged: (f) =>
                            setState(() => _consolidatedListStatusFilter = f),
                        onOnlyClaimedByMeChanged: (v) =>
                            setState(() => _consolidatedOnlyClaimedByMe = v),
                        pendingAutofocusItemId: _pendingAutofocusItemId,
                        onAutofocusItemHandled: (itemId) {
                          if (!mounted) return;
                          if (_pendingAutofocusItemId != itemId) return;
                          setState(() => _pendingAutofocusItemId = null);
                        },
                        consolidatedStructureLocked:
                            consolidatedLockRestrictsEditing,
                        showConsolidatedSaveButton: isAdminOrAbove &&
                            _consolidatedItems.isNotEmpty,
                        isSavingConsolidated: _isSavingConsolidated,
                        assignees: assignees,
                        consolidatedRemoteAsync: consolidatedRemoteAsync,
                        suppressRemoteConsolidatedSync:
                            _suppressRemoteConsolidatedSync,
                        listActionsMenu: consolidatedActionsMenu,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isConsolidating)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.45),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            if (showAddItemFab)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.extended(
                  heroTag: 'shopping_add_item_fab',
                  tooltip: l10n.shoppingActionAddItem,
                  onPressed: () => unawaited(
                    _addFromFabAddItem(
                      context,
                      manualLockRestrictsEditing: manualLockRestrictsEditing,
                      consolidatedLockRestrictsEditing:
                          consolidatedLockRestrictsEditing,
                    ),
                  ),
                  icon: const Icon(PhosphorIconsRegular.plus),
                  label: Text(l10n.shoppingActionAddItem),
                ),
              ),
          ],
        );
      },
    );
  }

  String _remoteConsolidatedFingerprint(ConsolidatedListFirestorePayload payload) {
    if (payload.rows.isEmpty) return 'empty';
    return payload.rows
        .map(
          (r) =>
              '${r.item.id}|${r.item.label}|${r.item.order}|${r.item.checked}|'
              '${r.item.quantityValue}|${r.item.quantityUnit.firestoreValue}|'
              '${r.categoryId}|${r.item.claimedBy ?? ''}',
        )
        .join('~');
  }

  void _ensureRemoteConsolidatedSynced(
    AsyncValue<ConsolidatedListFirestorePayload> asyncVal,
  ) {
    if (_suppressRemoteConsolidatedSync) return;
    final payload = asyncVal.asData?.value;
    if (payload == null) return;
    final key = _remoteConsolidatedFingerprint(payload);
    if (key == _appliedRemoteConsolidatedFingerprint) return;
    _appliedRemoteConsolidatedFingerprint = key;
    final captured = payload;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _suppressRemoteConsolidatedSync) return;
      if (_remoteConsolidatedFingerprint(captured) != key) return;
      _applyRemoteConsolidatedPayload(captured);
    });
  }

  void _applyRemoteConsolidatedPayload(ConsolidatedListFirestorePayload payload) {
    if (!mounted) return;
    setState(() {
      if (payload.rows.isEmpty) {
        _consolidationResult = null;
        _consolidatedItems = const [];
        return;
      }
      _consolidationResult = ConsolidatedShoppingResult(
        items: const [],
        summary: payload.summary,
        categories: payload.categories,
      );
      _consolidatedItems = [
        for (final row in payload.rows)
          _ConsolidatedEditableItem(
            categoryId:
                row.categoryId.trim().isEmpty ? 'divers' : row.categoryId.trim(),
            item: row.item,
          ),
      ];
    });
  }

  Future<void> _persistConsolidatedToggleChecked(
    BuildContext context,
    ShoppingItem item,
    bool checked,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shoppingRepositoryProvider).setConsolidatedItemChecked(
            tripId: widget.tripId,
            itemId: item.id,
            checked: checked,
          );
      if (!mounted) return;
      _updateConsolidatedItem(
        item.id,
        (prev) => ShoppingItem(
          id: prev.id,
          label: prev.label,
          checked: checked,
          quantityValue: prev.quantityValue,
          quantityUnit: prev.quantityUnit,
          createdAt: prev.createdAt,
          order: prev.order,
          createdBy: prev.createdBy,
          claimedBy: prev.claimedBy,
        ),
      );
    } on ConsolidatedShoppingRowNotPersistedException {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.shoppingConsolidatedRowNotPersisted)),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  Future<void> _persistConsolidatedSetClaimedBy(
    BuildContext context,
    ShoppingItem item,
    String? claimedBy,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shoppingRepositoryProvider).setConsolidatedItemClaimedBy(
            tripId: widget.tripId,
            itemId: item.id,
            claimedBy: claimedBy,
          );
      if (!mounted) return;
      _updateConsolidatedItem(
        item.id,
        (prev) => ShoppingItem(
          id: prev.id,
          label: prev.label,
          checked: prev.checked,
          quantityValue: prev.quantityValue,
          quantityUnit: prev.quantityUnit,
          createdAt: prev.createdAt,
          order: prev.order,
          createdBy: prev.createdBy,
          claimedBy: claimedBy,
        ),
      );
    } on ConsolidatedShoppingRowNotPersistedException {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.shoppingConsolidatedRowNotPersisted)),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  static const String _changeManualCategoryActionId =
      'change_shopping_item_category';
  static const String _assignItemActionId = 'assign_shopping_item';
  static const String _makePrivateActionId = 'make_shopping_item_private';
  static const String _makeSharedActionId = 'make_shopping_item_shared';
  static const String _addToPackingActionId = 'add_shopping_item_to_packing';

  /// Whether [item] is held by the current user (account or participant id).
  static bool _isHeldBy(
    ShoppingItem item,
    String currentUid,
    String currentParticipantId,
  ) {
    final claimedBy = item.claimedBy?.trim() ?? '';
    if (claimedBy.isEmpty) return false;
    return claimedBy == currentUid ||
        (currentParticipantId.isNotEmpty && claimedBy == currentParticipantId);
  }

  /// Row actions of the free list, besides delete. Any item can be sorted
  /// into a category. A shared item can be assigned (admins) and, while still
  /// to buy, made private when free or held by the current user; a private
  /// item can go to the "À emporter" list or be shared again.
  List<IngredientLineCustomMenuItem> _manualItemMenuItems(
    AppLocalizations l10n,
    ShoppingItem item, {
    required bool canAssign,
    required bool isMine,
    required bool canShare,
    required bool canAddToPacking,
  }) {
    final isFree = (item.claimedBy?.trim() ?? '').isEmpty;
    return <IngredientLineCustomMenuItem>[
      IngredientLineCustomMenuItem(
        actionId: _changeManualCategoryActionId,
        label: l10n.shoppingChangeCategoryMenu,
        icon: PhosphorIconsRegular.folderSimpleUser,
      ),
      if (item.isPrivate) ...[
        if (canAddToPacking && item.label.trim().isNotEmpty)
          IngredientLineCustomMenuItem(
            actionId: _addToPackingActionId,
            label: l10n.shoppingAddToPackingMenu,
            icon: PhosphorIconsRegular.suitcaseRolling,
          ),
        if (canShare)
          IngredientLineCustomMenuItem(
            actionId: _makeSharedActionId,
            label: l10n.shoppingMakeSharedMenu,
            icon: PhosphorIconsRegular.lockOpen,
          ),
      ] else ...[
        if (canAssign)
          IngredientLineCustomMenuItem(
            actionId: _assignItemActionId,
            label: l10n.shoppingAssignMenu,
            icon: PhosphorIconsRegular.userPlus,
          ),
        if (!item.checked && (isFree || isMine))
          IngredientLineCustomMenuItem(
            actionId: _makePrivateActionId,
            label: l10n.shoppingMakePrivateMenu,
            icon: PhosphorIconsRegular.lock,
          ),
      ],
    ];
  }

  /// Sorts a free-list [item] into a grocery category, or takes it out of
  /// its category.
  Future<void> _changeManualItemCategory(
    BuildContext context,
    ShoppingItem item,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final currentId = item.categoryId ?? '';
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _CategoryPickerDialog(
        options: [
          (id: '', label: l10n.shoppingCategoryNone),
          for (final id in kShoppingCategoryIds)
            (id: id, label: shoppingCategoryLabel(l10n, id)),
        ],
        initialId: currentId,
      ),
    );
    if (chosen == null || chosen == currentId || !mounted) return;
    try {
      await ref.read(shoppingRepositoryProvider).setItemCategory(
            tripId: widget.tripId,
            itemId: item.id,
            categoryId: chosen.isEmpty ? null : chosen,
            isPrivate: item.isPrivate,
          );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  Future<void> _setItemPrivate(
    BuildContext context,
    ShoppingItem item,
    bool isPrivate,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shoppingRepositoryProvider).setItemPrivate(
            tripId: widget.tripId,
            item: item,
            isPrivate: isPrivate,
          );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  /// Copies a private [item] (label and quantity) into the current
  /// traveler's "À emporter" list, showing that module if it was hidden.
  Future<void> _addToPackingList(
    BuildContext context,
    ShoppingItem item,
    String participantId,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(packingRepositoryProvider).addFromShoppingItem(
            tripId: widget.tripId,
            participantId: participantId,
            shoppingItemId: item.id,
            label: _packingLabelFor(l10n, item),
          );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  /// Admin action: puts [item] of the manual list in the hands of a
  /// participant (or nobody).
  Future<void> _assignManualItem(
    BuildContext context,
    ShoppingItem item,
    List<ShoppingAssignee> assignees,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final chosen = await showShoppingAssigneeDialog(
      context,
      assignees: assignees,
      initialClaimId: item.claimedBy?.trim() ?? '',
      // A bought item keeps a holder: nobody could untick it otherwise.
      allowNobody: !item.checked,
    );
    if (chosen == null || !mounted) return;
    if (chosen == (item.claimedBy?.trim() ?? '')) return;
    try {
      await ref.read(shoppingRepositoryProvider).setClaimedBy(
            tripId: widget.tripId,
            itemId: item.id,
            claimedBy: chosen.isEmpty ? null : chosen,
          );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  /// Admin action: puts a consolidated [item] in the hands of a participant
  /// (or nobody).
  Future<void> _assignConsolidatedItem(
    BuildContext context,
    ShoppingItem item,
    List<ShoppingAssignee> assignees,
  ) async {
    final chosen = await showShoppingAssigneeDialog(
      context,
      assignees: assignees,
      initialClaimId: item.claimedBy?.trim() ?? '',
      // A bought item keeps a holder: nobody could untick it otherwise.
      allowNobody: !item.checked,
    );
    if (chosen == null || !context.mounted) return;
    if (chosen == (item.claimedBy?.trim() ?? '')) return;
    await _persistConsolidatedSetClaimedBy(
      context,
      item,
      chosen.isEmpty ? null : chosen,
    );
  }

  /// Admin action on a consolidated category, among its items still to buy
  /// ([openItems]): a participant takes the free ones; "nobody" frees them
  /// all.
  Future<void> _assignConsolidatedCategory(
    BuildContext context,
    List<ShoppingItem> openItems,
    List<ShoppingAssignee> assignees,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final chosen = await showShoppingAssigneeDialog(
      context,
      assignees: assignees,
      allowNobody: true,
    );
    if (chosen == null || !mounted) return;
    final nextHolder = chosen.isEmpty ? null : chosen;
    final itemIds = {
      for (final item in openItems)
        if ((item.claimedBy?.trim() ?? '').isEmpty != chosen.isEmpty) item.id,
    };
    if (itemIds.isEmpty) return;
    try {
      await ref.read(shoppingRepositoryProvider).setConsolidatedItemsClaimedBy(
            tripId: widget.tripId,
            itemIds: itemIds.toList(growable: false),
            claimedBy: nextHolder,
          );
      if (!mounted) return;
      setState(() {
        _consolidatedItems = _consolidatedItems
            .map(
              (entry) => itemIds.contains(entry.item.id)
                  ? _ConsolidatedEditableItem(
                      categoryId: entry.categoryId,
                      item: _shoppingItemClaimedBy(entry.item, nextHolder),
                    )
                  : entry,
            )
            .toList(growable: false);
      });
    } on ConsolidatedShoppingRowNotPersistedException {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.shoppingConsolidatedRowNotPersisted)),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  Future<void> _saveConsolidatedList(BuildContext context) async {
    if (_isSavingConsolidated || _consolidatedItems.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSavingConsolidated = true);
    try {
      final rows = <ConsolidatedFirestoreRow>[
        for (final entry in _consolidatedItems)
          ConsolidatedFirestoreRow(
            categoryId: entry.categoryId,
            item: entry.item,
          ),
      ];
      final categories = _categoriesPersistedWithUnassigned(
        _consolidationResult?.categories ?? const [],
        rows,
      );
      await ref.read(shoppingRepositoryProvider).replaceConsolidatedShoppingList(
            tripId: widget.tripId,
            categories: categories,
            summary:
                _consolidationResult?.summary ?? ConsolidatedShoppingSummary.empty,
            rows: rows,
          );
      if (!mounted) return;
      setState(() => _suppressRemoteConsolidatedSync = false);
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _isSavingConsolidated = false);
    }
  }

  Future<void> _confirmAndClearConsolidated(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.shoppingConsolidatedClearConfirmTitle),
          content: Text(l10n.shoppingConsolidatedClearConfirmContent),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        );
      },
    );
    if (confirm != true || !context.mounted) return;
    try {
      await ref.read(shoppingRepositoryProvider).deleteConsolidatedShoppingList(
            widget.tripId,
          );
      if (!mounted) return;
      setState(() {
        _suppressRemoteConsolidatedSync = false;
        _consolidationResult = null;
        _consolidatedItems = const [];
      });
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  Widget _buildConsolidatedTab(
    BuildContext context,
    AppLocalizations l10n,
    String languageCode,
    Map<String, Map<String, dynamic>> usersDataById,
    Map<String, int> normalizedLabelCounts, {
    required ShoppingListStatusFilter activeStatusFilter,
    required bool onlyClaimedByMe,
    required String currentUid,
    required String currentParticipantId,
    required Set<String> checkableOnBehalfIds,
    required Map<String, String> claimLabelsById,
    required ValueChanged<ShoppingListStatusFilter> onStatusFilterChanged,
    required ValueChanged<bool> onOnlyClaimedByMeChanged,
    required String? pendingAutofocusItemId,
    required void Function(String itemId) onAutofocusItemHandled,
    required bool consolidatedStructureLocked,
    required bool showConsolidatedSaveButton,
    required bool isSavingConsolidated,
    required List<ShoppingAssignee> assignees,
    required AsyncValue<ConsolidatedListFirestorePayload> consolidatedRemoteAsync,
    required bool suppressRemoteConsolidatedSync,
    required Widget listActionsMenu,
  }) {
    if (!suppressRemoteConsolidatedSync) {
      if (consolidatedRemoteAsync.isLoading && _consolidatedItems.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (consolidatedRemoteAsync.hasError && _consolidatedItems.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.commonErrorWithDetails(
                consolidatedRemoteAsync.error.toString(),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
    }

    final result = _consolidationResult;
    final categories = result?.categories ?? const [];
    if (result == null || _consolidatedItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.shoppingConsolidatedEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    final groups = _groupByCategory(_consolidatedItems, categories);
    final allItemsByCategory = {
      for (final entry in groups) entry.key: entry.value,
    };
    final visibleGroups = <MapEntry<String, List<ShoppingItem>>>[];
    for (final entry in groups) {
      final filtered = entry.value
          .where(
            (item) => shoppingItemMatchesShoppingListFilters(
              item,
              statusFilter: activeStatusFilter,
              onlyClaimedByMe: onlyClaimedByMe,
              currentUid: currentUid,
              currentParticipantId: currentParticipantId,
            ),
          )
          .toList(growable: false);
      if (filtered.isEmpty) continue;
      visibleGroups.add(MapEntry(entry.key, filtered));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: ShoppingListFilterBar(
            selectedStatus: activeStatusFilter,
            onlyClaimedByMe: onlyClaimedByMe,
            onStatusChanged: onStatusFilterChanged,
            onOnlyClaimedByMeChanged: onOnlyClaimedByMeChanged,
          ),
        ),
        PzProgressBar(
          done: _consolidatedItems.where((e) => e.item.checked).length,
          total: _consolidatedItems.length,
          trailing: [
              if (showConsolidatedSaveButton)
                IconButton(
                  tooltip: l10n.shoppingConsolidatedSave,
                  icon: isSavingConsolidated
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsRegular.floppyDisk),
                  onPressed: isSavingConsolidated
                      ? null
                      : () => _saveConsolidatedList(context),
                ),
            listActionsMenu,
          ],
        ),
        Expanded(
          child: visibleGroups.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.shoppingConsolidatedFilterEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                  itemCount: visibleGroups.length,
                  itemBuilder: (context, index) {
                    final entry = visibleGroups[index];
                    // Whole category, whatever the filters: items still to
                    // buy (bought ones keep their holder).
                    final openItems = (allItemsByCategory[entry.key] ??
                            const <ShoppingItem>[])
                        .where((item) => !item.checked)
                        .toList(growable: false);
                    return _ConsolidatedCategorySection(
                      l10n: l10n,
                      label: _categoryLabel(
                        l10n,
                        entry.key,
                        languageCode,
                        categories,
                      ),
                      items: entry.value,
                      tripId: widget.tripId,
                      listContext: context,
                      usersDataById: usersDataById,
                      normalizedLabelCounts: normalizedLabelCounts,
                      currentParticipantId: currentParticipantId,
                      checkableOnBehalfIds: checkableOnBehalfIds,
                      claimLabelsById: claimLabelsById,
                      pendingAutofocusItemId: pendingAutofocusItemId,
                      onAutofocusItemHandled: onAutofocusItemHandled,
                      structureLocked: consolidatedStructureLocked,
                      onConsolidatedToggleChecked: _persistConsolidatedToggleChecked,
                      onConsolidatedSetClaimedBy: _persistConsolidatedSetClaimedBy,
                      onItemChanged: (itemId, updatedItem) {
                        _updateConsolidatedItem(itemId, (_) => updatedItem);
                      },
                      onItemDeleted: _deleteConsolidatedItem,
                      onRequestChangeCategory: (dialogContext, rowItem) =>
                          _presentChangeConsolidatedCategoryDialog(
                            dialogContext,
                            rowItem,
                            entry.key,
                          ),
                      onRequestAssign: assignees.isEmpty
                          ? null
                          : (dialogContext, rowItem) =>
                              _assignConsolidatedItem(
                                dialogContext,
                                rowItem,
                                assignees,
                              ),
                      onAssignCategory: assignees.isEmpty || openItems.isEmpty
                          ? null
                          : () => _assignConsolidatedCategory(
                                context,
                                openItems,
                                assignees,
                              ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showFilterHelp(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.shoppingFiltersTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.shoppingFiltersHelpBody,
              ),
              const SizedBox(height: 12),
              _FilterLegendRow(
                icon: PhosphorIconsRegular.squaresFour,
                label: l10n.shoppingFilterAll,
              ),
              const SizedBox(height: 8),
              _FilterLegendRow(
                icon: PhosphorIconsRegular.circle,
                label: l10n.shoppingFilterTodo,
              ),
              const SizedBox(height: 8),
              _FilterLegendRow(
                icon: PhosphorIconsRegular.checkCircle,
                label: l10n.shoppingFilterDone,
              ),
              const SizedBox(height: 8),
              _FilterLegendRow(
                icon: PhosphorIconsRegular.userCircle,
                label: l10n.shoppingFilterClaimedByMe,
              ),
              const SizedBox(height: 8),
              _FilterLegendRow(
                icon: PhosphorIconsRegular.lock,
                label: l10n.shoppingFilterPrivateTooltip,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: Navigator.of(dialogContext).pop,
              child: Text(l10n.commonClose),
            ),
          ],
        );
      },
    );
  }

  List<_ConsolidatedEditableItem> _buildConsolidatedEditableItems(
    List<ConsolidatedShoppingItem> sourceItems,
  ) {
    final now = DateTime.now();
    return [
      for (int index = 0; index < sourceItems.length; index++)
        _ConsolidatedEditableItem(
          categoryId: sourceItems[index].categoryId,
          item: ShoppingItem(
            id: 'consolidated_$index',
            label: sourceItems[index].label,
            checked: false,
            quantityValue:
                sourceItems[index].quantityValue > 0 ? sourceItems[index].quantityValue : 1.0,
            quantityUnit: ShoppingUnit.fromHumanLabel(sourceItems[index].quantityUnit),
            createdAt: now,
            order: index,
          ),
        ),
    ];
  }

  void _updateConsolidatedItem(
    String itemId,
    ShoppingItem Function(ShoppingItem item) update,
  ) {
    setState(() {
      _consolidatedItems = _consolidatedItems
          .map(
            (entry) => entry.item.id == itemId
                ? _ConsolidatedEditableItem(
                    categoryId: entry.categoryId,
                    item: update(entry.item),
                  )
                : entry,
          )
          .toList(growable: false);
    });
  }

  void _deleteConsolidatedItem(String itemId) {
    setState(() {
      _consolidatedItems = _consolidatedItems
          .where((entry) => entry.item.id != itemId)
          .toList(growable: false);
    });
  }

  void _reassignConsolidatedItemCategory(String itemId, String newCategoryId) {
    final normalized =
        newCategoryId.trim().isEmpty ? 'divers' : newCategoryId.trim();
    setState(() {
      _consolidatedItems = _consolidatedItems
          .map(
            (entry) => entry.item.id == itemId
                ? _ConsolidatedEditableItem(
                    categoryId: normalized,
                    item: entry.item,
                  )
                : entry,
          )
          .toList(growable: false);
    });
  }

  Future<void> _presentChangeConsolidatedCategoryDialog(
    BuildContext context,
    ShoppingItem item,
    String currentCategoryId,
  ) async {
    final result = _consolidationResult;
    if (result == null) return;
    final l10n = AppLocalizations.of(context)!;
    final languageCode = Localizations.localeOf(context).languageCode;
    final categoryIds =
        _orderedCategoryIdsForPicker(result.categories, _consolidatedItems);
    if (categoryIds.isEmpty) return;
    final normalizedCurrent =
        currentCategoryId.trim().isEmpty ? 'divers' : currentCategoryId.trim();
    final initialId = categoryIds.contains(normalizedCurrent)
        ? normalizedCurrent
        : categoryIds.first;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _CategoryPickerDialog(
        options: [
          for (final id in categoryIds)
            (
              id: id,
              label: _categoryLabel(l10n, id, languageCode, result.categories),
            ),
        ],
        initialId: initialId,
      ),
    );
    if (!mounted || chosen == null) return;
    if (chosen == normalizedCurrent) return;
    _reassignConsolidatedItemCategory(item.id, chosen);
  }
}

ShoppingItem _shoppingItemClaimedBy(ShoppingItem item, String? claimedBy) =>
    ShoppingItem(
      id: item.id,
      label: item.label,
      checked: item.checked,
      quantityValue: item.quantityValue,
      quantityUnit: item.quantityUnit,
      createdAt: item.createdAt,
      order: item.order,
      createdBy: item.createdBy,
      claimedBy: claimedBy,
    );

String _normalizeItemLabel(String raw) {
  return raw.trim().toLowerCase();
}

/// Text of the "À emporter" item made from a shopping [item]: its label and
/// its quantity.
String _packingLabelFor(AppLocalizations l10n, ShoppingItem item) {
  final label = item.label.trim();
  if (item.quantityUnit == ShoppingUnit.unit) {
    return l10n.shoppingPackingLabelCount(label, item.quantityValue);
  }
  return l10n.shoppingPackingLabelMeasure(
    label,
    item.quantityValue,
    item.quantityUnit.label,
  );
}

enum _ConsolidationMode { full, manualOnly }

List<String> _orderedCategoryIdsForPicker(
  List<ConsolidatedShoppingCategory> meta,
  List<_ConsolidatedEditableItem> items,
) {
  final ordered = <String>[];
  for (final c in meta) {
    if (c.id.isNotEmpty) ordered.add(c.id);
  }
  final usedIds = <String>{
    for (final e in items)
      e.categoryId.trim().isEmpty ? 'divers' : e.categoryId.trim(),
  };
  for (final id in usedIds) {
    if (!ordered.contains(id)) ordered.add(id);
  }
  return ordered;
}

String _categoryLabel(
  AppLocalizations l10n,
  String categoryId,
  String languageCode,
  List<ConsolidatedShoppingCategory> categories,
) {
  final key = categoryId.trim().isEmpty ? 'divers' : categoryId.trim();
  if (key == kUnassignedConsolidatedCategoryId) {
    final match = categories.where((c) => c.id == key).firstOrNull;
    if (match != null) return match.label(languageCode);
    return l10n.shoppingCategoryUnassigned;
  }
  final match = categories.where((c) => c.id == key).firstOrNull;
  if (match != null) return match.label(languageCode);
  if (key == 'divers') return l10n.shoppingCategoryDivers;
  return key;
}

List<ConsolidatedShoppingCategory> _categoriesPersistedWithUnassigned(
  List<ConsolidatedShoppingCategory> base,
  List<ConsolidatedFirestoreRow> rows,
) {
  final needsUnassigned = rows.any((r) {
    final id = r.categoryId.trim().isEmpty ? 'divers' : r.categoryId.trim();
    return id == kUnassignedConsolidatedCategoryId;
  });
  if (!needsUnassigned) return List<ConsolidatedShoppingCategory>.from(base);
  if (base.any((c) => c.id == kUnassignedConsolidatedCategoryId)) {
    return List<ConsolidatedShoppingCategory>.from(base);
  }
  return [...base, kUnassignedConsolidatedCategoryMeta];
}

/// The free list by grocery category: items without one first (key ''),
/// then the categories in catalog order. Items keep their list order.
List<MapEntry<String, List<ShoppingItem>>> _groupManualItemsByCategory(
  List<ShoppingItem> items,
) {
  final byCategory = <String, List<ShoppingItem>>{};
  for (final item in items) {
    (byCategory[item.categoryId ?? ''] ??= []).add(item);
  }
  return [
    for (final id in ['', ...kShoppingCategoryIds])
      if (byCategory[id] case final categoryItems?)
        MapEntry(id, categoryItems),
  ];
}

List<MapEntry<String, List<ShoppingItem>>> _groupByCategory(
  List<_ConsolidatedEditableItem> items,
  List<ConsolidatedShoppingCategory> categories,
) {
  final map = <String, List<ShoppingItem>>{};
  for (final item in items) {
    final cat = item.categoryId.isEmpty ? 'divers' : item.categoryId;
    (map[cat] ??= []).add(item.item);
  }
  final ordered = <String>[];
  for (final cat in categories) {
    if (map.containsKey(cat.id)) ordered.add(cat.id);
  }
  for (final id in map.keys) {
    if (!ordered.contains(id)) ordered.add(id);
  }
  if (map.containsKey(kUnassignedConsolidatedCategoryId)) {
    ordered.remove(kUnassignedConsolidatedCategoryId);
    ordered.insert(0, kUnassignedConsolidatedCategoryId);
  }
  for (final list in map.values) {
    list.sort(
      (a, b) => _normalizeItemLabel(a.label).compareTo(_normalizeItemLabel(b.label)),
    );
  }
  return [for (final id in ordered) MapEntry(id, map[id]!)];
}

class _ConsolidatedCategorySection extends StatelessWidget {
  const _ConsolidatedCategorySection({
    required this.l10n,
    required this.label,
    required this.items,
    required this.tripId,
    required this.listContext,
    required this.usersDataById,
    required this.normalizedLabelCounts,
    required this.currentParticipantId,
    required this.checkableOnBehalfIds,
    required this.claimLabelsById,
    required this.pendingAutofocusItemId,
    required this.onAutofocusItemHandled,
    required this.structureLocked,
    required this.onConsolidatedToggleChecked,
    required this.onConsolidatedSetClaimedBy,
    required this.onItemChanged,
    required this.onItemDeleted,
    required this.onRequestChangeCategory,
    this.onRequestAssign,
    this.onAssignCategory,
  });

  static const String _changeCategoryActionId = 'change_consolidated_category';
  static const String _assignItemActionId = 'assign_consolidated_item';

  final AppLocalizations l10n;
  final String label;
  final List<ShoppingItem> items;
  final String tripId;
  final BuildContext listContext;
  final Map<String, Map<String, dynamic>> usersDataById;
  final Map<String, int> normalizedLabelCounts;
  final String currentParticipantId;
  final Set<String> checkableOnBehalfIds;
  final Map<String, String> claimLabelsById;
  final String? pendingAutofocusItemId;
  final void Function(String itemId) onAutofocusItemHandled;
  final bool structureLocked;
  final Future<void> Function(
    BuildContext context,
    ShoppingItem item,
    bool checked,
  ) onConsolidatedToggleChecked;
  final Future<void> Function(
    BuildContext context,
    ShoppingItem item,
    String? claimedBy,
  ) onConsolidatedSetClaimedBy;
  final void Function(String itemId, ShoppingItem updatedItem) onItemChanged;
  final void Function(String itemId) onItemDeleted;
  final Future<void> Function(BuildContext context, ShoppingItem item)
      onRequestChangeCategory;

  /// Assigns one item to a participant; null hides the action (non-admins).
  final Future<void> Function(BuildContext context, ShoppingItem item)?
      onRequestAssign;

  /// Assigns (or frees) the items of the category; null hides the action
  /// (non-admins, or nothing left to buy).
  final Future<void> Function()? onAssignCategory;

  @override
  Widget build(BuildContext context) {
    return _ShoppingCategoryCard(
      label: label,
      checkedCount: items.where((item) => item.checked).length,
      total: items.length,
      trailing: onAssignCategory == null
          ? null
          : PopupMenuButton<String>(
              tooltip: l10n.commonMoreActions,
              icon: Icon(
                PhosphorIconsRegular.dotsThreeVertical,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onSelected: (_) => unawaited(onAssignCategory!()),
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'assign_category',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(PhosphorIconsRegular.userPlus),
                    title: Text(l10n.shoppingAssignCategoryMenu),
                  ),
                ),
              ],
            ),
      children: [
        for (int i = 0; i < items.length; i++)
          ShoppingItemRow(
            key: ValueKey(items[i].id),
            tripId: tripId,
            item: items[i],
            usersDataById: usersDataById,
            normalizedLabelCounts: normalizedLabelCounts,
            structureLocked: structureLocked,
            currentParticipantId: currentParticipantId,
            checkableOnBehalfIds: checkableOnBehalfIds,
            claimLabelsById: claimLabelsById,
            autoFocusLabel: items[i].id == pendingAutofocusItemId,
            onAutoFocusHandled: () => onAutofocusItemHandled(items[i].id),
            customMenuItems: structureLocked
                ? null
                : [
                    IngredientLineCustomMenuItem(
                      actionId: _changeCategoryActionId,
                      label: l10n.shoppingChangeCategoryMenu,
                      icon: PhosphorIconsRegular.folderSimpleUser,
                    ),
                    if (onRequestAssign != null)
                      IngredientLineCustomMenuItem(
                        actionId: _assignItemActionId,
                        label: l10n.shoppingAssignMenu,
                        icon: PhosphorIconsRegular.userPlus,
                      ),
                  ],
            onCustomMenuAction: structureLocked
                ? null
                : (actionId) {
                    if (actionId == _changeCategoryActionId) {
                      unawaited(
                        onRequestChangeCategory(context, items[i]),
                      );
                    } else if (actionId == _assignItemActionId) {
                      unawaited(onRequestAssign!(listContext, items[i]));
                    }
                  },
            onToggleCheckedOverride: (checked) async {
              await onConsolidatedToggleChecked(listContext, items[i], checked);
            },
            onSetClaimedByOverride: (claimedBy) async {
              await onConsolidatedSetClaimedBy(listContext, items[i], claimedBy);
            },
            onSaveOverride: (value) async {
              onItemChanged(
                items[i].id,
                ShoppingItem(
                  id: items[i].id,
                  label: value.label,
                  checked: items[i].checked,
                  quantityValue: value.quantityValue,
                  quantityUnit: value.quantityUnit,
                  createdAt: items[i].createdAt,
                  order: items[i].order,
                  createdBy: items[i].createdBy,
                  claimedBy: items[i].claimedBy,
                ),
              );
            },
            onDeleteOverride: () async {
              onItemDeleted(items[i].id);
            },
          ),
      ],
    );
  }
}

/// A category of a shopping list: a card that folds its item rows under the
/// category name and how many of them are bought.
class _ShoppingCategoryCard extends StatelessWidget {
  const _ShoppingCategoryCard({
    super.key,
    required this.label,
    required this.checkedCount,
    required this.total,
    required this.children,
    this.trailing,
  });

  final String label;
  final int checkedCount;
  final int total;
  final List<Widget> children;

  /// Shown after the progress (e.g. the category actions).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text(
                '$checkedCount/$total',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          tilePadding: const EdgeInsets.only(left: 14, right: 8),
          childrenPadding: const EdgeInsets.only(left: 6, right: 6, bottom: 4),
          children: [
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1) const Divider(indent: 38),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConsolidatedEditableItem {
  const _ConsolidatedEditableItem({
    required this.categoryId,
    required this.item,
  });

  final String categoryId;
  final ShoppingItem item;
}

class _FilterLegendRow extends StatelessWidget {
  const _FilterLegendRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
      ],
    );
  }
}

class _ConsolidationOptionsDialog extends StatefulWidget {
  const _ConsolidationOptionsDialog({required this.isApplicationOwner});

  final bool isApplicationOwner;

  @override
  State<_ConsolidationOptionsDialog> createState() =>
      _ConsolidationOptionsDialogState();
}

class _ConsolidationOptionsDialogState
    extends State<_ConsolidationOptionsDialog> {
  late bool _isReady;
  Timer? _readyTimer;
  _ConsolidationMode _selectedMode = _ConsolidationMode.manualOnly;

  @override
  void initState() {
    super.initState();
    _isReady = widget.isApplicationOwner;
    if (!_isReady) {
      _readyTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _isReady = true);
      });
    }
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.shoppingConsolidateOptionsTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AiBilledSupportBanner(),
            if (_isReady) ...[
              const SizedBox(height: 16),
              RadioGroup<_ConsolidationMode>(
                groupValue: _selectedMode,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedMode = value);
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.shoppingConsolidateOptionManualOnlyDescription,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    _OptionTile(
                      title: l10n.shoppingConsolidateOptionManualOnly,
                      icon: PhosphorIconsRegular.notePencil,
                      mode: _ConsolidationMode.manualOnly,
                      selected: _selectedMode == _ConsolidationMode.manualOnly,
                      onRowTap: () => setState(
                        () => _selectedMode = _ConsolidationMode.manualOnly,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.shoppingConsolidateOptionFullDescription,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    _OptionTile(
                      title: l10n.shoppingConsolidateOptionFull,
                      icon: PhosphorIconsRegular.gitMerge,
                      mode: _ConsolidationMode.full,
                      selected: _selectedMode == _ConsolidationMode.full,
                      onRowTap: () =>
                          setState(() => _selectedMode = _ConsolidationMode.full),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: _isReady
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_selectedMode),
                child: Text(l10n.shoppingConsolidateLaunch),
              ),
            ]
          : [],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.icon,
    required this.mode,
    required this.selected,
    required this.onRowTap,
  });

  final String title;
  final IconData icon;
  final _ConsolidationMode mode;
  final bool selected;
  final VoidCallback onRowTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onRowTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            Radio<_ConsolidationMode>(value: mode),
          ],
        ),
      ),
    );
  }
}

/// Picks one category among [options] (id and display name); pops the
/// chosen id.
class _CategoryPickerDialog extends StatefulWidget {
  const _CategoryPickerDialog({
    required this.options,
    required this.initialId,
  });

  final List<({String id, String label})> options;
  final String initialId;

  @override
  State<_CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<_CategoryPickerDialog> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialId;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.shoppingChangeCategoryDialogTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: RadioGroup<String>(
          groupValue: _selectedId,
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedId = value);
            }
          },
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final option in widget.options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Radio<String>(value: option.id),
                    title: Text(option.label),
                    onTap: () => setState(() => _selectedId = option.id),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedId),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
