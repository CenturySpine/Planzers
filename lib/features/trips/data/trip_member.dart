import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:planerz/features/trips/data/trip_member_stay.dart';

/// Phone number visibility for a trip member.
enum TripMemberPhoneVisibility {
  nobody('nobody'),
  owner('owner'),
  admin('admin'),
  participant('participant');

  const TripMemberPhoneVisibility(this.value);

  final String value;

  static TripMemberPhoneVisibility? fromString(String? s) {
    if (s == null) return null;
    for (final v in values) {
      if (v.value == s) return v;
    }
    return null;
  }

  String toFirestore() => value;
}

class TripMember {
  const TripMember({
    required this.id,
    required this.participantName,
    this.userId,
    this.stay,
    this.cupidonEnabled = false,
    this.cupidonUpdatedAt,
    this.phoneVisibility = TripMemberPhoneVisibility.nobody,
    this.updatedAt,
    this.useProfileName = false,
  });

  /// Firestore document ID (auto-generated, stable across claim).
  final String id;

  /// Display name set by the trip organiser. Fallback when [useProfileName] is off or profile has no name.
  final String participantName;

  /// Firebase UID, null until the participant claims this slot.
  final String? userId;

  /// When true, the resolved display name comes from the user's profile (account.name) rather than [participantName].
  final bool useProfileName;

  /// Stay bounds for this participant. Written at slot creation with trip defaults.
  final TripMemberStay? stay;

  final bool cupidonEnabled;
  final DateTime? cupidonUpdatedAt;
  final TripMemberPhoneVisibility phoneVisibility;
  final DateTime? updatedAt;

  bool get isClaimed => userId != null && userId!.trim().isNotEmpty;

  factory TripMember.fromMap(String id, Map<String, dynamic> data) {
    final rawCupidonUpdatedAt = data['cupidonUpdatedAt'];
    final rawUpdatedAt = data['updatedAt'];
    return TripMember(
      id: id,
      participantName: (data['participantName'] as String?)?.trim() ?? '',
      userId: (data['userId'] as String?)?.trim().isNotEmpty == true
          ? (data['userId'] as String).trim()
          : null,
      stay: TripMemberStay.tryFromFirestore(data),
      cupidonEnabled: data['cupidonEnabled'] == true,
      cupidonUpdatedAt: switch (rawCupidonUpdatedAt) {
        Timestamp ts => ts.toDate(),
        _ => null,
      },
      phoneVisibility:
          TripMemberPhoneVisibility.fromString(data['phoneVisibility'] as String?) ??
              TripMemberPhoneVisibility.nobody,
      updatedAt: switch (rawUpdatedAt) {
        Timestamp ts => ts.toDate(),
        _ => null,
      },
      useProfileName: data['useProfileName'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'participantName': participantName,
      if (userId != null && userId!.trim().isNotEmpty) 'userId': userId,
      if (stay != null) ...stay!.toFirestoreMap(),
      'cupidonEnabled': cupidonEnabled,
      'phoneVisibility': phoneVisibility.toFirestore(),
      if (useProfileName) 'useProfileName': true,
    };
  }

  TripMember copyWith({
    String? participantName,
    Object? userId = _sentinel,
    Object? stay = _sentinel,
    bool? cupidonEnabled,
    Object? cupidonUpdatedAt = _sentinel,
    TripMemberPhoneVisibility? phoneVisibility,
    Object? updatedAt = _sentinel,
    bool? useProfileName,
  }) {
    return TripMember(
      id: id,
      participantName: participantName ?? this.participantName,
      userId: identical(userId, _sentinel) ? this.userId : userId as String?,
      stay: identical(stay, _sentinel) ? this.stay : stay as TripMemberStay?,
      cupidonEnabled: cupidonEnabled ?? this.cupidonEnabled,
      cupidonUpdatedAt: identical(cupidonUpdatedAt, _sentinel)
          ? this.cupidonUpdatedAt
          : cupidonUpdatedAt as DateTime?,
      phoneVisibility: phoneVisibility ?? this.phoneVisibility,
      updatedAt: identical(updatedAt, _sentinel) ? this.updatedAt : updatedAt as DateTime?,
      useProfileName: useProfileName ?? this.useProfileName,
    );
  }
}

const Object _sentinel = Object();
