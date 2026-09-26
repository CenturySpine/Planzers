import 'package:planerz/app/theme/app_icons.dart';
import 'package:flutter/material.dart';

/// Stable Material Symbol key stored in Firestore (`icon` field).
const String kDefaultExpenseIconKey = 'receipt_long';
const String kDefaultExpensePostIconKey = 'group';

class ExpenseIconCatalogGroup {
  const ExpenseIconCatalogGroup({required this.labelFr, required this.iconKeys});

  final String labelFr;
  final List<String> iconKeys;
}

/// Curated expense/post icons (50) grouped for the picker sheet.
const List<ExpenseIconCatalogGroup> kExpenseIconCatalog = [
  ExpenseIconCatalogGroup(
    labelFr: 'Hébergement',
    iconKeys: [
      'cabin',
      'hotel',
      'bed',
      'cottage',
      'villa',
      'house',
      'night_shelter',
      'camping',
      'holiday_village',
      'apartment',
    ],
  ),
  ExpenseIconCatalogGroup(
    labelFr: 'Repas & boissons',
    iconKeys: [
      'restaurant',
      'local_bar',
      'local_cafe',
      'bakery_dining',
      'lunch_dining',
      'liquor',
      'icecream',
      'wine_bar',
      'ramen_dining',
      'tapas',
    ],
  ),
  ExpenseIconCatalogGroup(
    labelFr: 'Transport',
    iconKeys: [
      'local_gas_station',
      'directions_car',
      'train',
      'flight',
      'local_taxi',
      'directions_boat',
      'directions_bus',
      'pedal_bike',
      'local_parking',
      'ev_station',
    ],
  ),
  ExpenseIconCatalogGroup(
    labelFr: 'Activités',
    iconKeys: [
      'hiking',
      'beach_access',
      'confirmation_number',
      'festival',
      'downhill_skiing',
      'pool',
      'museum',
      'theater_comedy',
      'sports_soccer',
      'kayaking',
    ],
  ),
  ExpenseIconCatalogGroup(
    labelFr: 'Courses & divers',
    iconKeys: [
      'local_grocery_store',
      'shopping_cart',
      'shopping_bag',
      'receipt_long',
      'redeem',
      'medical_services',
      'pets',
      'celebration',
      'savings',
      'category',
    ],
  ),
];

const Map<String, IconData> _kExpenseIconByKey = {
  'cabin': PhosphorIconsRegular.houseLine,
  'hotel': PhosphorIconsRegular.bed,
  'bed': PhosphorIconsRegular.bed,
  'cottage': PhosphorIconsRegular.houseSimple,
  'villa': PhosphorIconsRegular.house,
  'house': PhosphorIconsRegular.house,
  'night_shelter': PhosphorIconsRegular.tent,
  'camping': PhosphorIconsRegular.treeEvergreen,
  'holiday_village': PhosphorIconsRegular.houseLine,
  'apartment': PhosphorIconsRegular.buildings,
  'restaurant': PhosphorIconsRegular.forkKnife,
  'local_bar': PhosphorIconsRegular.martini,
  'local_cafe': PhosphorIconsRegular.coffee,
  'bakery_dining': PhosphorIconsRegular.bread,
  'lunch_dining': PhosphorIconsRegular.hamburger,
  'liquor': PhosphorIconsRegular.beerBottle,
  'icecream': PhosphorIconsRegular.iceCream,
  'wine_bar': PhosphorIconsRegular.wine,
  'ramen_dining': PhosphorIconsRegular.bowlSteam,
  'tapas': PhosphorIconsRegular.bowlFood,
  'local_gas_station': PhosphorIconsRegular.gasPump,
  'directions_car': PhosphorIconsRegular.car,
  'train': PhosphorIconsRegular.train,
  'flight': PhosphorIconsRegular.airplane,
  'local_taxi': PhosphorIconsRegular.taxi,
  'directions_boat': PhosphorIconsRegular.boat,
  'directions_bus': PhosphorIconsRegular.bus,
  'pedal_bike': PhosphorIconsRegular.bicycle,
  'local_parking': PhosphorIconsRegular.letterCircleP,
  'ev_station': PhosphorIconsRegular.chargingStation,
  'hiking': PhosphorIconsRegular.personSimpleHike,
  'beach_access': PhosphorIconsRegular.umbrella,
  'confirmation_number': PhosphorIconsRegular.ticket,
  'festival': PhosphorIconsRegular.confetti,
  'downhill_skiing': PhosphorIconsRegular.personSimpleSki,
  'pool': PhosphorIconsRegular.swimmingPool,
  'museum': PhosphorIconsRegular.bank,
  'theater_comedy': PhosphorIconsRegular.maskHappy,
  'sports_soccer': PhosphorIconsRegular.soccerBall,
  'kayaking': PhosphorIconsRegular.lifebuoy,
  'local_grocery_store': PhosphorIconsRegular.basket,
  'shopping_cart': PhosphorIconsRegular.shoppingCartSimple,
  'shopping_bag': PhosphorIconsRegular.shoppingBag,
  'receipt_long': PhosphorIconsRegular.receipt,
  'redeem': PhosphorIconsRegular.gift,
  'medical_services': PhosphorIconsRegular.firstAidKit,
  'pets': PhosphorIconsRegular.pawPrint,
  'celebration': PhosphorIconsRegular.confetti,
  'savings': PhosphorIconsRegular.piggyBank,
  'category': PhosphorIconsRegular.shapes,
  'group': PhosphorIconsRegular.users,
};

IconData expenseIconDataForKey(String? key, {required String fallbackKey}) {
  final k = (key ?? '').trim();
  if (k.isNotEmpty) {
    final icon = _kExpenseIconByKey[k];
    if (icon != null) return icon;
  }
  return _kExpenseIconByKey[fallbackKey] ?? PhosphorIconsRegular.receipt;
}

IconData expenseIconForExpense(String? key) =>
    expenseIconDataForKey(key, fallbackKey: kDefaultExpenseIconKey);

IconData expenseIconForPost(String? key, {bool isDefault = false}) =>
    expenseIconDataForKey(
      key,
      fallbackKey: isDefault ? kDefaultExpensePostIconKey : kDefaultExpensePostIconKey,
    );

bool isKnownExpenseIconKey(String key) =>
    _kExpenseIconByKey.containsKey(key.trim());
