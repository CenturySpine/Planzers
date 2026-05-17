class TripMember {
  const TripMember({
    required this.id,
    required this.participantName,
    this.userId,
  });

  /// Firestore document ID (auto-generated, stable across claim).
  final String id;

  /// Display name set by the trip organiser. Source of truth everywhere.
  final String participantName;

  /// Firebase UID, null until the participant claims this slot.
  final String? userId;

  bool get isClaimed => userId != null && userId!.trim().isNotEmpty;

  factory TripMember.fromMap(String id, Map<String, dynamic> data) {
    return TripMember(
      id: id,
      participantName: (data['participantName'] as String?)?.trim() ?? '',
      userId: (data['userId'] as String?)?.trim().isNotEmpty == true
          ? (data['userId'] as String).trim()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'participantName': participantName,
      if (userId != null && userId!.trim().isNotEmpty) 'userId': userId,
    };
  }

  TripMember copyWith({
    String? participantName,
    Object? userId = _sentinel,
  }) {
    return TripMember(
      id: id,
      participantName: participantName ?? this.participantName,
      userId: identical(userId, _sentinel) ? this.userId : userId as String?,
    );
  }
}

const Object _sentinel = Object();
