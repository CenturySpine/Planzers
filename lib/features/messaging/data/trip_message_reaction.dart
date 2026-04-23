import 'package:cloud_firestore/cloud_firestore.dart';

class TripMessageReaction {
  TripMessageReaction({
    required this.userId,
    required this.emoji,
    required this.createdAt,
    this.updatedAt,
  });

  final String userId;
  final String emoji;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory TripMessageReaction.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdRaw = data['createdAt'];
    final createdAt = switch (createdRaw) {
      Timestamp ts => ts.toDate(),
      _ => DateTime.fromMillisecondsSinceEpoch(0),
    };
    final updatedRaw = data['updatedAt'];
    final updatedAt = switch (updatedRaw) {
      Timestamp ts => ts.toDate(),
      _ => null,
    };

    return TripMessageReaction(
      userId: doc.id.trim(),
      emoji: (data['emoji'] as String?)?.trim() ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
