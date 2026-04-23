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
  manageTripSettings,
  deleteTrip;
}

class TripGeneralPermissions {
  const TripGeneralPermissions({
    required this.editGeneralInfoMinRole,
    required this.manageBannerMinRole,
    required this.shareAccessMinRole,
    required this.manageTripSettingsMinRole,
    required this.deleteTripMinRole,
  });

  final TripPermissionRole editGeneralInfoMinRole;
  final TripPermissionRole manageBannerMinRole;
  final TripPermissionRole shareAccessMinRole;
  final TripPermissionRole manageTripSettingsMinRole;
  final TripPermissionRole deleteTripMinRole;

  static const defaults = TripGeneralPermissions(
    editGeneralInfoMinRole: TripPermissionRole.admin,
    manageBannerMinRole: TripPermissionRole.admin,
    shareAccessMinRole: TripPermissionRole.participant,
    manageTripSettingsMinRole: TripPermissionRole.owner,
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
      manageTripSettingsMinRole: raw['manageTripSettings'] == null
          ? TripPermissionRole.owner
          : TripPermissionRole.fromFirestore(raw['manageTripSettings']),
      deleteTripMinRole: TripPermissionRole.fromFirestore(raw['deleteTrip']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'editGeneralInfo': editGeneralInfoMinRole.toFirestore(),
      'manageBanner': manageBannerMinRole.toFirestore(),
      'shareAccess': shareAccessMinRole.toFirestore(),
      'manageTripSettings': manageTripSettingsMinRole.toFirestore(),
      'deleteTrip': deleteTripMinRole.toFirestore(),
    };
  }

  TripPermissionRole minRoleFor(TripGeneralPermissionAction action) {
    return switch (action) {
      TripGeneralPermissionAction.editGeneralInfo => editGeneralInfoMinRole,
      TripGeneralPermissionAction.manageBanner => manageBannerMinRole,
      TripGeneralPermissionAction.shareAccess => shareAccessMinRole,
      TripGeneralPermissionAction.manageTripSettings => manageTripSettingsMinRole,
      TripGeneralPermissionAction.deleteTrip => deleteTripMinRole,
    };
  }
}

enum TripParticipantsPermissionAction {
  createParticipant,
  editPlaceholderParticipant,
  deletePlaceholderParticipant,
  deleteRegisteredParticipant,
  toggleAdminRole;
}

class TripParticipantsPermissions {
  const TripParticipantsPermissions({
    required this.createParticipantMinRole,
    required this.editPlaceholderParticipantMinRole,
    required this.deletePlaceholderParticipantMinRole,
    required this.deleteRegisteredParticipantMinRole,
    required this.toggleAdminRoleMinRole,
  });

  final TripPermissionRole createParticipantMinRole;
  final TripPermissionRole editPlaceholderParticipantMinRole;
  final TripPermissionRole deletePlaceholderParticipantMinRole;
  final TripPermissionRole deleteRegisteredParticipantMinRole;
  final TripPermissionRole toggleAdminRoleMinRole;

  static const defaults = TripParticipantsPermissions(
    createParticipantMinRole: TripPermissionRole.owner,
    editPlaceholderParticipantMinRole: TripPermissionRole.owner,
    deletePlaceholderParticipantMinRole: TripPermissionRole.owner,
    deleteRegisteredParticipantMinRole: TripPermissionRole.owner,
    toggleAdminRoleMinRole: TripPermissionRole.owner,
  );

  factory TripParticipantsPermissions.fromFirestore(dynamic raw) {
    if (raw is! Map) {
      return defaults;
    }
    return TripParticipantsPermissions(
      createParticipantMinRole: raw['createParticipant'] == null
          ? TripPermissionRole.owner
          : TripPermissionRole.fromFirestore(raw['createParticipant']),
      editPlaceholderParticipantMinRole: raw['editPlaceholderParticipant'] == null
          ? TripPermissionRole.owner
          : TripPermissionRole.fromFirestore(raw['editPlaceholderParticipant']),
      deletePlaceholderParticipantMinRole: raw['deletePlaceholderParticipant'] == null
          ? TripPermissionRole.owner
          : TripPermissionRole.fromFirestore(raw['deletePlaceholderParticipant']),
      deleteRegisteredParticipantMinRole:
          raw['deleteRegisteredParticipant'] == null
          ? TripPermissionRole.owner
          : TripPermissionRole.fromFirestore(raw['deleteRegisteredParticipant']),
      toggleAdminRoleMinRole: raw['toggleAdminRole'] == null
          ? TripPermissionRole.owner
          : TripPermissionRole.fromFirestore(raw['toggleAdminRole']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'createParticipant': createParticipantMinRole.toFirestore(),
      'editPlaceholderParticipant': editPlaceholderParticipantMinRole.toFirestore(),
      'deletePlaceholderParticipant': deletePlaceholderParticipantMinRole.toFirestore(),
      'deleteRegisteredParticipant': deleteRegisteredParticipantMinRole.toFirestore(),
      'toggleAdminRole': toggleAdminRoleMinRole.toFirestore(),
    };
  }
}

enum TripExpensesPermissionAction {
  createExpensePost,
  editExpensePost,
  deleteExpensePost,
}

/// Permissions for expense **posts** (`expenseGroups`): create / edit / delete.
///
/// Firestore: `trips/{id}.permissions.expenses`.
class TripExpensesPermissions {
  const TripExpensesPermissions({
    required this.createExpensePostMinRole,
    required this.editExpensePostMinRole,
    required this.deleteExpensePostMinRole,
  });

  final TripPermissionRole createExpensePostMinRole;
  final TripPermissionRole editExpensePostMinRole;
  final TripPermissionRole deleteExpensePostMinRole;

  /// Everyone can manage posts by default; visibility still restricts who sees a post.
  static const defaults = TripExpensesPermissions(
    createExpensePostMinRole: TripPermissionRole.participant,
    editExpensePostMinRole: TripPermissionRole.participant,
    deleteExpensePostMinRole: TripPermissionRole.participant,
  );

  factory TripExpensesPermissions.fromFirestore(dynamic raw) {
    if (raw is! Map) {
      return defaults;
    }
    return TripExpensesPermissions(
      createExpensePostMinRole: raw['createExpensePost'] == null
          ? TripPermissionRole.participant
          : TripPermissionRole.fromFirestore(raw['createExpensePost']),
      editExpensePostMinRole: raw['editExpensePost'] == null
          ? TripPermissionRole.participant
          : TripPermissionRole.fromFirestore(raw['editExpensePost']),
      deleteExpensePostMinRole: raw['deleteExpensePost'] == null
          ? TripPermissionRole.participant
          : TripPermissionRole.fromFirestore(raw['deleteExpensePost']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'createExpensePost': createExpensePostMinRole.toFirestore(),
      'editExpensePost': editExpensePostMinRole.toFirestore(),
      'deleteExpensePost': deleteExpensePostMinRole.toFirestore(),
    };
  }

  TripPermissionRole minRoleFor(TripExpensesPermissionAction action) {
    return switch (action) {
      TripExpensesPermissionAction.createExpensePost => createExpensePostMinRole,
      TripExpensesPermissionAction.editExpensePost => editExpensePostMinRole,
      TripExpensesPermissionAction.deleteExpensePost => deleteExpensePostMinRole,
    };
  }
}
