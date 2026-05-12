import 'package:flutter/material.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Shopping list row filter: all, unchecked, checked, or claimed by current user.
enum ShoppingListStatusFilter {
  all,
  todo,
  done,
  claimedByMe,
}

bool shoppingItemMatchesStatusFilter(
  ShoppingItem item,
  ShoppingListStatusFilter filter,
  String currentUid,
) {
  final claimedBy = item.claimedBy?.trim() ?? '';
  return switch (filter) {
    ShoppingListStatusFilter.all => true,
    ShoppingListStatusFilter.todo => !item.checked,
    ShoppingListStatusFilter.done => item.checked,
    ShoppingListStatusFilter.claimedByMe =>
      claimedBy.isNotEmpty && claimedBy == currentUid,
  };
}

/// Segmented status filter + help, shared by manual and consolidated shopping lists.
class ShoppingListStatusFilterBar extends StatelessWidget {
  const ShoppingListStatusFilterBar({
    super.key,
    required this.selected,
    required this.onSelectionChanged,
    required this.onHelpPressed,
  });

  final ShoppingListStatusFilter selected;
  final ValueChanged<ShoppingListStatusFilter> onSelectionChanged;
  final VoidCallback onHelpPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
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
            ButtonSegment<ShoppingListStatusFilter>(
              value: ShoppingListStatusFilter.claimedByMe,
              icon: const Icon(Icons.person_pin_circle_outlined),
              tooltip: l10n.shoppingFilterClaimedByMe,
            ),
          ],
          selected: {selected},
          onSelectionChanged: (selection) {
            if (selection.isEmpty) return;
            onSelectionChanged(selection.first);
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.shoppingFilterHelpTooltip,
          icon: const Icon(Icons.help_outline),
          onPressed: onHelpPressed,
        ),
      ],
    );
  }
}
