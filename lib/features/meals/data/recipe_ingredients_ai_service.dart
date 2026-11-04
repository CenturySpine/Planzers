import 'package:cloud_functions/cloud_functions.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/core/intl/app_language.dart';
import 'package:planerz/features/ingredients/data/ingredient_catalog_item.dart';
import 'package:planerz/features/ingredients/data/ingredient_catalog_repository.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';

/// What the user wants the AI to produce. Sent by name to the Cloud Function
/// (mirrors RECIPE_AI_MODES in functions/recipe_ai.js).
enum RecipeAiMode {
  /// Only the ingredient list (faster, useful when re-scaling an existing
  /// recipe whose instructions are still relevant).
  ingredientsOnly,

  /// Ingredients plus the cooking instructions.
  ingredientsAndInstructions,
}

/// Result of an AI recipe generation: the parsed [ingredients] ready to be
/// merged into a [MealComponent], plus the human-readable [instructions]
/// (cooking steps) returned by the model. [instructions] is empty in
/// [RecipeAiMode.ingredientsOnly] mode.
class RecipeAiResult {
  const RecipeAiResult({
    required this.ingredients,
    required this.instructions,
  });

  final List<MealComponentIngredient> ingredients;
  final String instructions;
}

/// Generates a recipe's ingredient list (and optionally cooking
/// instructions) from a name and a number of servings.
///
/// The AI calls run in the `generateRecipeWithAi` Cloud Function, which also
/// applies the AI settings of the administration and the quotas of
/// [tripId] (see functions/recipe_ai.js). This function maps the returned
/// ingredients onto the app's units and ingredient catalog.
Future<RecipeAiResult> generateRecipeIngredients({
  required String tripId,
  required String recipeName,
  required int servings,
  required List<IngredientCatalogItem> catalogItems,
  required RecipeAiMode mode,
  AppLanguage language = AppLanguage.frFr,
}) async {
  final trimmedName = recipeName.trim();
  if (trimmedName.isEmpty) {
    throw ArgumentError('recipeName must not be empty');
  }
  if (servings <= 0) {
    throw ArgumentError('servings must be strictly positive');
  }

  final callable = FirebaseFunctions.instanceFor(
    region: kFirebaseFunctionsRegion,
  ).httpsCallable(
    'generateRecipeWithAi',
    // Two AI calls, one with a web search: may take longer than the default.
    options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
  );
  final response = await callable.call<Map<String, dynamic>>(<String, dynamic>{
    'tripId': tripId,
    'recipeName': trimmedName,
    'servings': servings,
    'mode': mode.name,
    'lang': language == AppLanguage.frFr ? 'fr' : 'en',
  });
  final structured = Map<String, dynamic>.from(response.data);

  final rawIngredients = structured['ingredients'];
  final rawInstructions =
      (structured['instructions'] as Object?)?.toString().trim() ?? '';

  final ingredients = <MealComponentIngredient>[];
  if (rawIngredients is List) {
    for (final raw in rawIngredients) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final label = (map['name'] as Object?)?.toString().trim() ?? '';
      if (label.isEmpty) continue;

      final quantityRaw = map['quantity'];
      final baseQuantity = switch (quantityRaw) {
        num n when n > 0 => n.toDouble(),
        _ => 1.0,
      };
      final rawUnit = (map['unit'] as Object?)?.toString();

      final parsed = _parseAiUnit(
        baseQuantity: baseQuantity,
        rawUnit: rawUnit,
        language: language,
      );

      final match = _bestCatalogMatch(
        label: label,
        catalogItems: catalogItems,
      );
      final baseLabel = match?.label ?? label;
      final finalLabel = '$baseLabel${parsed.labelSuffix}';

      ingredients.add(
        MealComponentIngredient(
          catalogItemId: match?.id ?? '',
          label: finalLabel,
          quantityValue: parsed.quantity,
          quantityUnit: parsed.unit.firestoreValue,
        ),
      );
    }
  }

  return RecipeAiResult(
    ingredients: ingredients,
    instructions: rawInstructions,
  );
}

/// Result of mapping an AI-returned `(quantity, unit)` pair into our
/// internal model. Spoons are converted to grams using static conversions
/// (acceptable approximation for a POC). Boxes keep their quantity but
/// fold a `(boîte)` suffix into the label so the information is preserved
/// in the UI.
class _ParsedAiUnit {
  const _ParsedAiUnit({
    required this.quantity,
    required this.unit,
    required this.labelSuffix,
  });

  final double quantity;
  final ShoppingUnit unit;
  final String labelSuffix;
}

/// Static conversions (POC, intentionally simplistic):
///   1 tablespoon / c. à soupe ≈ 15 g
///   1 teaspoon  / c. à café   ≈ 5 g
///   can(s) / boîte(s)         → preserved in the label as "(can)" / "(boîte)"
_ParsedAiUnit _parseAiUnit({
  required double baseQuantity,
  required String? rawUnit,
  required AppLanguage language,
}) {
  final raw = (rawUnit ?? '').trim();
  final normalized = raw.toLowerCase();
  final isFr = language == AppLanguage.frFr;

  // Tablespoon — FR and EN patterns
  if (normalized.contains('c. à soupe') ||
      normalized.contains('cuillère à soupe') ||
      normalized.contains('cuillere a soupe') ||
      normalized.contains('c.a.s') ||
      normalized == 'tablespoon' ||
      normalized == 'tablespoons' ||
      normalized == 'tbsp') {
    return _ParsedAiUnit(
      quantity: baseQuantity * 15.0,
      unit: ShoppingUnit.grams,
      labelSuffix: '',
    );
  }
  // Teaspoon — FR and EN patterns
  if (normalized.contains('c. à café') ||
      normalized.contains('cuillère à café') ||
      normalized.contains('cuillere a cafe') ||
      normalized.contains('c.a.c') ||
      normalized == 'teaspoon' ||
      normalized == 'teaspoons' ||
      normalized == 'tsp') {
    return _ParsedAiUnit(
      quantity: baseQuantity * 5.0,
      unit: ShoppingUnit.grams,
      labelSuffix: '',
    );
  }
  // Can — FR and EN patterns
  if (normalized.contains('boîte') ||
      normalized.contains('boite') ||
      normalized.contains('can(s)') ||
      normalized == 'can' ||
      normalized == 'cans') {
    return _ParsedAiUnit(
      quantity: baseQuantity,
      unit: ShoppingUnit.unit,
      labelSuffix: isFr ? ' (boîte)' : ' (can)',
    );
  }

  return _ParsedAiUnit(
    quantity: baseQuantity,
    unit: ShoppingUnit.fromHumanLabel(raw),
    labelSuffix: '',
  );
}

/// Best-effort lookup against the local catalog. Accepts an exact label
/// match, an alias-equality match, or a label/alias starts-with match
/// (score ≥ 200 in [IngredientCatalogRepository.search]). Anything weaker
/// is treated as no match.
IngredientCatalogItem? _bestCatalogMatch({
  required String label,
  required List<IngredientCatalogItem> catalogItems,
}) {
  final candidates = IngredientCatalogRepository.search(catalogItems, label);
  if (candidates.isEmpty) return null;
  final top = candidates.first;
  if (top.type != 'food') return null;
  final normalizedQuery = _normalize(label);
  final normalizedLabel = _normalize(top.label);
  if (normalizedLabel == normalizedQuery) return top;
  if (normalizedLabel.startsWith(normalizedQuery)) return top;
  for (final alias in top.aliases) {
    final normalizedAlias = _normalize(alias);
    if (normalizedAlias == normalizedQuery) return top;
    if (normalizedAlias.startsWith(normalizedQuery)) return top;
  }
  return null;
}

String _normalize(String input) {
  final lower = input.trim().toLowerCase();
  if (lower.isEmpty) return '';
  return lower
      .replaceAll(RegExp(r'[àáâãäå]'), 'a')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôõö]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[ÿ]'), 'y')
      .replaceAll(RegExp(r'[œ]'), 'oe')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
