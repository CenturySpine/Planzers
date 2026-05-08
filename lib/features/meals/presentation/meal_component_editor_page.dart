import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/core/intl/app_language.dart';
import 'package:planerz/core/presentation/ai_billed_support_banner.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:planerz/features/ingredients/data/ingredient_catalog_item.dart';
import 'package:planerz/features/ingredients/presentation/ingredient_line_editor.dart';
import 'package:planerz/features/meals/data/meal_component_risks.dart';
import 'package:planerz/features/meals/data/recipe_ingredients_ai_service.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';

class MealComponentEditorPage extends StatefulWidget {
  const MealComponentEditorPage({
    super.key,
    required this.component,
    required this.catalogItems,
    required this.participantAllergenIds,
    required this.defaultServings,
    required this.canUseAi,
    required this.isApplicationOwner,
    required this.language,
    this.showLockIndicator = false,
  });

  final MealComponent component;
  final List<IngredientCatalogItem> catalogItems;
  final Set<String> participantAllergenIds;
  final int defaultServings;
  final bool canUseAi;
  final bool isApplicationOwner;
  final AppLanguage language;
  final bool showLockIndicator;

  @override
  State<MealComponentEditorPage> createState() =>
      _MealComponentEditorPageState();
}

class _MealComponentEditorPageState extends State<MealComponentEditorPage> {
  late MealComponent _component;
  late final TextEditingController _titleController;
  bool _isGenerating = false;

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

  bool _shouldKeepAiGeneratedFlag({
    required List<MealComponentIngredient> ingredients,
    required String recipeInstructions,
  }) {
    final hasIngredients = ingredients.isNotEmpty;
    final hasRecipeInstructions = recipeInstructions.trim().isNotEmpty;
    return hasIngredients || hasRecipeInstructions;
  }

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
      _component = _component.copyWith(
        ingredients: next,
      );
    });
  }

  void _deleteIngredient(int index) {
    if (index < 0 || index >= _component.ingredients.length) return;
    final next = _component.ingredients.toList(growable: true)..removeAt(index);
    setState(() {
      _component = _component.copyWith(
        ingredients: next,
        ingredientsGeneratedByAi: _component.ingredientsGeneratedByAi &&
            _shouldKeepAiGeneratedFlag(
              ingredients: next,
              recipeInstructions: _component.recipeInstructions,
            ),
      );
    });
  }

  void _clearRecipeInstructions() {
    setState(() {
      _component = _component.copyWith(
        recipeInstructions: '',
        ingredientsGeneratedByAi: _component.ingredientsGeneratedByAi &&
            _shouldKeepAiGeneratedFlag(
              ingredients: _component.ingredients,
              recipeInstructions: '',
            ),
      );
    });
  }

  Future<void> _confirmAndClearAllIngredients() async {
    if (_component.ingredients.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.mealIngredientsRemoveAllTitle),
        content: Text(l10n.mealIngredientsRemoveAllBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _component = _component.copyWith(
        ingredients: const [],
        ingredientsGeneratedByAi: _component.ingredientsGeneratedByAi &&
            _shouldKeepAiGeneratedFlag(
              ingredients: const [],
              recipeInstructions: _component.recipeInstructions,
            ),
      );
    });
  }

  Future<void> _showRecipeAiNotAccessibleDialog() async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.mealRecipeAiNotAccessibleTitle),
        content: Text(l10n.mealRecipeAiNotAccessibleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  Future<void> _onRecipeAiFabPressed() async {
    if (_isGenerating) return;
    if (!widget.isApplicationOwner) {
      await _showRecipeAiNotAccessibleDialog();
      return;
    }
    await _generateIngredientsWithAi();
  }

  Future<void> _generateIngredientsWithAi() async {
    if (_isGenerating) return;
    final messenger = ScaffoldMessenger.of(context);
    final request = await showDialog<_GenerateRecipeRequest>(
      context: context,
      builder: (dialogContext) => _GenerateRecipeDialog(
        initialRecipeName: _component.title,
        initialServings: widget.defaultServings,
        existingIngredientsCount: _component.ingredients.length,
        hasExistingRecipeInstructions:
            _component.recipeInstructions.trim().isNotEmpty,
      ),
    );
    if (request == null || !mounted) return;

    setState(() {
      _isGenerating = true;
      _component = _component.copyWith(ingredientsGeneratedByAi: true);
    });
    try {
      final result = await generateRecipeIngredients(
        recipeName: request.recipeName,
        servings: request.servings,
        catalogItems: widget.catalogItems,
        mode: request.mode,
        language: widget.language,
      );
      if (!mounted) return;
      if (result.ingredients.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.mealRecipeAiNoIngredientGenerated),
          ),
        );
        return;
      }
      final keepInstructions =
          request.mode == RecipeAiMode.ingredientsOnly;
      setState(() {
        _titleController.text = request.recipeName;
        _component = _component.copyWith(
          title: request.recipeName,
          ingredients: result.ingredients,
          recipeInstructions: keepInstructions
              ? _component.recipeInstructions
              : result.instructions,
          ingredientsGeneratedByAi: true,
        );
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
          if (widget.showLockIndicator)
            IconButton(
              tooltip: l10n.mealComponentLockedByMe,
              onPressed: null,
              icon: const Icon(Icons.lock_outline),
            ),
          IconButton(
            tooltip: l10n.commonDone,
            onPressed: () => Navigator.of(context).pop(_component),
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<MealComponentKind>(
            initialValue: _component.kind,
            decoration: InputDecoration(
              labelText: l10n.mealComponentTypeLabel,
              border: const OutlineInputBorder(),
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
            decoration: InputDecoration(
              labelText: l10n.mealComponentNameOptionalLabel,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _syncTitle(),
            onEditingComplete: _syncTitle,
          ),
          if (_component.ingredientsGeneratedByAi) ...[
            const SizedBox(height: 8),
            _AiQuantityWarningBanner(),
          ],
          const SizedBox(height: 16),
          if (_risk.containsAllergenIds.isNotEmpty ||
              _risk.mayContainAllergenIds.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in _risk.containsAllergenIds)
                  Chip(
                    label: Text(l10n.mealContainsAllergen(allergenLabelById[id] ?? id)),
                    avatar: const Icon(Icons.warning_amber_rounded, size: 16),
                  ),
                for (final id in _risk.mayContainAllergenIds)
                  Chip(
                    label: Text(
                      l10n.mealMayContainAllergen(allergenLabelById[id] ?? id),
                    ),
                    avatar: const Icon(Icons.info_outline, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  l10n.mealIngredientsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_component.ingredients.isNotEmpty)
                IconButton(
                  tooltip: l10n.mealIngredientsRemoveAllTooltip,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _confirmAndClearAllIngredients,
                ),
            ],
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
              hintText: l10n.mealIngredientHint,
              onSave: (value) async => _updateIngredient(i, value),
              onDelete: () async => _deleteIngredient(i),
            ),
          TextButton.icon(
            onPressed: _addIngredient,
            icon: const Icon(Icons.add),
            label: Text(l10n.mealAddIngredient),
          ),
          if (_component.recipeInstructions.trim().isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    l10n.mealRecipePreparationTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: l10n.mealRecipeStepsRemoveTooltip,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _clearRecipeInstructions,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _component.recipeInstructions.trim(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
          if (widget.canUseAi) const SizedBox(height: 88),
        ],
      ),
      floatingActionButton: widget.canUseAi
          ? FloatingActionButton(
              heroTag: 'generate_recipe_ingredients_with_ai',
              tooltip: l10n.mealRecipeAiGenerateLabel,
              onPressed: _isGenerating ? null : _onRecipeAiFabPressed,
              child: _isGenerating
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
            )
          : null,
    );
  }
}

class _AiQuantityWarningBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final planerzColors = context.planerzColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: planerzColors.warningContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: planerzColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.mealRecipeAiQuantityWarning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: planerzColors.warning,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GenerateRecipeRequest {
  const _GenerateRecipeRequest({
    required this.recipeName,
    required this.servings,
    required this.mode,
  });

  final String recipeName;
  final int servings;
  final RecipeAiMode mode;
}

class _GenerateRecipeDialog extends StatefulWidget {
  const _GenerateRecipeDialog({
    required this.initialRecipeName,
    required this.initialServings,
    required this.existingIngredientsCount,
    required this.hasExistingRecipeInstructions,
  });

  final String initialRecipeName;
  final int initialServings;
  final int existingIngredientsCount;
  final bool hasExistingRecipeInstructions;

  @override
  State<_GenerateRecipeDialog> createState() => _GenerateRecipeDialogState();
}

class _GenerateRecipeDialogState extends State<_GenerateRecipeDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _servingsController;
  RecipeAiMode _mode = RecipeAiMode.ingredientsOnly;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialRecipeName);
    final initialServings = widget.initialServings > 0
        ? widget.initialServings.toString()
        : '';
    _servingsController = TextEditingController(text: initialServings);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _servingsController.dispose();
    super.dispose();
  }

  int _parsedServings() {
    final parsed = int.tryParse(_servingsController.text.trim()) ?? 0;
    return parsed;
  }

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty && _parsedServings() > 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.mealRecipeAiGenerateLabel),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.mealRecipeAiRecipeNameLabel,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _servingsController,
              decoration: InputDecoration(
                labelText: l10n.mealRecipeAiServingsLabel,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.mealRecipeAiModeQuestion,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            SegmentedButton<RecipeAiMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment<RecipeAiMode>(
                  value: RecipeAiMode.ingredientsOnly,
                  label: Text(l10n.mealRecipeAiModeIngredientsOnly),
                ),
                ButtonSegment<RecipeAiMode>(
                  value: RecipeAiMode.ingredientsAndInstructions,
                  enabled: !widget.hasExistingRecipeInstructions,
                  label: Text(l10n.mealRecipeAiModeIngredientsAndInstructions),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                if (selection.isEmpty) return;
                setState(() => _mode = selection.first);
              },
            ),
            if (widget.existingIngredientsCount > 0) ...[
              const SizedBox(height: 16),
              Text(
                l10n.mealRecipeAiWillReplaceIngredients(widget.existingIngredientsCount),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const AiBilledSupportBanner(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _isValid
              ? () => Navigator.of(context).pop(
                    _GenerateRecipeRequest(
                      recipeName: _nameController.text.trim(),
                      servings: _parsedServings(),
                      mode: _mode,
                    ),
                  )
              : null,
          child: Text(l10n.mealRecipeAiGenerateAction),
        ),
      ],
    );
  }
}
