enum TripMessageThreadType {
  main('main'),
  admin('admin'),
  object('object');

  const TripMessageThreadType(this.firestoreValue);

  final String firestoreValue;

  static TripMessageThreadType fromFirestore(dynamic raw) {
    final cleanValue = raw is String ? raw.trim() : '';
    for (final type in TripMessageThreadType.values) {
      if (type.firestoreValue == cleanValue) {
        return type;
      }
    }
    return TripMessageThreadType.main;
  }
}

enum TripMessageVisibilityType {
  tripAll('trip_all'),
  adminsOnly('admins_only'),
  objectParticipants('object_participants');

  const TripMessageVisibilityType(this.firestoreValue);

  final String firestoreValue;

  static TripMessageVisibilityType fromFirestore(dynamic raw) {
    final cleanValue = raw is String ? raw.trim() : '';
    for (final type in TripMessageVisibilityType.values) {
      if (type.firestoreValue == cleanValue) {
        return type;
      }
    }
    return TripMessageVisibilityType.tripAll;
  }
}

class TripMessageThreadScope {
  const TripMessageThreadScope._({
    required this.threadType,
    required this.visibilityType,
    this.threadObjectType,
    this.threadObjectId,
  });

  const TripMessageThreadScope.main()
      : this._(
          threadType: TripMessageThreadType.main,
          visibilityType: TripMessageVisibilityType.tripAll,
        );

  const TripMessageThreadScope.admin()
      : this._(
          threadType: TripMessageThreadType.admin,
          visibilityType: TripMessageVisibilityType.adminsOnly,
        );

  const TripMessageThreadScope.object({
    required String objectType,
    required String objectId,
    TripMessageVisibilityType visibilityType =
        TripMessageVisibilityType.objectParticipants,
  }) : this._(
          threadType: TripMessageThreadType.object,
          threadObjectType: objectType,
          threadObjectId: objectId,
          visibilityType: visibilityType,
        );

  final TripMessageThreadType threadType;
  final String? threadObjectType;
  final String? threadObjectId;
  final TripMessageVisibilityType visibilityType;

  bool get isMain => threadType == TripMessageThreadType.main;
  bool get isAdmin => threadType == TripMessageThreadType.admin;
  bool get isObject => threadType == TripMessageThreadType.object;

  String get channelKey => switch (threadType) {
        TripMessageThreadType.main => 'messages',
        TripMessageThreadType.admin => 'messages:admin',
        TripMessageThreadType.object =>
          'messages:${(threadObjectType ?? '').trim()}:${(threadObjectId ?? '').trim()}',
      };

  bool matchesMessageFields({
    required TripMessageThreadType messageThreadType,
    required String? messageThreadObjectType,
    required String? messageThreadObjectId,
  }) {
    if (threadType != messageThreadType) {
      return false;
    }
    if (!isObject) {
      return true;
    }
    return (threadObjectType ?? '').trim() ==
            (messageThreadObjectType ?? '').trim() &&
        (threadObjectId ?? '').trim() == (messageThreadObjectId ?? '').trim();
  }
}
