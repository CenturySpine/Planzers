import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/account/data/account_repository.dart';
import 'package:planzers/features/auth/data/users_repository.dart';
import 'package:planzers/features/ingredients/data/ingredient_catalog_item.dart';
import 'package:planzers/features/meals/data/trip_meal.dart';

final usersDataByIdsProvider = StreamProvider.autoDispose
    .family<Map<String, Map<String, dynamic>>, String>(
  (ref, participantIdsKey) {
    final ids = participantIdsKey
        .split('|')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    return ref.read(usersRepositoryProvider).watchUsersDataByIds(ids);
  },
);

class MealComponentRisk {
  const MealComponentRisk({
    required this.componentId,
    required this.containsAllergenIds,
    required this.mayContainAllergenIds,
  });

  final String componentId;
  final Set<String> containsAllergenIds;
  final Set<String> mayContainAllergenIds;
}

Set<String> participantAllergenIdsFromUsersData(
  Map<String, Map<String, dynamic>> usersDataById,
  Iterable<String> participantIds,
) {
  final out = <String>{};
  for (final participantId in participantIds) {
    final data = usersDataById[participantId];
    if (data == null) continue;
    out.addAll(foodAllergenCatalogIdsFromUserData(data));
  }
  return out;
}

Map<String, MealComponentRisk> buildMealComponentRisks({
  required List<MealComponent> components,
  required List<IngredientCatalogItem> catalogItems,
  required Set<String> participantAllergenIds,
}) {
  final byId = <String, IngredientCatalogItem>{
    for (final item in catalogItems) item.id: item,
  };
  final byLabel = <String, IngredientCatalogItem>{};
  for (final item in catalogItems.where((i) => i.type == 'food')) {
    final key = _normalize(item.label);
    byLabel.putIfAbsent(key, () => item);
  }

  final result = <String, MealComponentRisk>{};
  for (final component in components) {
    final contains = <String>{};
    final mayContain = <String>{};
    for (final ingredient in component.ingredients) {
      IngredientCatalogItem? catalogItem;
      if (ingredient.catalogItemId.trim().isNotEmpty) {
        catalogItem = byId[ingredient.catalogItemId.trim()];
      }
      catalogItem ??= byLabel[_normalize(ingredient.label)];
      if (catalogItem == null) continue;

      contains.addAll(
        catalogItem.allergens.where(participantAllergenIds.contains),
      );
      mayContain.addAll(
        catalogItem.mayContainAllergens.where(participantAllergenIds.contains),
      );
    }

    mayContain.removeAll(contains);
    result[component.id] = MealComponentRisk(
      componentId: component.id,
      containsAllergenIds: contains,
      mayContainAllergenIds: mayContain,
    );
  }
  return result;
}

String _normalize(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.isEmpty) return '';
  return lower
      .replaceAll(RegExp(r'[àáâãäå]'), 'a')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôõö]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[ÿ]'), 'y')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

