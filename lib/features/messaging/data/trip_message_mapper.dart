import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
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
Message mapTripMessage(
  TripMessage m,
  List<TripMessageReaction> reactions,
) {
  return Message.text(
    id: m.id,
    authorId: m.authorId,
    text: m.text,
    createdAt: m.createdAt,
    updatedAt: m.updatedAt,
    editedAt: m.wasEdited ? m.updatedAt : null,
    reactions: reactions.isEmpty ? null : _mapReactions(reactions),
    metadata: {
      'threadType': m.threadType.firestoreValue,
      'visibilityType': m.visibilityType.firestoreValue,
    },
  );
}
