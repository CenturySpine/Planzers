import 'package:planerz/features/trips/data/trip.dart';

/// Module shown in the trip's fifth tab, after Aperçu, Messagerie, Planning
/// and Dépenses.
enum TripModuleTab { shopping, map }

/// The fifth tab goes to the trip's main module: the shopping list, else the
/// trip map. With neither, the bar keeps four tabs.
TripModuleTab? tripModuleTabFor(Trip trip) {
  if (trip.shoppingModuleEnabled) return TripModuleTab.shopping;
  if (trip.journeyModuleEnabled) return TripModuleTab.map;
  return null;
}
