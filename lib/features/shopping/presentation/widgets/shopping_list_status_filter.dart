import 'package:flutter/material.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Shopping list row filter by checked state: all, unchecked (to buy), or checked (done).
enum ShoppingListStatusFilter {
  all,
  todo,
  done,
}

/// Whether the list is further restricted to items claimed by the current user.
bool shoppingItemMatchesShoppingListFilters(
  ShoppingItem item, {
  required ShoppingListStatusFilter statusFilter,
  required bool onlyClaimedByMe,
  required String currentUid,
}) {
  final statusOk = switch (statusFilter) {
    ShoppingListStatusFilter.all => true,
    ShoppingListStatusFilter.todo => !item.checked,
    ShoppingListStatusFilter.done => item.checked,
  };
  if (!statusOk) return false;
  if (!onlyClaimedByMe) return true;
  final claimedBy = item.claimedBy?.trim() ?? '';
  return claimedBy.isNotEmpty && claimedBy == currentUid;
}

/// Status chips (exclusive) + optional « claimed by me » chip, in a
/// single compact scrollable row.
class ShoppingListFilterBar extends StatelessWidget {
  const ShoppingListFilterBar({
    super.key,
    required this.selectedStatus,
    required this.onlyClaimedByMe,
    required this.onStatusChanged,
    required this.onOnlyClaimedByMeChanged,
    this.trailing = const [],
  });

  final ShoppingListStatusFilter selectedStatus;
  final bool onlyClaimedByMe;
  final ValueChanged<ShoppingListStatusFilter> onStatusChanged;
  final ValueChanged<bool> onOnlyClaimedByMeChanged;

  /// Extra actions shown at the end of the row (e.g. list overflow menu).
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget status(ShoppingListStatusFilter value, String label, String tip) =>
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Tooltip(
            message: tip,
            child: ChoiceChip(
              label: Text(label),
              selected: selectedStatus == value,
              onSelected: (_) => onStatusChanged(value),
            ),
          ),
        );
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                status(ShoppingListStatusFilter.all, l10n.commonAll,
                    l10n.shoppingFilterAll),
                status(ShoppingListStatusFilter.todo, l10n.shoppingFilterTodo,
                    l10n.shoppingFilterTodo),
                status(ShoppingListStatusFilter.done, l10n.shoppingFilterDone,
                    l10n.shoppingFilterDone),
                Tooltip(
                  message: l10n.shoppingFilterClaimedByMe,
                  child: FilterChip(
                    avatar: const Icon(Icons.person_rounded),
                    label: Text(l10n.commonMe),
                    selected: onlyClaimedByMe,
                    onSelected: onOnlyClaimedByMeChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
        ...trailing,
      ],
    );
  }
}
