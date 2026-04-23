import 'package:flutter/material.dart';
import 'package:planerz/features/ingredients/data/ingredient_catalog_item.dart';
import 'package:planerz/features/ingredients/presentation/ingredient_line_editor.dart';
import 'package:planerz/features/meals/data/meal_component_risks.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';

class MealComponentEditorPage extends StatefulWidget {
  const MealComponentEditorPage({
    super.key,
    required this.component,
    required this.catalogItems,
    required this.participantAllergenIds,
  });

  final MealComponent component;
  final List<IngredientCatalogItem> catalogItems;
  final Set<String> participantAllergenIds;

  @override
  State<MealComponentEditorPage> createState() =>
      _MealComponentEditorPageState();
}

class _MealComponentEditorPageState extends State<MealComponentEditorPage> {
  late MealComponent _component;
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _component = widget.component;
    _titleController = TextEditingController(text: widget.component.title);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  MealComponentRisk get _risk {
    return buildMealComponentRisks(
          components: [_component],
          catalogItems: widget.catalogItems,
          participantAllergenIds: widget.participantAllergenIds,
        )[_component.id] ??
        MealComponentRisk(
          componentId: _component.id,
          containsAllergenIds: const {},
          mayContainAllergenIds: const {},
        );
  }

  ShoppingUnit _unitFromRaw(String raw) => ShoppingUnit.fromFirestore(raw);

  void _syncTitle() {
    final nextTitle = _titleController.text.trim();
    if (nextTitle == _component.title) return;
    setState(() {
      _component = _component.copyWith(title: nextTitle);
    });
  }

  void _addIngredient() {
    setState(() {
      _component = _component.copyWith(
        ingredients: [
          ..._component.ingredients,
          MealComponentIngredient(
            catalogItemId: '',
            label: '',
            quantityValue: 1,
            quantityUnit: ShoppingUnit.unit.firestoreValue,
          ),
        ],
      );
    });
  }

  void _updateIngredient(int index, IngredientLineValue value) {
    if (index < 0 || index >= _component.ingredients.length) return;
    final next = _component.ingredients.toList(growable: true);
    next[index] = next[index].copyWith(
      catalogItemId: value.catalogItemId,
      label: value.label,
      quantityValue: value.quantityValue,
      quantityUnit: value.quantityUnit.firestoreValue,
    );
    setState(() {
      _component = _component.copyWith(ingredients: next);
    });
  }

  void _deleteIngredient(int index) {
    if (index < 0 || index >= _component.ingredients.length) return;
    final next = _component.ingredients.toList(growable: true)..removeAt(index);
    setState(() {
      _component = _component.copyWith(ingredients: next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final allergenLabelById = <String, String>{
      for (final item
          in widget.catalogItems.where((it) => it.type == 'allergen'))
        item.id: item.label,
    };
    final title = _component.title.trim().isEmpty
        ? _component.kind.labelFr
        : _component.title.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_component),
            child: const Text('Terminer'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<MealComponentKind>(
            initialValue: _component.kind,
            decoration: const InputDecoration(
              labelText: 'Type de composant',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final kind in MealComponentKind.values)
                DropdownMenuItem(
                  value: kind,
                  child: Text(kind.labelFr),
                ),
            ],
            onChanged: (kind) {
              if (kind == null) return;
              setState(() {
                _component = _component.copyWith(kind: kind);
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Nom du composant (optionnel)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _syncTitle(),
            onEditingComplete: _syncTitle,
          ),
          const SizedBox(height: 16),
          if (_risk.containsAllergenIds.isNotEmpty ||
              _risk.mayContainAllergenIds.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in _risk.containsAllergenIds)
                  Chip(
                    label: Text('Contient ${allergenLabelById[id] ?? id}'),
                    avatar: const Icon(Icons.warning_amber_rounded, size: 16),
                  ),
                for (final id in _risk.mayContainAllergenIds)
                  Chip(
                    label: Text('Peut contenir ${allergenLabelById[id] ?? id}'),
                    avatar: const Icon(Icons.info_outline, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Ingrédients',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _component.ingredients.length; i++)
            IngredientLineEditor(
              key: ValueKey('${_component.id}-$i'),
              catalogItemId: _component.ingredients[i].catalogItemId,
              label: _component.ingredients[i].label,
              quantityValue: _component.ingredients[i].quantityValue,
              quantityUnit:
                  _unitFromRaw(_component.ingredients[i].quantityUnit),
              hintText: 'Ingredient…',
              onSave: (value) async => _updateIngredient(i, value),
              onDelete: () async => _deleteIngredient(i),
            ),
          TextButton.icon(
            onPressed: _addIngredient,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un ingredient'),
          ),
        ],
      ),
    );
  }
}
