import 'package:cloud_firestore/cloud_firestore.dart';

/// A billing group for trip expenses (`trips/{tripId}/participantGroups/{groupId}`).
///
/// Groups aggregate [TripMember]s into a single billing unit with weighted shares.
/// Only used in the expenses module; all other modules reference TripMember directly.
class ParticipantGroup {
  const ParticipantGroup({
    required this.id,
    required this.label,
    required this.memberIds,
    required this.parts,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// Display label for this group (e.g. "A&B", "Famille Martin").
  final String label;

  /// TripMember document IDs belonging to this group.
  final List<String> memberIds;

  /// Number of billing shares assigned to the group (> 0, may be fractional).
  final double parts;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ParticipantGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final partsRaw = data['parts'];
    final parts = switch (partsRaw) {
      num n when n > 0 => n.toDouble(),
      _ => 1.0,
    };
    final rawCreatedAt = data['createdAt'];
    final rawUpdatedAt = data['updatedAt'];
    return ParticipantGroup(
      id: doc.id,
      label: (data['label'] as String?)?.trim() ?? '',
      memberIds: ((data['memberIds'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString().trim())
          .where((id) => id.isNotEmpty)
          .toList(),
      parts: parts,
      createdAt: switch (rawCreatedAt) {
        Timestamp ts => ts.toDate(),
        _ => null,
      },
      updatedAt: switch (rawUpdatedAt) {
        Timestamp ts => ts.toDate(),
        _ => null,
      },
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'label': label.trim(),
        'memberIds': memberIds,
        'parts': parts,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toUpdateMap() => {
        'label': label.trim(),
        'memberIds': memberIds,
        'parts': parts,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  ParticipantGroup copyWith({
    String? label,
    List<String>? memberIds,
    double? parts,
  }) {
    return ParticipantGroup(
      id: id,
      label: label ?? this.label,
      memberIds: memberIds ?? this.memberIds,
      parts: parts ?? this.parts,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
