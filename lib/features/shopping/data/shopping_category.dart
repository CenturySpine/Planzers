import 'package:planerz/l10n/app_localizations.dart';

/// Ids of the grocery categories a shopping item can be sorted into, in
/// display order. The AI consolidation uses the same ones: keep in sync with
/// `functions/shopping_categories.js` and `liste_categories_courses.json`.
const List<String> kShoppingCategoryIds = [
  'animaux',
  'bebe',
  'boissons',
  'boucherie',
  'boulangerie-viennoiserie',
  'conserves',
  'cremerie',
  'divers',
  'entretien',
  'epicerie-salee',
  'epicerie-sucree',
  'fruits-et-legumes',
  'hygiene',
  'maison',
  'petit-dejeuner-et-gouter',
  'poissonnerie',
  'rayon-frais',
  'surgeles',
];

/// [raw] when it is a known category id, null otherwise.
String? knownShoppingCategoryId(String? raw) {
  final id = raw?.trim() ?? '';
  return kShoppingCategoryIds.contains(id) ? id : null;
}

/// Display name of a known category id; [categoryId] itself otherwise.
String shoppingCategoryLabel(AppLocalizations l10n, String categoryId) {
  return switch (categoryId) {
    'animaux' => l10n.shoppingCategoryAnimaux,
    'bebe' => l10n.shoppingCategoryBebe,
    'boissons' => l10n.shoppingCategoryBoissons,
    'boucherie' => l10n.shoppingCategoryBoucherie,
    'boulangerie-viennoiserie' => l10n.shoppingCategoryBoulangerieViennoiserie,
    'conserves' => l10n.shoppingCategoryConserves,
    'cremerie' => l10n.shoppingCategoryCremerie,
    'divers' => l10n.shoppingCategoryDivers,
    'entretien' => l10n.shoppingCategoryEntretien,
    'epicerie-salee' => l10n.shoppingCategoryEpicerieSalee,
    'epicerie-sucree' => l10n.shoppingCategoryEpicerieSucree,
    'fruits-et-legumes' => l10n.shoppingCategoryFruitsEtLegumes,
    'hygiene' => l10n.shoppingCategoryHygiene,
    'maison' => l10n.shoppingCategoryMaison,
    'petit-dejeuner-et-gouter' => l10n.shoppingCategoryPetitDejeunerEtGouter,
    'poissonnerie' => l10n.shoppingCategoryPoissonnerie,
    'rayon-frais' => l10n.shoppingCategoryRayonFrais,
    'surgeles' => l10n.shoppingCategorySurgeles,
    _ => categoryId,
  };
}
