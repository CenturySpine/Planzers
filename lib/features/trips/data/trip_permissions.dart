enum TripPermissionRole {
  participant,
  admin,
  owner;

  static TripPermissionRole fromFirestore(dynamic raw) {
    final value = (raw is String ? raw : '').trim().toLowerCase();
    return switch (value) {
      'owner' => TripPermissionRole.owner,
      'admin' => TripPermissionRole.admin,
      _ => TripPermissionRole.participant,
    };
  }

  String toFirestore() => name;

  int get rank {
    return switch (this) {
      TripPermissionRole.participant => 0,
      TripPermissionRole.admin => 1,
      TripPermissionRole.owner => 2,
    };
  }

  bool allows(TripPermissionRole requiredRole) => rank >= requiredRole.rank;
}

enum TripGeneralPermissionAction {
  editGeneralInfo,
  manageBanner,
  shareAccess,
  deleteTrip;
}

class TripGeneralPermissions {
  const TripGeneralPermissions({
    required this.editGeneralInfoMinRole,
    required this.manageBannerMinRole,
    required this.shareAccessMinRole,
    required this.deleteTripMinRole,
  });

  final TripPermissionRole editGeneralInfoMinRole;
  final TripPermissionRole manageBannerMinRole;
  final TripPermissionRole shareAccessMinRole;
  final TripPermissionRole deleteTripMinRole;

  static const defaults = TripGeneralPermissions(
    editGeneralInfoMinRole: TripPermissionRole.admin,
    manageBannerMinRole: TripPermissionRole.admin,
    shareAccessMinRole: TripPermissionRole.participant,
    deleteTripMinRole: TripPermissionRole.owner,
  );

  factory TripGeneralPermissions.fromFirestore(dynamic raw) {
    if (raw is! Map) {
      return defaults;
    }
    return TripGeneralPermissions(
      editGeneralInfoMinRole: TripPermissionRole.fromFirestore(raw['editGeneralInfo']),
      manageBannerMinRole: TripPermissionRole.fromFirestore(raw['manageBanner']),
      shareAccessMinRole: TripPermissionRole.fromFirestore(raw['shareAccess']),
      deleteTripMinRole: TripPermissionRole.fromFirestore(raw['deleteTrip']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'editGeneralInfo': editGeneralInfoMinRole.toFirestore(),
      'manageBanner': manageBannerMinRole.toFirestore(),
      'shareAccess': shareAccessMinRole.toFirestore(),
      'deleteTrip': deleteTripMinRole.toFirestore(),
    };
  }

  TripPermissionRole minRoleFor(TripGeneralPermissionAction action) {
    return switch (action) {
      TripGeneralPermissionAction.editGeneralInfo => editGeneralInfoMinRole,
      TripGeneralPermissionAction.manageBanner => manageBannerMinRole,
      TripGeneralPermissionAction.shareAccess => shareAccessMinRole,
      TripGeneralPermissionAction.deleteTrip => deleteTripMinRole,
    };
  }
}
