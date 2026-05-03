import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';

TripPermissionRole resolveTripPermissionRole({
  required Trip trip,
  required String? userId,
}) {
  final cleanUid = userId?.trim() ?? '';
  if (cleanUid.isEmpty) return TripPermissionRole.participant;
  if (cleanUid == trip.ownerId.trim()) return TripPermissionRole.owner;
  if (trip.adminMemberIds.contains(cleanUid)) return TripPermissionRole.admin;
  return TripPermissionRole.participant;
}

bool isTripRoleAllowed({
  required TripPermissionRole currentRole,
  required TripPermissionRole minRole,
}) {
  return currentRole.allows(minRole);
}

bool canCreateExpensePostForTrip({
  required Trip trip,
  required String? userId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.expensesPermissions.createExpensePostMinRole,
  );
}

bool _expensePostVisibleToMember({
  required List<String> visibleToMemberIds,
  required String userId,
}) {
  final uid = userId.trim();
  if (uid.isEmpty) return false;
  if (visibleToMemberIds.isEmpty) return false;
  final allowed = visibleToMemberIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  return allowed.contains(uid);
}

/// Edit post metadata / visibility: role + must already see this post.
bool canEditExpensePostForTrip({
  required Trip trip,
  required String? userId,
  required List<String> expensePostVisibleToMemberIds,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty ||
      !_expensePostVisibleToMember(
        visibleToMemberIds: expensePostVisibleToMemberIds,
        userId: uid,
      )) {
    return false;
  }
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.expensesPermissions.editExpensePostMinRole,
  );
}

/// Delete a post: role + must see this post (hidden posts stay unreachable).
bool canDeleteExpensePostForTrip({
  required Trip trip,
  required String? userId,
  required List<String> expensePostVisibleToMemberIds,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty ||
      !_expensePostVisibleToMember(
        visibleToMemberIds: expensePostVisibleToMemberIds,
        userId: uid,
      )) {
    return false;
  }
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.expensesPermissions.deleteExpensePostMinRole,
  );
}

/// Create an expense line in a post: role + must see this post.
bool canCreateExpenseForTrip({
  required Trip trip,
  required String? userId,
  required List<String> expensePostVisibleToMemberIds,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty ||
      !_expensePostVisibleToMember(
        visibleToMemberIds: expensePostVisibleToMemberIds,
        userId: uid,
      )) {
    return false;
  }
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.expensesPermissions.createExpenseMinRole,
  );
}

/// Edit an expense line: role + must see this post.
bool canEditExpenseForTrip({
  required Trip trip,
  required String? userId,
  required List<String> expensePostVisibleToMemberIds,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty ||
      !_expensePostVisibleToMember(
        visibleToMemberIds: expensePostVisibleToMemberIds,
        userId: uid,
      )) {
    return false;
  }
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.expensesPermissions.editExpenseMinRole,
  );
}

/// Delete an expense line: role + must see this post.
bool canDeleteExpenseForTrip({
  required Trip trip,
  required String? userId,
  required List<String> expensePostVisibleToMemberIds,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty ||
      !_expensePostVisibleToMember(
        visibleToMemberIds: expensePostVisibleToMemberIds,
        userId: uid,
      )) {
    return false;
  }
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.expensesPermissions.deleteExpenseMinRole,
  );
}

bool canVoteForActivity({
  required Trip trip,
  required String? userId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  return trip.memberIds.contains(uid);
}

bool canSuggestActivityForTrip({
  required Trip trip,
  required String? userId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.activitiesPermissions.suggestActivityMinRole,
  );
}

bool canPlanActivityForTrip({
  required Trip trip,
  required String? userId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.activitiesPermissions.planActivityMinRole,
  );
}

bool canEditActivityForTrip({
  required Trip trip,
  required String? userId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.activitiesPermissions.editActivityMinRole,
  );
}

bool canDeleteActivityForTrip({
  required Trip trip,
  required String? userId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.activitiesPermissions.deleteActivityMinRole,
  );
}

bool canCreateMealForTrip({
  required Trip trip,
  required String? userId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.mealsPermissions.createMealMinRole,
  );
}

bool canDeleteMealForTrip({
  required Trip trip,
  required String? userId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.mealsPermissions.deleteMealMinRole,
  );
}

bool canEditMealForTrip({
  required Trip trip,
  required String? userId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.mealsPermissions.editMealMinRole,
  );
}

bool canAddMealContributionForTrip({
  required Trip trip,
  required String? userId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.mealsPermissions.addContributionMinRole,
  );
}

bool canManageMealRecipeForTrip({
  required Trip trip,
  required String? userId,
}) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return false;
  if (!trip.memberIds.contains(uid)) return false;
  final role = resolveTripPermissionRole(trip: trip, userId: uid);
  return isTripRoleAllowed(
    currentRole: role,
    minRole: trip.mealsPermissions.manageRecipeMinRole,
  );
}
