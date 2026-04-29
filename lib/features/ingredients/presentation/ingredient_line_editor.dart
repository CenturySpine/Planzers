import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:planerz/features/ingredients/data/ingredient_catalog_item.dart';
import 'package:planerz/features/ingredients/data/ingredient_catalog_repository.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';

class IngredientLineValue {
  const IngredientLineValue({
    required this.catalogItemId,
    required this.label,
    required this.quantityValue,
    required this.quantityUnit,
  });

  final String catalogItemId;
  final String label;
  final double quantityValue;
  final ShoppingUnit quantityUnit;
}

class IngredientLineEditor extends ConsumerStatefulWidget {
  const IngredientLineEditor({
    super.key,
    required this.label,
    required this.quantityValue,
    required this.quantityUnit,
    this.catalogItemId = '',
    required this.onSave,
    required this.onDelete,
    this.prefixWidgets = const [],
    this.hintText = 'Article…',
    this.autoFocusLabel = false,
    this.onAutoFocusHandled,
    this.labelStyle,
    this.isDuplicateLabel,
    this.duplicateWarningText = 'Cet élément existe déjà dans la liste.',
  });

  final String catalogItemId;
  final String label;
  final double quantityValue;
  final ShoppingUnit quantityUnit;
  final Future<void> Function(IngredientLineValue value) onSave;
  final Future<void> Function() onDelete;
  final List<Widget> prefixWidgets;
  final String hintText;
  final bool autoFocusLabel;
  final VoidCallback? onAutoFocusHandled;
  final TextStyle? labelStyle;
  final bool Function(String value)? isDuplicateLabel;
  final String duplicateWarningText;

  @override
  ConsumerState<IngredientLineEditor> createState() =>
      _IngredientLineEditorState();
}

class _IngredientLineEditorState extends ConsumerState<IngredientLineEditor> {
  static const Duration _autoSaveDebounce = Duration(milliseconds: 600);

  late TextEditingController _labelController;
  late TextEditingController _quantityController;
  late ShoppingUnit _selectedUnit;
  _MeasurementKind _measurementKind = _MeasurementKind.solid;
  String _catalogItemId = '';
  String? _acceptedSuggestionLabel;
  bool _isSaving = false;
  Timer? _autoSaveTimer;
  final FocusNode _labelFocusNode = FocusNode();
  final FocusNode _quantityFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _catalogItemId = widget.catalogItemId.trim();
    _labelController = TextEditingController(text: widget.label);
    _quantityController = TextEditingController(
      text: _formatQuantity(widget.quantityValue),
    );
    _selectedUnit = widget.quantityUnit;
    _measurementKind = _measurementKindFromUnit(_selectedUnit);
    _labelController.addListener(_onLabelChanged);
    if (widget.autoFocusLabel && widget.label.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _labelFocusNode.requestFocus();
        widget.onAutoFocusHandled?.call();
      });
    }
  }

  @override
  void didUpdateWidget(IngredientLineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_labelFocusNode.hasFocus && oldWidget.label != widget.label) {
      _labelController.text = widget.label;
    }
    if (!_quantityFocusNode.hasFocus) {
      if (oldWidget.quantityValue != widget.quantityValue) {
        _quantityController.text = _formatQuantity(widget.quantityValue);
      }
      if (oldWidget.quantityUnit != widget.quantityUnit) {
        _selectedUnit = widget.quantityUnit;
      }
    }
    if (oldWidget.catalogItemId != widget.catalogItemId) {
      _catalogItemId = widget.catalogItemId.trim();
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _labelController.removeListener(_onLabelChanged);
    _labelController.dispose();
    _quantityController.dispose();
    _labelFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  void _onLabelChanged() {
    final accepted = _acceptedSuggestionLabel;
    if (accepted != null && _normalize(_labelController.text) != accepted) {
      _acceptedSuggestionLabel = null;
      _catalogItemId = '';
    }
    if (mounted) setState(() {});
  }

  String _normalize(String input) => input.trim().toLowerCase();

  String _formatQuantity(double value) {
    if (value == value.truncateToDouble()) return value.toInt().toString();
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
    final hasChanged = label != widget.label.trim() ||
        safeQuantity != widget.quantityValue ||
        _selectedUnit != widget.quantityUnit ||
        _catalogItemId != widget.catalogItemId.trim();
    if (!hasChanged) return;

    setState(() => _isSaving = true);
    try {
      await widget.onSave(
        IngredientLineValue(
          catalogItemId: _catalogItemId,
          label: label,
          quantityValue: safeQuantity,
          quantityUnit: _selectedUnit,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
        return ShoppingUnit.milliliters;
      case 'l':
      case 'litre':
      case 'litres':
        return ShoppingUnit.liters;
      default:
        return ShoppingUnit.unit;
    }
  }

  _MeasurementKind _measurementKindFromUnit(ShoppingUnit unit) {
    return switch (unit) {
      ShoppingUnit.milliliters ||
      ShoppingUnit.liters =>
        _MeasurementKind.liquid,
      _ => _MeasurementKind.solid,
    };
  }

  Future<void> _applySuggestion(IngredientCatalogItem suggestion) async {
    _autoSaveTimer?.cancel();
    _acceptedSuggestionLabel = _normalize(suggestion.label);
    _catalogItemId = suggestion.id;
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
    _labelFocusNode.unfocus();
    await _save();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _measurementKind = _measurementKindFromUnit(_selectedUnit);
    final colorScheme = Theme.of(context).colorScheme;
    final query = _labelController.text.trim();
    final suggestionsAsync = ref.watch(ingredientAutocompleteProvider(query));
    final showSuggestions = _labelFocusNode.hasFocus &&
        query.isNotEmpty &&
        _normalize(query) != _acceptedSuggestionLabel;
    final isDuplicate =
        widget.isDuplicateLabel?.call(_labelController.text) ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          Row(
            children: [
              ...widget.prefixWidgets,
              Expanded(
                child: TextField(
                  controller: _labelController,
                  focusNode: _labelFocusNode,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.done,
                  minLines: 1,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    suffixIconConstraints:
                        const BoxConstraints(minHeight: 18, minWidth: 18),
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
                  style: widget.labelStyle,
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
                  });
                  _scheduleAutoSave();
                },
                onDecrement: _decrementQuantity,
                onIncrement: _incrementQuantity,
                onSave: _save,
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                tooltip: l10n.commonMoreActions,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                icon: Icon(Icons.more_vert,
                    size: 20, color: colorScheme.onSurfaceVariant),
                onSelected: (value) {
                  if (value == 'delete') {
                    unawaited(widget.onDelete());
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete,
                            size: 20, color: colorScheme.error),
                        const SizedBox(width: 10),
                        Text(l10n.commonDelete,
                            style: TextStyle(color: colorScheme.error)),
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
                            onPointerDown: (_) =>
                                unawaited(_applySuggestion(suggestion)),
                            child: ListTile(
                              dense: true,
                              visualDensity: const VisualDensity(
                                  horizontal: 0, vertical: -3),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 0),
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
              error: (_, __) => const SizedBox.shrink(),
            ),
          if (isDuplicate)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.duplicateWarningText,
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
          ShoppingUnit.liters
        ],
      _MeasurementKind.solid => const [
          ShoppingUnit.unit,
          ShoppingUnit.grams,
          ShoppingUnit.kilograms
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
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
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
                  child: Text(u.label,
                      style: Theme.of(context).textTheme.bodySmall),
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

enum _MeasurementKind { solid, liquid }
