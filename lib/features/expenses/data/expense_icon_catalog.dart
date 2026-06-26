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
  'cabin': Icons.cabin_outlined,
  'hotel': Icons.hotel_outlined,
  'bed': Icons.bed_outlined,
  'cottage': Icons.cottage_outlined,
  'villa': Icons.villa_outlined,
  'house': Icons.house_outlined,
  'night_shelter': Icons.night_shelter_outlined,
  'camping': Icons.forest_outlined,
  'holiday_village': Icons.holiday_village_outlined,
  'apartment': Icons.apartment_outlined,
  'restaurant': Icons.restaurant_outlined,
  'local_bar': Icons.local_bar_outlined,
  'local_cafe': Icons.local_cafe_outlined,
  'bakery_dining': Icons.bakery_dining_outlined,
  'lunch_dining': Icons.lunch_dining_outlined,
  'liquor': Icons.liquor_outlined,
  'icecream': Icons.icecream_outlined,
  'wine_bar': Icons.wine_bar_outlined,
  'ramen_dining': Icons.ramen_dining_outlined,
  'tapas': Icons.tapas_outlined,
  'local_gas_station': Icons.local_gas_station_outlined,
  'directions_car': Icons.directions_car_outlined,
  'train': Icons.train_outlined,
  'flight': Icons.flight_outlined,
  'local_taxi': Icons.local_taxi_outlined,
  'directions_boat': Icons.directions_boat_outlined,
  'directions_bus': Icons.directions_bus_outlined,
  'pedal_bike': Icons.pedal_bike_outlined,
  'local_parking': Icons.local_parking_outlined,
  'ev_station': Icons.ev_station_outlined,
  'hiking': Icons.hiking_outlined,
  'beach_access': Icons.beach_access_outlined,
  'confirmation_number': Icons.confirmation_number_outlined,
  'festival': Icons.festival_outlined,
  'downhill_skiing': Icons.downhill_skiing_outlined,
  'pool': Icons.pool_outlined,
  'museum': Icons.museum_outlined,
  'theater_comedy': Icons.theater_comedy_outlined,
  'sports_soccer': Icons.sports_soccer_outlined,
  'kayaking': Icons.kayaking_outlined,
  'local_grocery_store': Icons.local_grocery_store_outlined,
  'shopping_cart': Icons.shopping_cart_outlined,
  'shopping_bag': Icons.shopping_bag_outlined,
  'receipt_long': Icons.receipt_long_outlined,
  'redeem': Icons.redeem_outlined,
  'medical_services': Icons.medical_services_outlined,
  'pets': Icons.pets_outlined,
  'celebration': Icons.celebration_outlined,
  'savings': Icons.savings_outlined,
  'category': Icons.category_outlined,
  'group': Icons.group_outlined,
};

IconData expenseIconDataForKey(String? key, {required String fallbackKey}) {
  final k = (key ?? '').trim();
  if (k.isNotEmpty) {
    final icon = _kExpenseIconByKey[k];
    if (icon != null) return icon;
  }
  return _kExpenseIconByKey[fallbackKey] ?? Icons.receipt_long_outlined;
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
