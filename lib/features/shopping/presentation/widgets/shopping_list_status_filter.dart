import 'package:planerz/app/theme/app_icons.dart';
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
///
/// An item can be held by the user's account ([currentUid]) or, when an admin
/// assigned it before the user had an account, by their trip participant id
/// ([currentParticipantId]).
///
/// [onlyPrivate] further restricts it to the user's private items.
bool shoppingItemMatchesShoppingListFilters(
  ShoppingItem item, {
  required ShoppingListStatusFilter statusFilter,
  required bool onlyClaimedByMe,
  required String currentUid,
  String currentParticipantId = '',
  bool onlyPrivate = false,
}) {
  final statusOk = switch (statusFilter) {
    ShoppingListStatusFilter.all => true,
    ShoppingListStatusFilter.todo => !item.checked,
    ShoppingListStatusFilter.done => item.checked,
  };
  if (!statusOk) return false;
  if (onlyPrivate && !item.isPrivate) return false;
  if (!onlyClaimedByMe) return true;
  final claimedBy = item.claimedBy?.trim() ?? '';
  return claimedBy.isNotEmpty &&
      (claimedBy == currentUid ||
          (currentParticipantId.isNotEmpty &&
              claimedBy == currentParticipantId));
}

/// Status chips (exclusive) + « claimed by me » and optional « private »
/// chips (cumulative), in a single compact scrollable row.
class ShoppingListFilterBar extends StatelessWidget {
  const ShoppingListFilterBar({
    super.key,
    required this.selectedStatus,
    required this.onlyClaimedByMe,
    required this.onStatusChanged,
    required this.onOnlyClaimedByMeChanged,
    this.onlyPrivate = false,
    this.onOnlyPrivateChanged,
    this.trailing = const [],
  });

  final ShoppingListStatusFilter selectedStatus;
  final bool onlyClaimedByMe;
  final ValueChanged<ShoppingListStatusFilter> onStatusChanged;
  final ValueChanged<bool> onOnlyClaimedByMeChanged;
  final bool onlyPrivate;

  /// Null hides the « private » chip (lists without private items).
  final ValueChanged<bool>? onOnlyPrivateChanged;

  /// Extra actions shown at the end of the row (e.g. list overflow menu).
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget status(ShoppingListStatusFilter value, String label, String tip) =>
        Tooltip(
          message: tip,
          child: ChoiceChip(
            label: Text(label),
            selected: selectedStatus == value,
            onSelected: (_) => onStatusChanged(value),
          ),
        );
    final chips = <Widget>[
      status(ShoppingListStatusFilter.all, l10n.commonAll,
          l10n.shoppingFilterAll),
      status(ShoppingListStatusFilter.todo, l10n.shoppingFilterTodo,
          l10n.shoppingFilterTodo),
      status(ShoppingListStatusFilter.done, l10n.shoppingFilterDone,
          l10n.shoppingFilterDone),
      Tooltip(
        message: l10n.shoppingFilterClaimedByMe,
        child: FilterChip(
          avatar: const Icon(PhosphorIconsFill.user),
          label: Text(l10n.commonMe),
          selected: onlyClaimedByMe,
          onSelected: onOnlyClaimedByMeChanged,
        ),
      ),
      if (onOnlyPrivateChanged != null)
        Tooltip(
          message: l10n.shoppingFilterPrivateTooltip,
          child: FilterChip(
            avatar: const Icon(PhosphorIconsFill.lock),
            label: Text(l10n.shoppingFilterPrivate),
            selected: onlyPrivate,
            onSelected: onOnlyPrivateChanged,
          ),
        ),
    ];
    return Row(
      children: [
        Expanded(
          // Chips spread over the whole width; on screens too narrow for
          // them all, the row scrolls instead.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  spacing: 6,
                  children: chips,
                ),
              ),
            ),
          ),
        ),
        ...trailing,
      ],
    );
  }
}
