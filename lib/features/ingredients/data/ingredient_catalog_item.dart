class IngredientCatalogItem {
  const IngredientCatalogItem({
    required this.id,
    required this.label,
    required this.aliases,
    required this.category,
    required this.subcategory,
    required this.defaultUnit,
    required this.type,
    required this.allergens,
    required this.mayContainAllergens,
  });

  final String id;
  final String label;
  final List<String> aliases;
  final String category;
  final String subcategory;
  final String defaultUnit;
  final String type;
  final List<String> allergens;
  final List<String> mayContainAllergens;

  factory IngredientCatalogItem.fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(dynamic raw) {
      return (raw as List<dynamic>? ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }

    return IngredientCatalogItem(
      id: (json['id'] as String? ?? '').trim(),
      label: (json['label'] as String? ?? '').trim(),
      aliases: parseStringList(json['aliases']),
      category: (json['category'] as String? ?? '').trim(),
      subcategory: (json['subcategory'] as String? ?? '').trim(),
      defaultUnit: (json['defaultUnit'] as String? ?? '').trim(),
      type: (json['type'] as String? ?? '').trim(),
      allergens: parseStringList(json['allergens']),
      mayContainAllergens: parseStringList(json['mayContainAllergens']),
    );
  }
}
