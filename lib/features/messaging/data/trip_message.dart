import 'package:cloud_firestore/cloud_firestore.dart';

class TripMessage {
  TripMessage({
    required this.id,
    required this.text,
    required this.authorId,
    required this.createdAt,
  });

  final String id;
  final String text;
  final String authorId;
  final DateTime createdAt;

  factory TripMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdRaw = data['createdAt'];
    final createdAt = switch (createdRaw) {
      Timestamp ts => ts.toDate(),
      _ => DateTime.fromMillisecondsSinceEpoch(0),
    };
    return TripMessage(
      id: doc.id,
      text: (data['text'] as String?)?.trim() ?? '',
      authorId: (data['authorId'] as String?)?.trim() ?? '',
      createdAt: createdAt,
    );
  }
}
