import 'package:flutter/material.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/expenses/data/expense_icon_catalog.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Bottom sheet grid for picking an expense or post icon key.
Future<String?> showExpenseIconPickerSheet(
  BuildContext context, {
  required String currentKey,
  required String title,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ExpenseIconPickerSheet(
      currentKey: currentKey,
      title: title,
    ),
  );
}

class _ExpenseIconPickerSheet extends StatelessWidget {
  const _ExpenseIconPickerSheet({
    required this.currentKey,
    required this.title,
  });

  final String currentKey;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: NeonPalette.divider,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: NeonPalette.deep,
                              ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppLocalizations.of(context)!.commonClose,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    for (final group in kExpenseIconCatalog) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Text(
                          group.labelFr,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: NeonPalette.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      GridView.count(
                        crossAxisCount: 5,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1,
                        children: [
                          for (final key in group.iconKeys)
                            _IconTile(
                              iconKey: key,
                              selected: key == currentKey,
                              onTap: () => Navigator.pop(context, key),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.iconKey,
    required this.selected,
    required this.onTap,
  });

  final String iconKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? NeonPalette.accent : NeonPalette.segmentTrack,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Icon(
            expenseIconDataForKey(iconKey, fallbackKey: kDefaultExpenseIconKey),
            size: 26,
            color: selected ? Colors.white : NeonPalette.deep,
          ),
        ),
      ),
    );
  }
}
