import 'package:flutter/material.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/l10n/app_localizations.dart';

extension TripActivityCategoryPresentation on TripActivityCategory {
  IconData get categoryIcon => switch (this) {
        TripActivityCategory.sport => Icons.sports_soccer_outlined,
        TripActivityCategory.hiking => Icons.hiking_outlined,
        TripActivityCategory.shopping => Icons.shopping_bag_outlined,
        TripActivityCategory.visit => Icons.explore_outlined,
        TripActivityCategory.restaurant => Icons.restaurant_outlined,
        TripActivityCategory.cafe => Icons.local_cafe_outlined,
        TripActivityCategory.museum => Icons.museum_outlined,
        TripActivityCategory.show => Icons.theater_comedy_outlined,
        TripActivityCategory.nightlife => Icons.nightlife,
        TripActivityCategory.karaoke => Icons.mic_outlined,
        TripActivityCategory.games => Icons.sports_esports_outlined,
        TripActivityCategory.beach => Icons.beach_access,
        TripActivityCategory.park => Icons.park_outlined,
        TripActivityCategory.transport => Icons.directions_bus_outlined,
        TripActivityCategory.accommodation => Icons.hotel_outlined,
        TripActivityCategory.wellness => Icons.spa_outlined,
        TripActivityCategory.cooking => Icons.outdoor_grill,
        TripActivityCategory.workshop => Icons.palette_outlined,
        TripActivityCategory.market => Icons.storefront_outlined,
        TripActivityCategory.meeting => Icons.business_center_outlined,
      };

  String get categoryLabelFr => switch (this) {
        TripActivityCategory.sport => 'Sport',
        TripActivityCategory.hiking => 'Randonnée',
        TripActivityCategory.shopping => 'Shopping',
        TripActivityCategory.visit => 'Visite',
        TripActivityCategory.restaurant => 'Restaurant',
        TripActivityCategory.cafe => 'Café',
        TripActivityCategory.museum => 'Musée',
        TripActivityCategory.show => 'Spectacle',
        TripActivityCategory.nightlife => 'Soirée',
        TripActivityCategory.karaoke => 'Karaoké',
        TripActivityCategory.games => 'Jeux',
        TripActivityCategory.beach => 'Plage',
        TripActivityCategory.park => 'Parc',
        TripActivityCategory.transport => 'Transport',
        TripActivityCategory.accommodation => 'Hébergement',
        TripActivityCategory.wellness => 'Bien-être',
        TripActivityCategory.cooking => 'Cuisine',
        TripActivityCategory.workshop => 'Atelier',
        TripActivityCategory.market => 'Marché',
        TripActivityCategory.meeting => 'Réunion',
      };

  String label(AppLocalizations l10n) => switch (this) {
        TripActivityCategory.sport => l10n.activityCategorySport,
        TripActivityCategory.hiking => l10n.activityCategoryHiking,
        TripActivityCategory.shopping => l10n.activityCategoryShopping,
        TripActivityCategory.visit => l10n.activityCategoryVisit,
        TripActivityCategory.restaurant => l10n.activityCategoryRestaurant,
        TripActivityCategory.cafe => l10n.activityCategoryCafe,
        TripActivityCategory.museum => l10n.activityCategoryMuseum,
        TripActivityCategory.show => l10n.activityCategoryShow,
        TripActivityCategory.nightlife => l10n.activityCategoryNightlife,
        TripActivityCategory.karaoke => l10n.activityCategoryKaraoke,
        TripActivityCategory.games => l10n.activityCategoryGames,
        TripActivityCategory.beach => l10n.activityCategoryBeach,
        TripActivityCategory.park => l10n.activityCategoryPark,
        TripActivityCategory.transport => l10n.activityCategoryTransport,
        TripActivityCategory.accommodation => l10n.activityCategoryAccommodation,
        TripActivityCategory.wellness => l10n.activityCategoryWellness,
        TripActivityCategory.cooking => l10n.activityCategoryCooking,
        TripActivityCategory.workshop => l10n.activityCategoryWorkshop,
        TripActivityCategory.market => l10n.activityCategoryMarket,
        TripActivityCategory.meeting => l10n.activityCategoryMeeting,
      };
}
