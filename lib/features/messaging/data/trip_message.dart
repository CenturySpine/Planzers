import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planerz/features/messaging/data/trip_message_kind.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';

class TripMessage {
  TripMessage({
    required this.id,
    required this.text,
    required this.authorId,
    required this.createdAt,
    required this.threadType,
    required this.visibilityType,
    required this.kind,
    this.threadObjectType,
    this.threadObjectId,
    this.updatedAt,
    this.replyToMessageId,
    this.imageUrl,
    this.imageStoragePath,
    this.imageWidth,
    this.imageHeight,
  });

  final String id;
  final String text;
  final String authorId;
  final TripMessageKind kind;
  final String? imageUrl;
  final String? imageStoragePath;
  final double? imageWidth;
  final double? imageHeight;
  final DateTime createdAt;
  final TripMessageThreadType threadType;
  final String? threadObjectType;
  final String? threadObjectId;
  final TripMessageVisibilityType visibilityType;

  /// Server time of last edit; null if never edited after send.
  final DateTime? updatedAt;

  /// ID of the message this is a reply to, or null if not a reply.
  final String? replyToMessageId;

  bool get wasEdited => updatedAt != null;

  bool get isImage => kind == TripMessageKind.image;

  factory TripMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final imageUrl = (data['imageUrl'] as String?)?.trim();
    final kind = TripMessageKindFirestore.fromFirestore(
      data['type'],
      hasImageUrl: imageUrl != null && imageUrl.isNotEmpty,
    );
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
    final imageWidthRaw = data['imageWidth'];
    final imageHeightRaw = data['imageHeight'];
    return TripMessage(
      id: doc.id,
      text: (data['text'] as String?)?.trim() ?? '',
      authorId: (data['authorId'] as String?)?.trim() ?? '',
      kind: kind,
      imageUrl: (imageUrl?.isEmpty ?? true) ? null : imageUrl,
      imageStoragePath: () {
        final path = (data['imageStoragePath'] as String?)?.trim();
        return (path == null || path.isEmpty) ? null : path;
      }(),
      imageWidth: imageWidthRaw is num ? imageWidthRaw.toDouble() : null,
      imageHeight: imageHeightRaw is num ? imageHeightRaw.toDouble() : null,
      createdAt: createdAt,
      threadType: threadType,
      threadObjectType: (threadObjectType?.isEmpty ?? true)
          ? null
          : threadObjectType,
      threadObjectId:
          (threadObjectId?.isEmpty ?? true) ? null : threadObjectId,
      visibilityType: visibilityType,
      updatedAt: updatedAt,
      replyToMessageId: () {
        final s = (data['replyToMessageId'] as String?)?.trim();
        return (s == null || s.isEmpty) ? null : s;
      }(),
    );
  }
}
