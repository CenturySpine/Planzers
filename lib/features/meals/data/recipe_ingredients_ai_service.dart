import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:planerz/core/intl/app_language.dart';
import 'package:planerz/features/ingredients/data/ingredient_catalog_item.dart';
import 'package:planerz/features/ingredients/data/ingredient_catalog_repository.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';

/// What the user wants the AI to produce.
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

/// POC: generates a recipe's ingredient list (and optionally cooking
/// instructions) from a name and a number of servings, using the Firebase
/// AI Logic SDK.
///
/// Implementation note — chained approach:
///   1. First call uses [Tool.googleSearch] grounding with a free-form
///      prompt, so the model can ground its answer on real recipes from
///      the web. No structured output is requested at this stage because
///      Gemini 2.5 cannot combine grounding with `responseSchema`.
///   2. Second call takes the free-form text from step 1 and converts it
///      into the strict JSON shape we need, using `responseSchema`. No
///      grounding here.
///
/// The two-step cost is justified by:
///   - Reliable structured output (no JSON parsing surprises).
///   - Optional freshness via web grounding for less common recipes.
///
/// Prerequisite (must be configured in the Firebase console):
///   - Firebase AI Logic API enabled on the target project.
///
/// Grounding with Google Search ([Tool.googleSearch]) is supported natively
/// by the Firebase AI Logic Flutter SDK (>= 2.3.0) and does not require any
/// extra activation in the Firebase console.
Future<RecipeAiResult> generateRecipeIngredients({
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

  final freeFormText = await _callGroundedRecipe(
    recipeName: trimmedName,
    servings: servings,
    mode: mode,
    language: language,
  );
  if (freeFormText.trim().isEmpty) {
    throw StateError('Réponse IA vide.');
  }

  final structured = await _callStructuredConversion(
    sourceText: freeFormText,
    mode: mode,
    language: language,
  );

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

/// First call — free-form, grounded with Google Search. Returns the raw
/// recipe text produced by the model (ingredients + optional instructions).
Future<String> _callGroundedRecipe({
  required String recipeName,
  required int servings,
  required RecipeAiMode mode,
  required AppLanguage language,
}) async {
  final model = FirebaseAI.googleAI().generativeModel(
    model: 'gemini-2.5-flash',
    generationConfig: GenerationConfig(
      thinkingConfig: ThinkingConfig.withThinkingBudget(0),
    ),
    tools: [Tool.googleSearch()],
  );

  final asksForInstructions = mode == RecipeAiMode.ingredientsAndInstructions;
  final isFr = language == AppLanguage.frFr;

  final prompt = StringBuffer();
  if (isFr) {
    prompt
      ..writeln(
        asksForInstructions
            ? 'Donne-moi la liste complète des ingrédients ainsi que les instructions '
                'de préparation pour réaliser "$recipeName" pour $servings personnes.'
            : 'Donne-moi la liste complète des ingrédients pour réaliser '
                '"$recipeName" pour $servings personnes.',
      )
      ..writeln()
      ..writeln('Pour les ingrédients :')
      ..writeln(
        '- Les quantités doivent respecter les proportions culinaires réalistes, '
        'pas une simple multiplication par le nombre de personnes.',
      )
      ..writeln(
        '- Par exemple, les aromates et épices ne se multiplient pas linéairement.',
      )
      ..writeln(
        '- Utilise des unités usuelles parmi : "g", "kg", "ml", "l", '
        '"pièce(s)", "boîte(s)", "c. à soupe", "c. à café".',
      )
      ..writeln(
        '- Choisis l\'unité la plus naturelle pour chaque ingrédient (par '
        'exemple "c. à café" pour les épices en petite quantité, "boîte(s)" '
        'pour les conserves).',
      );
    if (asksForInstructions) {
      prompt
        ..writeln()
        ..writeln('Pour les instructions :')
        ..writeln(
          '- Présente les étapes de préparation numérotées (1., 2., 3., ...), '
          'une étape par ligne.',
        )
        ..writeln('- Sois clair et concis, en français.');
    }
    prompt
      ..writeln()
      ..writeln(
        'Tu peux t\'appuyer sur des recettes du web pour t\'assurer des bonnes '
        'proportions${asksForInstructions ? ' et des bonnes étapes' : ''}.',
      );
  } else {
    prompt
      ..writeln(
        asksForInstructions
            ? 'Give me the complete ingredient list and the preparation instructions '
                'to make "$recipeName" for $servings servings.'
            : 'Give me the complete ingredient list to make '
                '"$recipeName" for $servings servings.',
      )
      ..writeln()
      ..writeln('For the ingredients:')
      ..writeln(
        '- Quantities must follow realistic culinary proportions, '
        'not a simple multiplication by the number of servings.',
      )
      ..writeln(
        '- For example, aromatics and spices do not scale linearly.',
      )
      ..writeln(
        '- Use common units among: "g", "kg", "ml", "l", '
        '"piece(s)", "can(s)", "tablespoon", "teaspoon".',
      )
      ..writeln(
        '- Choose the most natural unit for each ingredient (e.g. "teaspoon" '
        'for small amounts of spices, "can(s)" for canned goods).',
      );
    if (asksForInstructions) {
      prompt
        ..writeln()
        ..writeln('For the instructions:')
        ..writeln(
          '- Present the preparation steps numbered (1., 2., 3., ...), '
          'one step per line.',
        )
        ..writeln('- Be clear and concise, in English.');
    }
    prompt
      ..writeln()
      ..writeln(
        'You may use web recipes to ensure accurate proportions'
        '${asksForInstructions ? ' and steps' : ''}.',
      );
  }

  final response = await model.generateContent([
    Content.text(prompt.toString()),
  ]);
  return response.text ?? '';
}

/// Second call — strict JSON conversion of [sourceText] into the schema we
/// expect. No grounding here (incompatible with `responseSchema` on Gemini
/// 2.5).
Future<Map<String, dynamic>> _callStructuredConversion({
  required String sourceText,
  required RecipeAiMode mode,
  required AppLanguage language,
}) async {
  final asksForInstructions = mode == RecipeAiMode.ingredientsAndInstructions;
  final isFr = language == AppLanguage.frFr;

  final unitEnumValues = isFr
      ? const ['g', 'kg', 'ml', 'l', 'pièce(s)', 'boîte(s)', 'c. à soupe', 'c. à café']
      : const ['g', 'kg', 'ml', 'l', 'piece(s)', 'can(s)', 'tablespoon', 'teaspoon'];

  final properties = <String, Schema>{
    'recipeName': Schema.string(),
    'servings': Schema.integer(),
    'ingredients': Schema.array(
      items: Schema.object(
        properties: {
          'name': Schema.string(),
          'quantity': Schema.number(),
          'unit': Schema.enumString(enumValues: unitEnumValues),
        },
      ),
    ),
  };
  if (asksForInstructions) {
    properties['instructions'] = Schema.string();
  }

  final model = FirebaseAI.googleAI().generativeModel(
    model: 'gemini-2.5-flash',
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json',
      responseSchema: Schema.object(properties: properties),
      thinkingConfig: ThinkingConfig.withThinkingBudget(0),
    ),
  );

  final prompt = StringBuffer();
  if (isFr) {
    prompt
      ..writeln(
        'Voici une recette rédigée en texte libre. Convertis-la fidèlement '
        'en JSON structuré selon le schéma fourni.',
      )
      ..writeln()
      ..writeln('Contraintes :')
      ..writeln(
        '- N\'invente pas et ne modifie pas les quantités : transcris '
        'fidèlement le texte source.',
      )
      ..writeln(
        '- Pour chaque ingrédient, l\'unité doit être STRICTEMENT une de : '
        '"g", "kg", "ml", "l", "pièce(s)", "boîte(s)", "c. à soupe", "c. à café".',
      );
    if (asksForInstructions) {
      prompt.writeln(
        '- Pour les instructions, conserve les étapes numérotées telles quelles, '
        'une étape par ligne.',
      );
    }
  } else {
    prompt
      ..writeln(
        'Here is a recipe written as free text. Convert it faithfully '
        'into structured JSON according to the provided schema.',
      )
      ..writeln()
      ..writeln('Constraints:')
      ..writeln(
        '- Do not invent or modify quantities: transcribe the source text faithfully.',
      )
      ..writeln(
        '- For each ingredient, the unit must be STRICTLY one of: '
        '"g", "kg", "ml", "l", "piece(s)", "can(s)", "tablespoon", "teaspoon".',
      );
    if (asksForInstructions) {
      prompt.writeln(
        '- For the instructions, keep the numbered steps as-is, '
        'one step per line.',
      );
    }
  }
  prompt
    ..writeln()
    ..writeln(isFr ? 'Texte source :' : 'Source text:')
    ..writeln('"""')
    ..writeln(sourceText)
    ..writeln('"""');

  final response = await model.generateContent([
    Content.text(prompt.toString()),
  ]);
  final rawText = response.text;
  if (rawText == null || rawText.trim().isEmpty) {
    throw StateError('Réponse IA invalide (conversion JSON vide).');
  }
  final decoded = jsonDecode(rawText);
  if (decoded is! Map) {
    throw StateError('Réponse IA invalide (format inattendu).');
  }
  return Map<String, dynamic>.from(decoded);
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
