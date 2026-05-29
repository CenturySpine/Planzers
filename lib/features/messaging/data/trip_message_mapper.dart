import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/data/trip_message_kind.dart';
import 'package:planerz/features/messaging/data/trip_message_reaction.dart';

Map<String, List<String>> _mapReactions(List<TripMessageReaction> reactions) {
  final result = <String, List<String>>{};
  for (final r in reactions) {
    final emoji = r.emoji.trim();
    if (emoji.isEmpty) continue;
    result.putIfAbsent(emoji, () => []).add(r.userId);
  }
  return result;
}

/// Converts a [TripMessage] and its reactions into a [Message] understood by flutter_chat_core.
Map<String, dynamic> _baseMetadata(TripMessage m) => {
      'threadType': m.threadType.firestoreValue,
      'visibilityType': m.visibilityType.firestoreValue,
      'kind': m.kind.firestoreValue,
    };

Message mapTripMessage(
  TripMessage m,
  List<TripMessageReaction> reactions,
) {
  final reactionsMap = reactions.isEmpty ? null : _mapReactions(reactions);
  if (m.kind == TripMessageKind.image) {
    final source = (m.imageUrl ?? '').trim();
    if (source.isEmpty) {
      return Message.unsupported(
        id: m.id,
        authorId: m.authorId,
        createdAt: m.createdAt,
        metadata: _baseMetadata(m),
      );
    }
    final caption = m.text.trim();
    return ImageMessage(
      id: m.id,
      authorId: m.authorId,
      source: source,
      text: caption.isEmpty ? null : caption,
      width: m.imageWidth,
      height: m.imageHeight,
      createdAt: m.createdAt,
      updatedAt: m.updatedAt,
      reactions: reactionsMap,
      replyToMessageId: m.replyToMessageId,
      metadata: _baseMetadata(m),
    );
  }

  return Message.text(
    id: m.id,
    authorId: m.authorId,
    text: m.text,
    createdAt: m.createdAt,
    updatedAt: m.updatedAt,
    editedAt: m.wasEdited ? m.updatedAt : null,
    reactions: reactionsMap,
    replyToMessageId: m.replyToMessageId,
    metadata: _baseMetadata(m),
  );
}
