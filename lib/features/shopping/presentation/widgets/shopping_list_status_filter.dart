import 'dart:math' as math;

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

const double _kChipGap = 4;
const EdgeInsets _kChipPadding = EdgeInsets.symmetric(horizontal: 4);
const EdgeInsets _kChipLabelPadding = EdgeInsets.symmetric(horizontal: 2);
const double _kChipIconSize = 16;
const double _kChipIconGap = 4;

/// One filter chip of [ShoppingListFilterBar].
class _FilterSpec {
  const _FilterSpec({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.isChoice = false,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;

  /// Exclusive status chip (vs. cumulative toggle).
  final bool isChoice;
}

/// Status chips (exclusive) + « claimed by me » and optional « private »
/// chips (cumulative), sharing the whole width of the row.
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
    _FilterSpec status(
      ShoppingListStatusFilter value,
      String label,
      String tooltip,
    ) =>
        _FilterSpec(
          label: label,
          tooltip: tooltip,
          selected: selectedStatus == value,
          onSelected: (_) => onStatusChanged(value),
          isChoice: true,
        );
    final specs = <_FilterSpec>[
      status(ShoppingListStatusFilter.all, l10n.commonAll,
          l10n.shoppingFilterAll),
      status(ShoppingListStatusFilter.todo, l10n.shoppingFilterTodo,
          l10n.shoppingFilterTodo),
      status(ShoppingListStatusFilter.done, l10n.shoppingFilterDone,
          l10n.shoppingFilterDone),
      _FilterSpec(
        label: l10n.commonMe,
        tooltip: l10n.shoppingFilterClaimedByMe,
        icon: PhosphorIconsFill.user,
        selected: onlyClaimedByMe,
        onSelected: onOnlyClaimedByMeChanged,
      ),
      if (onOnlyPrivateChanged != null)
        _FilterSpec(
          label: l10n.shoppingFilterPrivate,
          tooltip: l10n.shoppingFilterPrivateTooltip,
          icon: PhosphorIconsFill.lock,
          selected: onlyPrivate,
          onSelected: onOnlyPrivateChanged!,
        ),
    ];
    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final widths =
                  _chipWidths(context, specs, constraints.maxWidth);
              return Row(
                spacing: _kChipGap,
                children: [
                  for (var i = 0; i < specs.length; i++)
                    SizedBox(width: widths[i], child: _buildChip(specs[i])),
                ],
              );
            },
          ),
        ),
        ...trailing,
      ],
    );
  }

  Widget _buildChip(_FilterSpec spec) {
    final content = _FilterChipContent(label: spec.label, icon: spec.icon);
    return Tooltip(
      message: spec.tooltip,
      child: spec.isChoice
          ? ChoiceChip(
              label: content,
              padding: _kChipPadding,
              labelPadding: _kChipLabelPadding,
              selected: spec.selected,
              onSelected: spec.onSelected,
            )
          : FilterChip(
              label: content,
              padding: _kChipPadding,
              labelPadding: _kChipLabelPadding,
              selected: spec.selected,
              onSelected: spec.onSelected,
            ),
    );
  }

  /// Splits [available] between the chips: each gets its paddings, plus a
  /// share of the rest weighted by the width of its content. Every label
  /// thus ends up at the same size, shrunk only when even that is too wide.
  static List<double> _chipWidths(
    BuildContext context,
    List<_FilterSpec> specs,
    double available,
  ) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.merge(
      WidgetStateProperty.resolveAs<TextStyle?>(
        theme.chipTheme.labelStyle,
        const <WidgetState>{},
      ),
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final contentWidths = [
      for (final spec in specs)
        _textWidth(spec.label, style, textScaler) +
            (spec.icon != null ? _kChipIconSize + _kChipIconGap : 0),
    ];
    final fixedWidth = _kChipPadding.horizontal + _kChipLabelPadding.horizontal;
    final free = math.max(
      0.0,
      available - _kChipGap * (specs.length - 1) - fixedWidth * specs.length,
    );
    final totalContent = contentWidths.fold(0.0, (sum, w) => sum + w);
    return [
      for (final w in contentWidths)
        fixedWidth +
            (totalContent > 0 ? free * w / totalContent : free / specs.length),
    ];
  }

  static double _textWidth(
    String text,
    TextStyle? style,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// Icon and text of a filter chip, centered in the room the chip gets and
/// shrunk only when that room is too small.
class _FilterChipContent extends StatelessWidget {
  const _FilterChipContent({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      heightFactor: 1,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: _kChipIconSize,
                color: ChipTheme.of(context).iconTheme?.color,
              ),
              const SizedBox(width: _kChipIconGap),
            ],
            Text(label, maxLines: 1, softWrap: false),
          ],
        ),
      ),
    );
  }
}
