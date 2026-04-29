import 'package:cloud_firestore/cloud_firestore.dart';

class TripAnnouncement {
  TripAnnouncement({
    required this.id,
    required this.text,
    required this.authorId,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String text;
  final String authorId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get wasEdited => updatedAt != null;

  factory TripAnnouncement.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
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
    return TripAnnouncement(
      id: doc.id,
      text: (data['text'] as String?)?.trim() ?? '',
      authorId: (data['authorId'] as String?)?.trim() ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
