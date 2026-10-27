import 'package:planerz/features/trips/data/trip_permissions.dart';

/// Kinds of trip offered when creating one. A template only presets the new
/// trip (modules, day trip, lodging, permissions); it is not stored, and
/// everything stays editable afterwards.
enum TripTemplate {
  friendsStay,
  roadTrip,
  guidedTrip,
  dayOuting;

  TripTemplateSettings get settings => switch (this) {
        TripTemplate.friendsStay => const TripTemplateSettings(
            journeyModuleEnabled: false,
            homeMealsModuleEnabled: true,
            shoppingModuleEnabled: true,
            roomsModuleEnabled: true,
            carpoolModuleEnabled: true,
            gamesModuleEnabled: true,
            isDayTrip: false,
            lodgingAllNights: true,
            permissions: TripTemplatePermissions.defaults,
          ),
        TripTemplate.roadTrip => const TripTemplateSettings(
            journeyModuleEnabled: true,
            homeMealsModuleEnabled: false,
            shoppingModuleEnabled: false,
            roomsModuleEnabled: false,
            carpoolModuleEnabled: false,
            gamesModuleEnabled: false,
            isDayTrip: false,
            lodgingAllNights: false,
            permissions: TripTemplatePermissions.defaults,
          ),
        TripTemplate.guidedTrip => const TripTemplateSettings(
            journeyModuleEnabled: true,
            homeMealsModuleEnabled: false,
            shoppingModuleEnabled: false,
            roomsModuleEnabled: true,
            carpoolModuleEnabled: false,
            gamesModuleEnabled: false,
            isDayTrip: false,
            lodgingAllNights: false,
            permissions: TripTemplatePermissions.guided,
          ),
        TripTemplate.dayOuting => const TripTemplateSettings(
            journeyModuleEnabled: false,
            homeMealsModuleEnabled: true,
            shoppingModuleEnabled: true,
            roomsModuleEnabled: false,
            carpoolModuleEnabled: true,
            gamesModuleEnabled: true,
            isDayTrip: true,
            lodgingAllNights: true,
            permissions: TripTemplatePermissions.defaults,
          ),
      };
}

/// What a [TripTemplate] presets on a new trip. Cupidon is never preset.
class TripTemplateSettings {
  const TripTemplateSettings({
    required this.journeyModuleEnabled,
    required this.homeMealsModuleEnabled,
    required this.shoppingModuleEnabled,
    required this.roomsModuleEnabled,
    required this.carpoolModuleEnabled,
    required this.gamesModuleEnabled,
    required this.isDayTrip,
    required this.lodgingAllNights,
    required this.permissions,
  });

  final bool journeyModuleEnabled;
  final bool homeMealsModuleEnabled;
  final bool shoppingModuleEnabled;
  final bool roomsModuleEnabled;
  final bool carpoolModuleEnabled;
  final bool gamesModuleEnabled;
  final bool isDayTrip;

  /// Same lodging for every night, rather than night by night.
  final bool lodgingAllNights;
  final TripTemplatePermissions permissions;
}

/// The whole permissions block of a new trip.
class TripTemplatePermissions {
  const TripTemplatePermissions({
    required this.general,
    required this.participants,
    required this.expenses,
    required this.activities,
    required this.meals,
    required this.shopping,
    required this.carpool,
    required this.rooms,
  });

  final TripGeneralPermissions general;
  final TripParticipantsPermissions participants;
  final TripExpensesPermissions expenses;
  final TripActivitiesPermissions activities;
  final TripMealsPermissions meals;
  final TripShoppingPermissions shopping;
  final TripCarpoolPermissions carpool;
  final TripRoomsPermissions rooms;

  static const defaults = TripTemplatePermissions(
    general: TripGeneralPermissions.defaults,
    participants: TripParticipantsPermissions.defaults,
    expenses: TripExpensesPermissions.defaults,
    activities: TripActivitiesPermissions.defaults,
    meals: TripMealsPermissions.defaults,
    shopping: TripShoppingPermissions.defaults,
    carpool: TripCarpoolPermissions.defaults,
    rooms: TripRoomsPermissions.defaults,
  );

  /// Organised trip: everything is up to the admins, but the expenses that
  /// travelers share among themselves and what is already the creator's.
  static const guided = TripTemplatePermissions(
    general: TripGeneralPermissions(
      editGeneralInfoMinRole: TripPermissionRole.admin,
      manageBannerMinRole: TripPermissionRole.admin,
      publishAnnouncementsMinRole: TripPermissionRole.admin,
      shareAccessMinRole: TripPermissionRole.admin,
      manageTripSettingsMinRole: TripPermissionRole.owner,
      deleteTripMinRole: TripPermissionRole.owner,
    ),
    participants: TripParticipantsPermissions(
      manageParticipantsMinRole: TripPermissionRole.owner,
      toggleAdminRoleMinRole: TripPermissionRole.owner,
      editOwnStayMinRole: TripPermissionRole.admin,
    ),
    expenses: TripExpensesPermissions.defaults,
    activities: TripActivitiesPermissions(
      suggestActivityMinRole: TripPermissionRole.admin,
      planActivityMinRole: TripPermissionRole.admin,
      editActivityMinRole: TripPermissionRole.admin,
      deleteActivityMinRole: TripPermissionRole.admin,
    ),
    meals: TripMealsPermissions(
      createMealMinRole: TripPermissionRole.admin,
      deleteMealMinRole: TripPermissionRole.admin,
      editMealMinRole: TripPermissionRole.admin,
      addContributionMinRole: TripPermissionRole.admin,
      manageRecipeMinRole: TripPermissionRole.admin,
      chooseRestaurantMinRole: TripPermissionRole.admin,
    ),
    shopping: TripShoppingPermissions.defaults,
    carpool: TripCarpoolPermissions(
      proposeCarpoolMinRole: TripPermissionRole.admin,
      editCarpoolsMinRole: TripPermissionRole.admin,
      updateShoppingMeetupPointMinRole: TripPermissionRole.admin,
    ),
    rooms: TripRoomsPermissions(
      manageRoomsMinRole: TripPermissionRole.admin,
    ),
  );

  /// Firestore `trips/{id}.permissions`.
  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'tripGeneral': general.toFirestore(),
      'participants': participants.toFirestore(),
      'expenses': expenses.toFirestore(),
      'activities': activities.toFirestore(),
      'meals': meals.toFirestore(),
      'shopping': shopping.toFirestore(),
      'carpool': carpool.toFirestore(),
      'rooms': rooms.toFirestore(),
    };
  }
}
