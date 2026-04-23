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
