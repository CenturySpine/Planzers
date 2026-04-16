class IngredientCatalogItem {
  const IngredientCatalogItem({
    required this.id,
    required this.label,
    required this.aliases,
    required this.category,
    required this.subcategory,
    required this.defaultUnit,
    required this.type,
  });

  final String id;
  final String label;
  final List<String> aliases;
  final String category;
  final String subcategory;
  final String defaultUnit;
  final String type;

  factory IngredientCatalogItem.fromJson(Map<String, dynamic> json) {
    return IngredientCatalogItem(
      id: (json['id'] as String? ?? '').trim(),
      label: (json['label'] as String? ?? '').trim(),
      aliases: (json['aliases'] as List<dynamic>? ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      category: (json['category'] as String? ?? '').trim(),
      subcategory: (json['subcategory'] as String? ?? '').trim(),
      defaultUnit: (json['defaultUnit'] as String? ?? '').trim(),
      type: (json['type'] as String? ?? '').trim(),
    );
  }
}
