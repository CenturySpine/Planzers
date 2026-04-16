import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/ingredients/data/ingredient_catalog_item.dart';

const _catalogAssetPath = 'liste_courses_compilee.json';

final ingredientCatalogRepositoryProvider =
    Provider<IngredientCatalogRepository>((ref) {
  return const IngredientCatalogRepository();
});

final ingredientCatalogProvider = FutureProvider<List<IngredientCatalogItem>>((
  ref,
) async {
  return ref.read(ingredientCatalogRepositoryProvider).loadCatalog();
});

final ingredientAutocompleteProvider =
    Provider.family<AsyncValue<List<IngredientCatalogItem>>, String>((
  ref,
  query,
) {
  final trimmed = query.trim();
  final catalogAsync = ref.watch(ingredientCatalogProvider);
  return catalogAsync.whenData((items) {
    return IngredientCatalogRepository.search(items, trimmed);
  });
});

class IngredientCatalogRepository {
  const IngredientCatalogRepository();

  Future<List<IngredientCatalogItem>> loadCatalog() async {
    final raw = await rootBundle.loadString(_catalogAssetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final itemsRaw = decoded['items'] as List<dynamic>? ?? const [];
    return itemsRaw
        .whereType<Map>()
        .map(
          (item) => IngredientCatalogItem.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((item) => item.id.isNotEmpty && item.label.isNotEmpty)
        .toList(growable: false);
  }

  static List<IngredientCatalogItem> search(
    List<IngredientCatalogItem> items,
    String query,
  ) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return items.take(8).toList(growable: false);
    }

    final scored = <_IngredientMatch>[];
    for (final item in items) {
      final label = _normalize(item.label);
      final aliases = item.aliases.map(_normalize).toList(growable: false);
      final score = _score(
        query: normalizedQuery,
        label: label,
        aliases: aliases,
      );
      if (score > 0) {
        scored.add(_IngredientMatch(item: item, score: score));
      }
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.item.label.compareTo(b.item.label);
    });

    return scored.take(8).map((m) => m.item).toList(growable: false);
  }

  static int _score({
    required String query,
    required String label,
    required List<String> aliases,
  }) {
    if (label == query) return 500;
    if (label.startsWith(query)) return 400;
    if (aliases.any((a) => a == query)) return 300;
    if (aliases.any((a) => a.startsWith(query))) return 200;
    if (label.contains(query)) return 100;
    if (aliases.any((a) => a.contains(query))) return 50;
    return 0;
  }

  static String _normalize(String input) {
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
}

class _IngredientMatch {
  const _IngredientMatch({required this.item, required this.score});

  final IngredientCatalogItem item;
  final int score;
}
