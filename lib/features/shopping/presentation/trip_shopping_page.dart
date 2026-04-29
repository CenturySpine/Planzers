import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/ingredients/presentation/ingredient_line_editor.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';
import 'package:planerz/features/shopping/data/shopping_repository.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
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
                            return _ShoppingItemRow(
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

class _ShoppingItemRow extends ConsumerStatefulWidget {
  const _ShoppingItemRow({
    super.key,
    required this.tripId,
    required this.item,
    required this.usersDataById,
    required this.normalizedLabelCounts,
    this.autoFocusLabel = false,
    this.onAutoFocusHandled,
  });

  final String tripId;
  final ShoppingItem item;
  final Map<String, Map<String, dynamic>> usersDataById;
  final Map<String, int> normalizedLabelCounts;
  final bool autoFocusLabel;
  final VoidCallback? onAutoFocusHandled;

  @override
  ConsumerState<_ShoppingItemRow> createState() => _ShoppingItemRowState();
}

class _ShoppingItemRowState extends ConsumerState<_ShoppingItemRow> {
  String _photoUrlFromUserData(Map<String, dynamic>? userData) {
    if (userData == null) return '';
    final account = (userData['account'] as Map<String, dynamic>?) ?? const {};
    final accountPhoto = (account['photoUrl'] as String?)?.trim() ?? '';
    if (accountPhoto.isNotEmpty) return accountPhoto;
    return (userData['photoUrl'] as String?)?.trim() ?? '';
  }

  bool _isDuplicateLabel(String value) {
    final normalized = _normalizeItemLabel(value);
    if (normalized.isEmpty) return false;
    final totalCount = widget.normalizedLabelCounts[normalized] ?? 0;
    final ownMatches =
        _normalizeItemLabel(widget.item.label) == normalized ? 1 : 0;
    return (totalCount - ownMatches) > 0;
  }

  Future<void> _toggleChecked(bool? value) async {
    await ref.read(shoppingRepositoryProvider).setChecked(
          tripId: widget.tripId,
          itemId: widget.item.id,
          checked: value ?? false,
        );
  }

  Future<void> _delete() async {
    await ref.read(shoppingRepositoryProvider).deleteItem(
          tripId: widget.tripId,
          itemId: widget.item.id,
        );
  }

  Future<void> _toggleClaim() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid.trim() ?? '';
    if (uid.isEmpty) return;
    final claimedBy = widget.item.claimedBy?.trim() ?? '';
    if (claimedBy.isNotEmpty && claimedBy != uid) return;

    final nextClaimedBy = claimedBy == uid ? null : uid;
    await ref.read(shoppingRepositoryProvider).setClaimedBy(
          tripId: widget.tripId,
          itemId: widget.item.id,
          claimedBy: nextClaimedBy,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isChecked = widget.item.checked;
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUid = currentUser?.uid.trim() ?? '';
    final claimedBy = widget.item.claimedBy?.trim() ?? '';
    final isClaimedByMe = claimedBy.isNotEmpty && claimedBy == currentUid;
    final isClaimedByOther = claimedBy.isNotEmpty && claimedBy != currentUid;
    final claimedByUserData =
        claimedBy.isEmpty ? null : widget.usersDataById[claimedBy];
    final claimedByLabel = resolveTripMemberDisplayLabel(
      memberId: claimedBy,
      userData: claimedByUserData,
      tripMemberPublicLabels: const {},
      currentUserId: currentUid,
      emptyFallback: AppLocalizations.of(context)!.shoppingTravelerFallback,
    );
    final claimedByPhotoUrl = _photoUrlFromUserData(claimedByUserData);
    final labelStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          decoration:
              isChecked ? TextDecoration.lineThrough : TextDecoration.none,
          color:
              isChecked ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
        );

    return IngredientLineEditor(
      label: widget.item.label,
      quantityValue: widget.item.quantityValue,
      quantityUnit: widget.item.quantityUnit,
      onSave: (value) async {
        await ref.read(shoppingRepositoryProvider).updateItem(
              tripId: widget.tripId,
              itemId: widget.item.id,
              label: value.label,
              checked: widget.item.checked,
              quantityValue: value.quantityValue,
              quantityUnit: value.quantityUnit,
            );
      },
      onDelete: _delete,
      autoFocusLabel: widget.autoFocusLabel,
      onAutoFocusHandled: widget.onAutoFocusHandled,
      isDuplicateLabel: _isDuplicateLabel,
      labelStyle: labelStyle,
      prefixWidgets: [
        Checkbox(
          value: isChecked,
          onChanged: _toggleChecked,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Transform.translate(
          offset: const Offset(-4, 0),
          child: _ClaimButton(
            isClaimedByMe: isClaimedByMe,
            isClaimedByOther: isClaimedByOther,
            claimedByLabel: claimedByLabel,
            claimedByPhotoUrl: claimedByPhotoUrl,
            onTap: _toggleClaim,
            l10n: AppLocalizations.of(context)!,
          ),
        ),
      ],
    );
  }
}

class _ClaimButton extends StatelessWidget {
  const _ClaimButton({
    required this.isClaimedByMe,
    required this.isClaimedByOther,
    required this.claimedByLabel,
    required this.claimedByPhotoUrl,
    required this.onTap,
    required this.l10n,
  });

  final bool isClaimedByMe;
  final bool isClaimedByOther;
  final String claimedByLabel;
  final String claimedByPhotoUrl;
  final Future<void> Function() onTap;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const badgeSize = 26.0;
    const badgeRadius = 11.0;

    Widget claimAvatar({
      required String label,
      required String photoUrl,
      required Color backgroundColor,
      required Color foregroundColor,
    }) {
      final cleanUrl = photoUrl.trim();
      return CircleAvatar(
        radius: badgeRadius,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        foregroundImage: cleanUrl.isNotEmpty ? NetworkImage(cleanUrl) : null,
        child: Text(
          avatarInitialFromDisplayLabel(label),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );
    }

    final compactStyle = IconButton.styleFrom(
      padding: const EdgeInsets.all(2),
      minimumSize: const Size(badgeSize, badgeSize),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    if (isClaimedByMe) {
      final avatar = claimAvatar(
        label: claimedByLabel,
        photoUrl: claimedByPhotoUrl,
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      );
      return IconButton(
        style: compactStyle,
        tooltip: l10n.shoppingClaimRemoveMine,
        onPressed: () => onTap(),
        icon: avatar,
      );
    }

    if (isClaimedByOther) {
      final avatar = claimAvatar(
        label: claimedByLabel,
        photoUrl: claimedByPhotoUrl,
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
      );
      return Tooltip(
        message: l10n.shoppingClaimAlreadyBy(claimedByLabel),
        child: SizedBox(
          width: badgeSize,
          height: badgeSize,
          child: Center(child: avatar),
        ),
      );
    }

    return IconButton(
      style: compactStyle,
      tooltip: l10n.shoppingClaimTake,
      onPressed: () => onTap(),
      icon: const Icon(Icons.accessibility_new_outlined, size: 17),
    );
  }
}
