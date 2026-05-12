import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/presentation/ai_billed_support_banner.dart';
import 'package:planerz/features/ai_quotas/data/ai_quotas_repository.dart';
import 'package:planerz/features/auth/data/users_repository.dart'
    show
        stableUsersIdsKey,
        usersDataByIdsKeyStreamProvider,
        usersRepositoryProvider;
import 'package:planerz/features/shopping/data/shopping_item.dart';
import 'package:planerz/features/shopping/data/shopping_list_locks.dart';
import 'package:planerz/features/shopping/data/shopping_repository.dart';
import 'package:planerz/features/shopping/presentation/widgets/shopping_item_row.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/presentation/name_list_search.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripShoppingPage extends ConsumerWidget {
  const TripShoppingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = TripScope.of(context);
    final itemsAsync = ref.watch(tripShoppingItemsStreamProvider(trip.id));

    return itemsAsync.when(
      data: (items) => _ShoppingList(
        tripId: trip.id,
        items: items,
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
  _ShoppingFilter _activeFilter = _ShoppingFilter.all;
  String? _pendingAutofocusItemId;
  bool _isConsolidating = false;
  bool _isFabMenuOpen = false;
  bool _suppressRemoteConsolidatedSync = false;
  bool _isSavingConsolidated = false;
  String? _appliedRemoteConsolidatedFingerprint;
  ConsolidatedShoppingResult? _consolidationResult;
  List<_ConsolidatedEditableItem> _consolidatedItems = const [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _tabController = TabController(length: 2, vsync: this);
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
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final topOrder = widget.items.isEmpty ? 0 : (widget.items.first.order - 1);
    final newItemId = await ref.read(shoppingRepositoryProvider).addItem(
          tripId: widget.tripId,
          label: '',
          order: topOrder,
        );
    if (!mounted) return;
    setState(() => _pendingAutofocusItemId = newItemId);
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
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
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
        .where((item) => _matchesFilter(item, _activeFilter, currentUid))
        .toList(growable: false);
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

    return StreamBuilder<Map<String, Map<String, dynamic>>>(
      stream: usersDataStream,
      builder: (context, usersSnap) {
        final usersDataById = usersSnap.data ?? const <String, Map<String, dynamic>>{};
        return Stack(
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
                                    ? Icons.lock_outline
                                    : Icons.lock_open_outlined,
                              ),
                            )
                          else if (locks.manualListLocked)
                            Icon(
                              Icons.lock_outline,
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
                                    ? Icons.lock_outline
                                    : Icons.lock_open_outlined,
                              ),
                            )
                          else if (locks.consolidatedListLocked)
                            Icon(
                              Icons.lock_outline,
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
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: NameListSearchTextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SegmentedButton<_ShoppingFilter>(
                                  showSelectedIcon: false,
                                  segments: [
                                    ButtonSegment<_ShoppingFilter>(
                                      value: _ShoppingFilter.all,
                                      icon: const Icon(Icons.apps_outlined),
                                      tooltip: l10n.shoppingFilterAll,
                                    ),
                                    ButtonSegment<_ShoppingFilter>(
                                      value: _ShoppingFilter.todo,
                                      icon: const Icon(Icons.radio_button_unchecked),
                                      tooltip: l10n.shoppingFilterTodo,
                                    ),
                                    ButtonSegment<_ShoppingFilter>(
                                      value: _ShoppingFilter.done,
                                      icon: const Icon(Icons.check_circle_outline),
                                      tooltip: l10n.shoppingFilterDone,
                                    ),
                                    ButtonSegment<_ShoppingFilter>(
                                      value: _ShoppingFilter.claimedByMe,
                                      icon: const Icon(Icons.person_pin_circle_outlined),
                                      tooltip: l10n.shoppingFilterClaimedByMe,
                                    ),
                                  ],
                                  selected: {_activeFilter},
                                  onSelectionChanged: (selection) {
                                    if (selection.isEmpty) return;
                                    setState(() => _activeFilter = selection.first);
                                  },
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: l10n.shoppingFilterHelpTooltip,
                                  icon: const Icon(Icons.help_outline),
                                  onPressed: () => _showFilterHelp(context),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: widget.items.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.shopping_cart_outlined,
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
                                    : ListView.separated(
                                        padding: const EdgeInsets.only(
                                          left: 4,
                                          right: 4,
                                          top: 4,
                                          bottom: 88,
                                        ),
                                        itemCount: filteredItems.length,
                                        separatorBuilder: (_, __) => Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: Theme.of(context)
                                              .dividerColor
                                              .withValues(alpha: 0.35),
                                        ),
                                        itemBuilder: (context, index) {
                                          final item = filteredItems[index];
                                          return ShoppingItemRow(
                                            key: ValueKey(item.id),
                                            tripId: widget.tripId,
                                            item: item,
                                            usersDataById: usersDataById,
                                            normalizedLabelCounts: normalizedLabelCounts,
                                            structureLocked: manualLockRestrictsEditing,
                                            autoFocusLabel:
                                                item.id == _pendingAutofocusItemId,
                                            onAutoFocusHandled: () {
                                              if (!mounted) return;
                                              if (_pendingAutofocusItemId != item.id) return;
                                              setState(() => _pendingAutofocusItemId = null);
                                            },
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
                        consolidatedStructureLocked:
                            consolidatedLockRestrictsEditing,
                        showConsolidatedSaveButton: isAdminOrAbove &&
                            _consolidatedItems.isNotEmpty,
                        showConsolidatedClearButton: isAdminOrAbove &&
                            !locks.consolidatedListLocked &&
                            _consolidatedItems.isNotEmpty,
                        isSavingConsolidated: _isSavingConsolidated,
                        consolidatedRemoteAsync: consolidatedRemoteAsync,
                        suppressRemoteConsolidatedSync:
                            _suppressRemoteConsolidatedSync,
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
            if (showShoppingFab)
              Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_isFabMenuOpen) ...[
                    if (canDeleteCheckedItems) ...[
                      FloatingActionButton.extended(
                        heroTag: 'shopping_delete_checked_submenu',
                        tooltip: l10n.shoppingActionDeleteChecked,
                        backgroundColor:
                            Theme.of(context).colorScheme.error,
                        foregroundColor:
                            Theme.of(context).colorScheme.onError,
                        onPressed: checkedCount == 0
                            ? null
                            : () {
                                setState(() => _isFabMenuOpen = false);
                                _confirmAndDeleteChecked(context);
                              },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(l10n.shoppingActionDeleteChecked),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (canConsolidateWithAi) ...[
                      FloatingActionButton.extended(
                        heroTag: 'shopping_consolidate_ai_submenu',
                        tooltip: l10n.shoppingConsolidateAiTooltip,
                        onPressed: _isConsolidating || !ownerFlagReady
                            ? null
                            : () {
                                setState(() => _isFabMenuOpen = false);
                                _showConsolidateOptionsDialog(
                                  context,
                                  isApplicationOwner,
                                );
                              },
                        icon: _isConsolidating
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome),
                        label: Text(l10n.shoppingActionConsolidateAi),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FloatingActionButton.extended(
                      heroTag: 'shopping_add_item_submenu',
                      tooltip: l10n.shoppingActionAddItem,
                      onPressed: () {
                        setState(() => _isFabMenuOpen = false);
                        _addItem();
                      },
                      icon: const Icon(Icons.add),
                      label: Text(l10n.shoppingActionAddItem),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FloatingActionButton(
                    heroTag: 'shopping_list_main_fab',
                    tooltip: l10n.shoppingFabTooltip,
                    onPressed: () {
                      setState(() => _isFabMenuOpen = !_isFabMenuOpen);
                    },
                    child: Icon(
                      _isFabMenuOpen ? Icons.close : Icons.shopping_bag_outlined,
                    ),
                  ),
                ],
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
      await ref.read(shoppingRepositoryProvider).replaceConsolidatedShoppingList(
            tripId: widget.tripId,
            categories: _consolidationResult?.categories ?? const [],
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
    required bool consolidatedStructureLocked,
    required bool showConsolidatedSaveButton,
    required bool showConsolidatedClearButton,
    required bool isSavingConsolidated,
    required AsyncValue<ConsolidatedListFirestorePayload> consolidatedRemoteAsync,
    required bool suppressRemoteConsolidatedSync,
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
          child: Row(
            children: [
              Expanded(child: const SizedBox.shrink()),
              if (showConsolidatedSaveButton)
                IconButton(
                  tooltip: l10n.shoppingConsolidatedSave,
                  icon: isSavingConsolidated
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  onPressed: isSavingConsolidated
                      ? null
                      : () => _saveConsolidatedList(context),
                ),
              if (showConsolidatedClearButton)
                IconButton(
                  tooltip: l10n.shoppingConsolidatedClear,
                  icon: const Icon(Icons.close),
                  onPressed: () => _confirmAndClearConsolidated(context),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final entry = groups[index];
              return _ConsolidatedCategorySection(
                label: _categoryLabel(entry.key, languageCode, categories),
                items: entry.value,
                tripId: widget.tripId,
                usersDataById: usersDataById,
                normalizedLabelCounts: normalizedLabelCounts,
                structureLocked: consolidatedStructureLocked,
                onItemChanged: (itemId, updatedItem) {
                  _updateConsolidatedItem(itemId, (_) => updatedItem);
                },
                onItemDeleted: _deleteConsolidatedItem,
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
                icon: Icons.apps_outlined,
                label: l10n.shoppingFilterAll,
              ),
              const SizedBox(height: 8),
              _FilterLegendRow(
                icon: Icons.radio_button_unchecked,
                label: l10n.shoppingFilterTodo,
              ),
              const SizedBox(height: 8),
              _FilterLegendRow(
                icon: Icons.check_circle_outline,
                label: l10n.shoppingFilterDone,
              ),
              const SizedBox(height: 8),
              _FilterLegendRow(
                icon: Icons.person_pin_circle_outlined,
                label: l10n.shoppingFilterClaimedByMe,
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
}

String _normalizeItemLabel(String raw) {
  return raw.trim().toLowerCase();
}

bool _matchesFilter(ShoppingItem item, _ShoppingFilter filter, String currentUid) {
  final claimedBy = item.claimedBy?.trim() ?? '';
  return switch (filter) {
    _ShoppingFilter.all => true,
    _ShoppingFilter.todo => !item.checked,
    _ShoppingFilter.done => item.checked,
    _ShoppingFilter.claimedByMe => claimedBy.isNotEmpty && claimedBy == currentUid,
  };
}

enum _ShoppingFilter {
  all,
  todo,
  done,
  claimedByMe,
}

enum _ConsolidationMode { full, manualOnly }

String _categoryLabel(
  String categoryId,
  String languageCode,
  List<ConsolidatedShoppingCategory> categories,
) {
  final match = categories.where((c) => c.id == categoryId).firstOrNull;
  if (match == null) return categoryId;
  return match.label(languageCode);
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
  return [for (final id in ordered) MapEntry(id, map[id]!)];
}

class _ConsolidatedCategorySection extends StatelessWidget {
  const _ConsolidatedCategorySection({
    required this.label,
    required this.items,
    required this.tripId,
    required this.usersDataById,
    required this.normalizedLabelCounts,
    required this.structureLocked,
    required this.onItemChanged,
    required this.onItemDeleted,
  });

  final String label;
  final List<ShoppingItem> items;
  final String tripId;
  final Map<String, Map<String, dynamic>> usersDataById;
  final Map<String, int> normalizedLabelCounts;
  final bool structureLocked;
  final void Function(String itemId, ShoppingItem updatedItem) onItemChanged;
  final void Function(String itemId) onItemDeleted;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: EdgeInsets.zero,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          ShoppingItemRow(
            key: ValueKey(items[i].id),
            tripId: tripId,
            item: items[i],
            usersDataById: usersDataById,
            normalizedLabelCounts: normalizedLabelCounts,
            structureLocked: structureLocked,
            onToggleCheckedOverride: (checked) async {
              onItemChanged(
                items[i].id,
                ShoppingItem(
                  id: items[i].id,
                  label: items[i].label,
                  checked: checked,
                  quantityValue: items[i].quantityValue,
                  quantityUnit: items[i].quantityUnit,
                  createdAt: items[i].createdAt,
                  order: items[i].order,
                  createdBy: items[i].createdBy,
                  claimedBy: items[i].claimedBy,
                ),
              );
            },
            onSetClaimedByOverride: (claimedBy) async {
              onItemChanged(
                items[i].id,
                ShoppingItem(
                  id: items[i].id,
                  label: items[i].label,
                  checked: items[i].checked,
                  quantityValue: items[i].quantityValue,
                  quantityUnit: items[i].quantityUnit,
                  createdAt: items[i].createdAt,
                  order: items[i].order,
                  createdBy: items[i].createdBy,
                  claimedBy: claimedBy,
                ),
              );
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
          if (i < items.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              indent: 12,
              endIndent: 12,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
            ),
        ],
      ],
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
                      icon: Icons.edit_note,
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
                      icon: Icons.merge_type,
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

