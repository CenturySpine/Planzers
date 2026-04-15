import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/shopping/data/shopping_item.dart';
import 'package:planzers/features/shopping/data/shopping_repository.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';

class TripShoppingPage extends ConsumerWidget {
  const TripShoppingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = TripScope.of(context);
    final itemsAsync =
        ref.watch(tripShoppingItemsStreamProvider(trip.id));

    return itemsAsync.when(
      data: (items) => _ShoppingList(tripId: trip.id, items: items),
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Erreur : $e'),
        ),
      ),
    );
  }
}

class _ShoppingList extends ConsumerWidget {
  const _ShoppingList({
    required this.tripId,
    required this.items,
  });

  final String tripId;
  final List<ShoppingItem> items;

  Future<void> _addItem(WidgetRef ref) async {
    await ref.read(shoppingRepositoryProvider).addItem(
          tripId: tripId,
          label: '',
          order: items.length,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        items.isEmpty
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
                      'Liste de courses vide',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Appuyez sur + pour ajouter un article.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(
                    left: 8, right: 8, top: 8, bottom: 88),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return _ShoppingItemRow(
                    key: ValueKey(items[index].id),
                    tripId: tripId,
                    item: items[index],
                  );
                },
              ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'add_shopping_item',
            onPressed: () => _addItem(ref),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

class _ShoppingItemRow extends ConsumerStatefulWidget {
  const _ShoppingItemRow({
    super.key,
    required this.tripId,
    required this.item,
  });

  final String tripId;
  final ShoppingItem item;

  @override
  ConsumerState<_ShoppingItemRow> createState() => _ShoppingItemRowState();
}

class _ShoppingItemRowState extends ConsumerState<_ShoppingItemRow> {
  static const Duration _autoSaveDebounce = Duration(milliseconds: 600);
  late TextEditingController _labelController;
  late TextEditingController _quantityController;
  late ShoppingUnit _selectedUnit;
  bool _isSaving = false;
  Timer? _autoSaveTimer;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.item.label);
    _quantityController = TextEditingController(
      text: _formatQuantity(widget.item.quantityValue),
    );
    _selectedUnit = widget.item.quantityUnit;
  }

  @override
  void didUpdateWidget(_ShoppingItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync Firestore changes into fields only when the field is not focused
    if (!_labelFocusNode.hasFocus &&
        oldWidget.item.label != widget.item.label) {
      _labelController.text = widget.item.label;
    }
    if (!_quantityFocusNode.hasFocus) {
      if (oldWidget.item.quantityValue != widget.item.quantityValue) {
        _quantityController.text =
            _formatQuantity(widget.item.quantityValue);
      }
      if (oldWidget.item.quantityUnit != widget.item.quantityUnit) {
        setState(() => _selectedUnit = widget.item.quantityUnit);
      }
    }
  }

  final FocusNode _labelFocusNode = FocusNode();
  final FocusNode _quantityFocusNode = FocusNode();

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _labelController.dispose();
    _quantityController.dispose();
    _labelFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  String _formatQuantity(double value) {
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  double _parseQuantity(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    return double.tryParse(normalized) ?? 1.0;
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDebounce, _save);
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final label = _labelController.text.trim();
    final quantity = _parseQuantity(_quantityController.text);
    final safeQuantity = quantity > 0 ? quantity : 1.0;
    final hasChanged = label != widget.item.label.trim() ||
        safeQuantity != widget.item.quantityValue ||
        _selectedUnit != widget.item.quantityUnit;
    if (!hasChanged) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(shoppingRepositoryProvider).updateItem(
            tripId: widget.tripId,
            itemId: widget.item.id,
            label: label,
            checked: widget.item.checked,
            quantityValue: safeQuantity,
            quantityUnit: _selectedUnit,
          );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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

  void _incrementQuantity() {
    final current = _parseQuantity(_quantityController.text);
    final next = (current + 1).toDouble();
    _quantityController.text = _formatQuantity(next);
    _scheduleAutoSave();
  }

  void _decrementQuantity() {
    final current = _parseQuantity(_quantityController.text);
    final next = (current - 1).toDouble();
    if (next <= 0) return;
    _quantityController.text = _formatQuantity(next);
    _scheduleAutoSave();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isChecked = widget.item.checked;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Checkbox ──────────────────────────────────────────────
            Checkbox(
              value: isChecked,
              onChanged: _toggleChecked,
            ),

            // ── Label input ───────────────────────────────────────────
            Expanded(
              child: TextField(
                controller: _labelController,
                focusNode: _labelFocusNode,
                decoration: InputDecoration(
                  hintText: 'Article…',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  suffixIcon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      decoration: isChecked
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      color: isChecked
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onSurface,
                    ),
                onSubmitted: (_) => _save(),
                onEditingComplete: _save,
                onChanged: (_) => _scheduleAutoSave(),
              ),
            ),

            // ── Quantity controls ─────────────────────────────────────
            _QuantityControls(
              quantityController: _quantityController,
              quantityFocusNode: _quantityFocusNode,
              selectedUnit: _selectedUnit,
              onUnitChanged: (unit) {
                setState(() => _selectedUnit = unit);
                _scheduleAutoSave();
              },
              onDecrement: _decrementQuantity,
              onIncrement: _incrementQuantity,
              onSave: _save,
            ),

            // ── Delete ────────────────────────────────────────────────
            IconButton(
              icon: const Icon(Icons.delete_outline),
              iconSize: 20,
              color: colorScheme.onSurfaceVariant,
              onPressed: _delete,
              tooltip: 'Supprimer',
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityControls extends StatelessWidget {
  const _QuantityControls({
    required this.quantityController,
    required this.quantityFocusNode,
    required this.selectedUnit,
    required this.onUnitChanged,
    required this.onDecrement,
    required this.onIncrement,
    required this.onSave,
  });

  final TextEditingController quantityController;
  final FocusNode quantityFocusNode;
  final ShoppingUnit selectedUnit;
  final ValueChanged<ShoppingUnit> onUnitChanged;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Decrement
        IconButton(
          icon: const Icon(Icons.remove),
          iconSize: 18,
          onPressed: onDecrement,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),

        // Quantity text field
        SizedBox(
          width: 48,
          child: TextField(
            controller: quantityController,
            focusNode: quantityFocusNode,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            ),
            style: Theme.of(context).textTheme.bodyMedium,
            onSubmitted: (_) => onSave(),
            onEditingComplete: onSave,
            onChanged: (_) => onSave(),
          ),
        ),

        // Increment
        IconButton(
          icon: const Icon(Icons.add),
          iconSize: 18,
          onPressed: onIncrement,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),

        // Unit selector
        DropdownButton<ShoppingUnit>(
          value: selectedUnit,
          underline: const SizedBox.shrink(),
          isDense: true,
          items: ShoppingUnit.values
              .map(
                (u) => DropdownMenuItem(
                  value: u,
                  child: Text(
                    u.label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
              .toList(),
          onChanged: (unit) {
            if (unit != null) onUnitChanged(unit);
          },
        ),
      ],
    );
  }
}
