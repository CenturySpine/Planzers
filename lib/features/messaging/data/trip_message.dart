import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:planerz/features/messaging/data/trip_message_kind.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';

/// Delivery state of a message as seen by the local user.
enum TripMessageSendState {
  /// Stored on the server.
  sent,

  /// Written locally, waiting for the server (or for an image upload).
  sending,

  /// The server refused the message or the upload failed.
  failed,
}

@immutable
class TripMessage {
  const TripMessage({
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
    this.reactionsByUser = const <String, String>{},
    this.sendState = TripMessageSendState.sent,
    this.hasServerTimestamp = true,
  });

  final String id;
  final String text;
  final String authorId;
  final TripMessageKind kind;
  final String? imageUrl;
  final String? imageStoragePath;
  final double? imageWidth;
  final double? imageHeight;

  /// Server creation time. When [hasServerTimestamp] is false the server has
  /// not confirmed the message yet and this value is a local placeholder.
  final DateTime createdAt;
  final TripMessageThreadType threadType;
  final String? threadObjectType;
  final String? threadObjectId;
  final TripMessageVisibilityType visibilityType;

  /// Server time of the last write on the message (edit or reaction).
  final DateTime? updatedAt;

  /// ID of the message this is a reply to, or null if not a reply.
  final String? replyToMessageId;

  /// Emoji picked by each user (user id → emoji). One reaction per user.
  final Map<String, String> reactionsByUser;

  final TripMessageSendState sendState;

  /// False while `createdAt` is still a pending server timestamp.
  final bool hasServerTimestamp;

  bool get isImage => kind == TripMessageKind.image;

  bool get isSending => sendState == TripMessageSendState.sending;

  bool get isFailed => sendState == TripMessageSendState.failed;

  /// Text shown when the message is quoted or summarised on one line.
  /// Empty for an image without caption.
  String get previewText => text.trim();

  TripMessage copyWith({
    String? text,
    DateTime? createdAt,
    String? imageUrl,
    Map<String, String>? reactionsByUser,
    TripMessageSendState? sendState,
    bool? hasServerTimestamp,
  }) {
    return TripMessage(
      id: id,
      text: text ?? this.text,
      authorId: authorId,
      createdAt: createdAt ?? this.createdAt,
      threadType: threadType,
      visibilityType: visibilityType,
      kind: kind,
      threadObjectType: threadObjectType,
      threadObjectId: threadObjectId,
      updatedAt: updatedAt,
      replyToMessageId: replyToMessageId,
      imageUrl: imageUrl ?? this.imageUrl,
      imageStoragePath: imageStoragePath,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      reactionsByUser: reactionsByUser ?? this.reactionsByUser,
      sendState: sendState ?? this.sendState,
      hasServerTimestamp: hasServerTimestamp ?? this.hasServerTimestamp,
    );
  }

  factory TripMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final imageUrl = (data['imageUrl'] as String?)?.trim();
    final kind = TripMessageKindFirestore.fromFirestore(
      data['type'],
      hasImageUrl: imageUrl != null && imageUrl.isNotEmpty,
    );
    final createdRaw = data['createdAt'];
    final hasServerTimestamp = createdRaw is Timestamp;
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
      threadObjectType:
          (threadObjectType?.isEmpty ?? true) ? null : threadObjectType,
      threadObjectId: (threadObjectId?.isEmpty ?? true) ? null : threadObjectId,
      visibilityType: visibilityType,
      updatedAt: updatedAt,
      replyToMessageId: () {
        final s = (data['replyToMessageId'] as String?)?.trim();
        return (s == null || s.isEmpty) ? null : s;
      }(),
      reactionsByUser: _parseReactionsByUser(data['reactionsByUser']),
      sendState: hasServerTimestamp
          ? TripMessageSendState.sent
          : TripMessageSendState.sending,
      hasServerTimestamp: hasServerTimestamp,
    );
  }

  static Map<String, String> _parseReactionsByUser(Object? raw) {
    if (raw is! Map || raw.isEmpty) return const <String, String>{};
    final result = <String, String>{};
    raw.forEach((uid, value) {
      final cleanUid = uid is String ? uid.trim() : '';
      final emoji = value is String ? value.trim() : '';
      if (cleanUid.isEmpty || emoji.isEmpty) return;
      result[cleanUid] = emoji;
    });
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TripMessage &&
        other.id == id &&
        other.text == text &&
        other.authorId == authorId &&
        other.kind == kind &&
        other.imageUrl == imageUrl &&
        other.imageWidth == imageWidth &&
        other.imageHeight == imageHeight &&
        other.createdAt == createdAt &&
        other.replyToMessageId == replyToMessageId &&
        other.sendState == sendState &&
        other.hasServerTimestamp == hasServerTimestamp &&
        mapEquals(other.reactionsByUser, reactionsByUser);
  }

  @override
  int get hashCode => Object.hash(id, text, createdAt, sendState, imageUrl);
}
