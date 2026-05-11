import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';

class TripMessage {
  TripMessage({
    required this.id,
    required this.text,
    required this.authorId,
    required this.createdAt,
    required this.threadType,
    required this.visibilityType,
    this.threadObjectType,
    this.threadObjectId,
    this.updatedAt,
  });

  final String id;
  final String text;
  final String authorId;
  final DateTime createdAt;
  final TripMessageThreadType threadType;
  final String? threadObjectType;
  final String? threadObjectId;
  final TripMessageVisibilityType visibilityType;

  /// Server time of last edit; null if never edited after send.
  final DateTime? updatedAt;

  bool get wasEdited => updatedAt != null;

  factory TripMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
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
    final threadType = TripMessageThreadType.fromFirestore(data['threadType']);
    final visibilityType =
        TripMessageVisibilityType.fromFirestore(data['visibilityType']);
    final threadObjectType = (data['threadObjectType'] as String?)?.trim();
    final threadObjectId = (data['threadObjectId'] as String?)?.trim();
    return TripMessage(
      id: doc.id,
      text: (data['text'] as String?)?.trim() ?? '',
      authorId: (data['authorId'] as String?)?.trim() ?? '',
      createdAt: createdAt,
      threadType: threadType,
      threadObjectType: (threadObjectType?.isEmpty ?? true)
          ? null
          : threadObjectType,
      threadObjectId:
          (threadObjectId?.isEmpty ?? true) ? null : threadObjectId,
      visibilityType: visibilityType,
      updatedAt: updatedAt,
    );
  }
}
