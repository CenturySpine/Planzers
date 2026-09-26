import 'package:planerz/app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/l10n/app_localizations.dart';

extension TripActivityCategoryPresentation on TripActivityCategory {
  IconData get categoryIcon => switch (this) {
        TripActivityCategory.sport => PhosphorIconsRegular.soccerBall,
        TripActivityCategory.hiking => PhosphorIconsRegular.personSimpleHike,
        TripActivityCategory.shopping => PhosphorIconsRegular.shoppingBag,
        TripActivityCategory.visit => PhosphorIconsRegular.compass,
        TripActivityCategory.restaurant => PhosphorIconsRegular.forkKnife,
        TripActivityCategory.cafe => PhosphorIconsRegular.coffee,
        TripActivityCategory.museum => PhosphorIconsRegular.bank,
        TripActivityCategory.show => PhosphorIconsRegular.maskHappy,
        TripActivityCategory.nightlife => PhosphorIconsRegular.martini,
        TripActivityCategory.karaoke => PhosphorIconsRegular.microphone,
        TripActivityCategory.games => PhosphorIconsRegular.gameController,
        TripActivityCategory.beach => PhosphorIconsFill.umbrella,
        TripActivityCategory.park => PhosphorIconsRegular.tree,
        TripActivityCategory.transport => PhosphorIconsRegular.bus,
        TripActivityCategory.accommodation => PhosphorIconsRegular.bed,
        TripActivityCategory.wellness => PhosphorIconsRegular.flowerLotus,
        TripActivityCategory.cooking => PhosphorIconsRegular.cookingPot,
        TripActivityCategory.workshop => PhosphorIconsRegular.palette,
        TripActivityCategory.market => PhosphorIconsRegular.storefront,
        TripActivityCategory.meeting => PhosphorIconsRegular.briefcase,
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
