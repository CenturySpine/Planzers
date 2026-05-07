import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/data/users_repository.dart'
    show
        stableUsersIdsKey,
        usersDataByIdsKeyStreamProvider,
        usersRepositoryProvider;
import 'package:planerz/features/shopping/data/shopping_item.dart';
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

class _ShoppingListState extends ConsumerState<_ShoppingList> {
  late final TextEditingController _searchController;
  _ShoppingFilter _activeFilter = _ShoppingFilter.all;
  String? _pendingAutofocusItemId;
  bool _isConsolidating = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  Future<void> _showConsolidationNotAvailableForAccountDialog(
    BuildContext context,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.shoppingConsolidateAiNotAvailableTitle),
          content: Text(l10n.shoppingConsolidateAiNotAvailableBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.commonClose),
            ),
          ],
        );
      },
    );
  }

  Future<void> _consolidateWithAi(BuildContext context) async {
    if (_isConsolidating) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isConsolidating = true);
    try {
      final result = await ref
          .read(shoppingRepositoryProvider)
          .consolidateWithAi(tripId: widget.tripId);
      if (!context.mounted) return;
      await _showConsolidatedItemsDialog(context, result);
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _isConsolidating = false);
    }
  }

  Future<void> _showConsolidatedItemsDialog(
    BuildContext context,
    ConsolidatedShoppingResult result,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final summary = result.summary;
        final items = result.items;
        return AlertDialog(
          title: const Text('Consolidation IA (POC)'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Ingrédients recettes en entrée: ${summary.recipeOriginalLineCount}\n'
                    'Ingrédients manuels en entrée: ${summary.manualOriginalLineCount}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Flexible(
                  child: items.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Aucun élément consolidé.'),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: theme.dividerColor.withValues(alpha: 0.4),
                          ),
                          itemBuilder: (context, index) {
                            return _ConsolidatedItemTile(item: items[index]);
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
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
    final canDeleteCheckedItems = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: widget.trip.shoppingPermissions.deleteCheckedItemsMinRole,
    );
    final canConsolidateWithAi = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: TripPermissionRole.admin,
    );
    final currentUserOwnerAsync = ref.watch(
      usersDataByIdsKeyStreamProvider(stableUsersIdsKey([currentUid])),
    );
    final ownerData = currentUserOwnerAsync.asData?.value;
    final ownerFlagReady = ownerData != null;
    final isApplicationOwner =
        ownerData?[currentUid]?['isApplicationOwner'] == true;
    final searchQuery = _searchController.text;
    final searchFilteredItems = widget.items
        .where((item) => displayNameMatchesNameSearch(item.label, searchQuery))
        .toList(growable: false);
    final filteredItems = searchFilteredItems
        .where((item) => _matchesFilter(item, _activeFilter, currentUid))
        .toList(growable: false);
    final claimedByIds = widget.items
        .map((item) => item.claimedBy?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final normalizedLabelCounts = <String, int>{};
    for (final item in widget.items) {
      final normalized = _normalizeItemLabel(item.label);
      if (normalized.isEmpty) continue;
      normalizedLabelCounts[normalized] =
          (normalizedLabelCounts[normalized] ?? 0) + 1;
    }

    final usersDataStream =
        ref.read(usersRepositoryProvider).watchUsersDataByIds(claimedByIds);

    return StreamBuilder<Map<String, Map<String, dynamic>>>(
      stream: usersDataStream,
      builder: (context, usersSnap) {
        final usersDataById = usersSnap.data ?? const <String, Map<String, dynamic>>{};
        return Stack(
          children: [
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
            Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canConsolidateWithAi) ...[
                    FloatingActionButton(
                      heroTag: 'consolidate_shopping_with_ai',
                      tooltip: l10n.shoppingConsolidateAiTooltip,
                      onPressed: _isConsolidating || !ownerFlagReady
                          ? null
                          : () {
                              if (isApplicationOwner) {
                                _consolidateWithAi(context);
                              } else {
                                _showConsolidationNotAvailableForAccountDialog(
                                  context,
                                );
                              }
                            },
                      child: _isConsolidating
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FloatingActionButton(
                    heroTag: 'add_shopping_item',
                    onPressed: _addItem,
                    child: const Icon(Icons.add),
                  ),
                  if (canDeleteCheckedItems) ...[
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'delete_checked_shopping_items',
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                      onPressed: checkedCount == 0
                          ? null
                          : () => _confirmAndDeleteChecked(context),
                      child: const Icon(Icons.delete_outline),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
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
}

String _normalizeItemLabel(String raw) {
  return raw.trim().toLowerCase();
}

String _formatConsolidatedQuantity(double value, String unit) {
  final hasInteger = value == value.roundToDouble();
  final displayValue = hasInteger ? value.toInt().toString() : value.toString();
  final cleanUnit = unit.trim();
  if (cleanUnit.isEmpty) return displayValue;
  return '$displayValue $cleanUnit';
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

class _ConsolidatedItemTile extends StatelessWidget {
  const _ConsolidatedItemTile({required this.item});

  final ConsolidatedShoppingItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantity = _formatConsolidatedQuantity(
      item.quantityValue,
      item.quantityUnit,
    );
    final sourceIcon = _consolidatedSourceIcon(item.sourceType);
    final showSources =
        item.sourceType == ConsolidatedShoppingSourceType.mixed &&
            item.sourceItems.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        item.label,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      sourceIcon,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                quantity,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (showSources)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final source in item.sourceItems)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: _ConsolidatedSourceLine(source: source),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ConsolidatedSourceLine extends StatelessWidget {
  const _ConsolidatedSourceLine({required this.source});

  final ConsolidatedShoppingSourceItem source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isManual = source.source == 'manual';
    final icon = isManual ? Icons.edit_note : Icons.restaurant_menu;
    final quantity = _formatConsolidatedQuantity(
      source.originalQuantityValue,
      source.originalQuantityUnit,
    );
    final detail = quantity.isEmpty
        ? source.originalLabel
        : '${source.originalLabel} — $quantity';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

IconData _consolidatedSourceIcon(ConsolidatedShoppingSourceType sourceType) {
  switch (sourceType) {
    case ConsolidatedShoppingSourceType.manual:
      return Icons.edit_note;
    case ConsolidatedShoppingSourceType.recipe:
      return Icons.restaurant_menu;
    case ConsolidatedShoppingSourceType.mixed:
      return Icons.merge_type;
  }
}
