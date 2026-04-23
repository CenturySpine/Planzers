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
