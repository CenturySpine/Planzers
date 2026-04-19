import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/ingredients/data/ingredient_catalog_item.dart';
import 'package:planzers/features/ingredients/data/ingredient_catalog_repository.dart';
import 'package:planzers/features/shopping/data/shopping_item.dart';
import 'package:planzers/features/shopping/data/shopping_repository.dart';
import 'package:planzers/features/trips/presentation/name_list_search.dart';
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

class _ShoppingList extends ConsumerStatefulWidget {
  const _ShoppingList({
    required this.tripId,
    required this.items,
  });

  final String tripId;
  final List<ShoppingItem> items;

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
    final checkedCount = widget.items.where((item) => item.checked).length;
    if (checkedCount == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer les éléments cochés ?'),
          content: Text(
            '$checkedCount élément(s) sera(ont) supprimé(s) définitivement. Cette opération est irréversible.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Supprimer'),
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
          content: Text('$deletedCount élément(s) supprimé(s).'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final checkedCount = widget.items.where((item) => item.checked).length;
    final searchQuery = _searchController.text;
    final searchFilteredItems = widget.items
        .where((item) => displayNameMatchesNameSearch(item.label, searchQuery))
        .toList(growable: false);
    final filteredItems = searchFilteredItems
        .where((item) => _matchesFilter(item, _activeFilter))
        .toList(growable: false);

    final normalizedLabelCounts = <String, int>{};
    for (final item in widget.items) {
      final normalized = _normalizeItemLabel(item.label);
      if (normalized.isEmpty) continue;
      normalizedLabelCounts[normalized] =
          (normalizedLabelCounts[normalized] ?? 0) + 1;
    }

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
                children: [
                  Expanded(
                    child: SegmentedButton<_ShoppingFilter>(
                      segments: const [
                        ButtonSegment<_ShoppingFilter>(
                          value: _ShoppingFilter.all,
                          label: Text('Tout'),
                        ),
                        ButtonSegment<_ShoppingFilter>(
                          value: _ShoppingFilter.todo,
                          label: Text('À acheter'),
                        ),
                        ButtonSegment<_ShoppingFilter>(
                          value: _ShoppingFilter.done,
                          label: Text('Déjà cochés'),
                        ),
                      ],
                      selected: {_activeFilter},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        setState(() => _activeFilter = selection.first);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: checkedCount == 0
                        ? null
                        : () => _confirmAndDeleteChecked(context),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Supprimer'),
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
                  : filteredItems.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              kNameListSearchEmptyMessage,
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
                            color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
                          ),
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            return _ShoppingItemRow(
                              key: ValueKey(item.id),
                              tripId: widget.tripId,
                              item: item,
                              normalizedLabelCounts: normalizedLabelCounts,
                              autoFocusLabel: item.id == _pendingAutofocusItemId,
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
          child: FloatingActionButton(
            heroTag: 'add_shopping_item',
            onPressed: _addItem,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

String _normalizeItemLabel(String raw) {
  return raw.trim().toLowerCase();
}

bool _matchesFilter(ShoppingItem item, _ShoppingFilter filter) {
  return switch (filter) {
    _ShoppingFilter.all => true,
    _ShoppingFilter.todo => !item.checked,
    _ShoppingFilter.done => item.checked,
  };
}

enum _ShoppingFilter {
  all,
  todo,
  done,
}

class _ShoppingItemRow extends ConsumerStatefulWidget {
  const _ShoppingItemRow({
    super.key,
    required this.tripId,
    required this.item,
    required this.normalizedLabelCounts,
    this.autoFocusLabel = false,
    this.onAutoFocusHandled,
  });

  final String tripId;
  final ShoppingItem item;
  final Map<String, int> normalizedLabelCounts;
  final bool autoFocusLabel;
  final VoidCallback? onAutoFocusHandled;

  @override
  ConsumerState<_ShoppingItemRow> createState() => _ShoppingItemRowState();
}

class _ShoppingItemRowState extends ConsumerState<_ShoppingItemRow> {
  static const Duration _autoSaveDebounce = Duration(milliseconds: 600);
  late TextEditingController _labelController;
  late TextEditingController _quantityController;
  late ShoppingUnit _selectedUnit;
  _MeasurementKind _measurementKind = _MeasurementKind.solid;
  String? _acceptedSuggestionLabel;
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
    _measurementKind = _measurementKindFromUnit(_selectedUnit);
    _labelController.addListener(_onLabelChanged);
    _labelFocusNode.addListener(_onFocusChanged);
    _quantityFocusNode.addListener(_onFocusChanged);
    if (widget.autoFocusLabel && widget.item.label.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _labelFocusNode.requestFocus();
        widget.onAutoFocusHandled?.call();
      });
    }
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
        setState(() {
          _selectedUnit = widget.item.quantityUnit;
          _measurementKind = _measurementKindFromUnit(_selectedUnit);
        });
      }
    }
    if (!oldWidget.autoFocusLabel &&
        widget.autoFocusLabel &&
        widget.item.label.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _labelFocusNode.requestFocus();
        widget.onAutoFocusHandled?.call();
      });
    }
  }

  final FocusNode _labelFocusNode = FocusNode();
  final FocusNode _quantityFocusNode = FocusNode();

  void _onLabelChanged() {
    final accepted = _acceptedSuggestionLabel;
    if (accepted != null && _normalize(_labelController.text) != accepted) {
      _acceptedSuggestionLabel = null;
    }
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  String _normalize(String input) {
    return input.trim().toLowerCase();
  }

  void _syncMeasurementKindFromUnit() {
    final kind = _measurementKindFromUnit(_selectedUnit);
    if (kind != _measurementKind) {
      _measurementKind = kind;
    }
  }

  _MeasurementKind _measurementKindFromUnit(ShoppingUnit unit) {
    return switch (unit) {
      ShoppingUnit.milliliters || ShoppingUnit.liters =>
        _MeasurementKind.liquid,
      _ => _MeasurementKind.solid,
    };
  }

  bool _isDuplicateLabel(String value) {
    final normalized = _normalizeItemLabel(value);
    if (normalized.isEmpty) return false;
    final totalCount = widget.normalizedLabelCounts[normalized] ?? 0;
    final ownMatches = _normalizeItemLabel(widget.item.label) == normalized ? 1 : 0;
    return (totalCount - ownMatches) > 0;
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _labelController.removeListener(_onLabelChanged);
    _labelFocusNode.removeListener(_onFocusChanged);
    _quantityFocusNode.removeListener(_onFocusChanged);
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

  ShoppingUnit _unitFromCatalogDefault(String rawUnit) {
    final unit = rawUnit.trim().toLowerCase();
    switch (unit) {
      case 'g':
      case 'gramme':
      case 'grammes':
        return ShoppingUnit.grams;
      case 'kg':
      case 'kilogramme':
      case 'kilogrammes':
        return ShoppingUnit.kilograms;
      case 'ml':
      case 'millilitre':
      case 'millilitres':
        return ShoppingUnit.liters;
      case 'l':
      case 'litre':
      case 'litres':
        return ShoppingUnit.liters;
      default:
        return ShoppingUnit.unit;
    }
  }

  Future<void> _applySuggestion(IngredientCatalogItem suggestion) async {
    _autoSaveTimer?.cancel();
    _acceptedSuggestionLabel = _normalize(suggestion.label);
    _labelController.value = TextEditingValue(
      text: suggestion.label,
      selection: TextSelection.collapsed(offset: suggestion.label.length),
    );
    final suggestedUnit = _unitFromCatalogDefault(suggestion.defaultUnit);
    if (suggestedUnit != _selectedUnit) {
      setState(() {
        _selectedUnit = suggestedUnit;
        _measurementKind = _measurementKindFromUnit(suggestedUnit);
      });
    }
    // Close suggestions after a successful pick.
    _labelFocusNode.unfocus();
    await _save();
    if (mounted) setState(() {});
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
    _syncMeasurementKindFromUnit();
    final query = _labelController.text.trim();
    final suggestionsAsync = ref.watch(ingredientAutocompleteProvider(query));
    final showSuggestions = _labelFocusNode.hasFocus &&
        query.isNotEmpty &&
        _normalize(query) != _acceptedSuggestionLabel;
    final isDuplicateLabel = _isDuplicateLabel(_labelController.text);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
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
                  currentUser: currentUser,
                  onTap: _toggleClaim,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _labelController,
                  focusNode: _labelFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Article…',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 6,
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minHeight: 18,
                      minWidth: 18,
                    ),
                    suffixIcon: SizedBox(
                      width: 16,
                      height: 16,
                      child: _isSaving
                          ? const Padding(
                              padding: EdgeInsets.all(2),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const SizedBox.shrink(),
                    ),
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
              _QuantityControls(
                quantityController: _quantityController,
                quantityFocusNode: _quantityFocusNode,
                selectedUnit: _selectedUnit,
                measurementKind: _measurementKind,
                onUnitChanged: (unit) {
                  setState(() {
                    _selectedUnit = unit;
                    _measurementKind = _measurementKindFromUnit(unit);
                  });
                  _scheduleAutoSave();
                },
                onDecrement: _decrementQuantity,
                onIncrement: _incrementQuantity,
                onSave: _save,
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                tooltip: 'Plus d\'actions',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                onSelected: (value) {
                  if (value == 'delete') _delete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Supprimer',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
            if (showSuggestions)
              suggestionsAsync.when(
                data: (suggestions) {
                  final filtered = suggestions
                      .where((s) => s.type == 'food')
                      .take(5)
                      .toList(growable: false);
                  if (filtered.isEmpty) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: filtered
                          .map(
                            (suggestion) => Listener(
                              onPointerDown: (_) {
                                unawaited(_applySuggestion(suggestion));
                              },
                              child: ListTile(
                                dense: true,
                                visualDensity: const VisualDensity(
                                  horizontal: 0,
                                  vertical: -3,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 0,
                                ),
                                minVerticalPadding: 0,
                                title: Text(
                                  suggestion.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {},
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (error, stackTrace) => const SizedBox.shrink(),
              ),
            if (isDuplicateLabel)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 8, bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Cet élément existe déjà dans la liste.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _QuantityControls extends StatelessWidget {
  const _QuantityControls({
    required this.quantityController,
    required this.quantityFocusNode,
    required this.selectedUnit,
    required this.measurementKind,
    required this.onUnitChanged,
    required this.onDecrement,
    required this.onIncrement,
    required this.onSave,
  });

  final TextEditingController quantityController;
  final FocusNode quantityFocusNode;
  final ShoppingUnit selectedUnit;
  final _MeasurementKind measurementKind;
  final ValueChanged<ShoppingUnit> onUnitChanged;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final unitOptions = switch (measurementKind) {
      _MeasurementKind.liquid => const [
          ShoppingUnit.milliliters,
          ShoppingUnit.liters,
        ],
      _MeasurementKind.solid => const [
          ShoppingUnit.unit,
          ShoppingUnit.grams,
          ShoppingUnit.kilograms,
        ],
    };
    final qtyBtnStyle = IconButton.styleFrom(
      padding: const EdgeInsets.all(2),
      minimumSize: const Size(24, 24),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          style: qtyBtnStyle,
          icon: const Icon(Icons.remove),
          iconSize: 16,
          onPressed: onDecrement,
        ),
        SizedBox(
          width: 36,
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
              contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 6),
            ),
            style: Theme.of(context).textTheme.bodyMedium,
            onSubmitted: (_) => onSave(),
            onEditingComplete: onSave,
            onChanged: (_) => onSave(),
          ),
        ),
        IconButton(
          style: qtyBtnStyle,
          icon: const Icon(Icons.add),
          iconSize: 16,
          onPressed: onIncrement,
        ),
        DropdownButton<ShoppingUnit>(
          value: selectedUnit,
          underline: const SizedBox.shrink(),
          isDense: true,
          padding: EdgeInsets.zero,
          alignment: AlignmentDirectional.centerStart,
          items: unitOptions
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

class _ClaimButton extends StatelessWidget {
  const _ClaimButton({
    required this.isClaimedByMe,
    required this.isClaimedByOther,
    required this.currentUser,
    required this.onTap,
  });

  final bool isClaimedByMe;
  final bool isClaimedByOther;
  final User? currentUser;
  final Future<void> Function() onTap;

  String _initialsFromUser(User? user) {
    final base = (user?.displayName ?? user?.email ?? '').trim();
    if (base.isEmpty) return '?';
    return base[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final compactStyle = IconButton.styleFrom(
      padding: const EdgeInsets.all(2),
      minimumSize: const Size(28, 28),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    if (isClaimedByMe) {
      final photoUrl = (currentUser?.photoURL ?? '').trim();
      final avatar = CircleAvatar(
        radius: 10,
        backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
        child: photoUrl.isEmpty ? Text(_initialsFromUser(currentUser)) : null,
      );
      return IconButton(
        style: compactStyle,
        tooltip: 'Retirer mon claim',
        onPressed: () => onTap(),
        icon: avatar,
      );
    }

    if (isClaimedByOther) {
      return IconButton(
        style: compactStyle,
        tooltip: 'Déjà claimé par un autre participant',
        onPressed: null,
        icon: const Icon(Icons.accessibility_new, size: 17),
      );
    }

    return IconButton(
      style: compactStyle,
      tooltip: 'Je m\'en occupe',
      onPressed: () => onTap(),
      icon: const Icon(Icons.accessibility_new_outlined, size: 17),
    );
  }
}

enum _MeasurementKind {
  solid,
  liquid,
}
