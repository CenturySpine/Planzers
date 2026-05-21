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

/// Status segments (exclusive) + optional « claimed by me » filter + help.
class ShoppingListFilterBar extends StatelessWidget {
  const ShoppingListFilterBar({
    super.key,
    required this.selectedStatus,
    required this.onlyClaimedByMe,
    required this.onStatusChanged,
    required this.onOnlyClaimedByMeChanged,
    required this.onHelpPressed,
  });

  final ShoppingListStatusFilter selectedStatus;
  final bool onlyClaimedByMe;
  final ValueChanged<ShoppingListStatusFilter> onStatusChanged;
  final ValueChanged<bool> onOnlyClaimedByMeChanged;
  final VoidCallback onHelpPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<ShoppingListStatusFilter>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment<ShoppingListStatusFilter>(
              value: ShoppingListStatusFilter.all,
              icon: const Icon(Icons.apps_outlined),
              tooltip: l10n.shoppingFilterAll,
            ),
            ButtonSegment<ShoppingListStatusFilter>(
              value: ShoppingListStatusFilter.todo,
              icon: const Icon(Icons.radio_button_unchecked),
              tooltip: l10n.shoppingFilterTodo,
            ),
            ButtonSegment<ShoppingListStatusFilter>(
              value: ShoppingListStatusFilter.done,
              icon: const Icon(Icons.check_circle_outline),
              tooltip: l10n.shoppingFilterDone,
            ),
          ],
          selected: {selectedStatus},
          onSelectionChanged: (selection) {
            if (selection.isEmpty) return;
            onStatusChanged(selection.first);
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.shoppingFilterClaimedByMe,
          isSelected: onlyClaimedByMe,
          onPressed: () => onOnlyClaimedByMeChanged(!onlyClaimedByMe),
          icon: const Icon(Icons.person_pin_circle_outlined),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: l10n.shoppingFilterHelpTooltip,
          icon: const Icon(Icons.help_outline),
          onPressed: onHelpPressed,
        ),
      ],
    );
  }
}
