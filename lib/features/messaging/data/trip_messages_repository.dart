import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/data/trip_message_reaction.dart';

final tripMessagesRepositoryProvider = Provider<TripMessagesRepository>((ref) {
  return TripMessagesRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Live messages for a trip, oldest first.
final tripMessagesStreamProvider =
    StreamProvider.autoDispose.family<List<TripMessage>, String>((ref, tripId) {
  return ref.watch(tripMessagesRepositoryProvider).watchMessages(tripId);
});

final tripMessagesLastReadAtProvider =
    StreamProvider.autoDispose.family<DateTime?, String>((ref, tripId) {
  return ref.watch(tripMessagesRepositoryProvider).watchMyLastReadAt(tripId);
});

final tripMessageReactionsStreamProvider = StreamProvider.autoDispose
    .family<Map<String, List<TripMessageReaction>>, String>((ref, tripId) {
  return ref.watch(tripMessagesRepositoryProvider).watchReactionsByMessage(tripId);
});

final tripChatDataStreamProvider =
    StreamProvider.autoDispose.family<TripChatData, String>((ref, tripId) {
  return ref
      .watch(tripMessagesRepositoryProvider)
      .watchRecentChatData(tripId, pageSize: 50);
});

class TripChatData {
  const TripChatData({
    required this.messages,
    required this.reactionsByMessage,
    this.oldestLoadedDoc,
    this.hasPotentialOlder = false,
  });

  final List<TripMessage> messages;
  final Map<String, List<TripMessageReaction>> reactionsByMessage;
  final QueryDocumentSnapshot<Map<String, dynamic>>? oldestLoadedDoc;
  final bool hasPotentialOlder;
}

class TripChatPage {
  const TripChatPage({
    required this.data,
    required this.nextCursor,
    required this.hasMore,
  });

  final TripChatData data;
  final QueryDocumentSnapshot<Map<String, dynamic>>? nextCursor;
  final bool hasMore;
}

class TripMessagesRepository {
  TripMessagesRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  static const int maxTextLength = 4000;

  CollectionReference<Map<String, dynamic>> _messagesCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('messages');
  }

  CollectionReference<Map<String, dynamic>> _messageReactionsCol({
    required String tripId,
    required String messageId,
  }) {
    return _messagesCol(tripId).doc(messageId).collection('reactions');
  }

  static const String _messagesChannelKey = 'messages';

  DocumentReference<Map<String, dynamic>> _myReadStateDoc(String tripId) {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('Utilisateur non connecte');
    }
    return firestore
        .collection('trips')
        .doc(tripId)
        .collection('notificationReads')
        .doc(uid);
  }

  Stream<List<TripMessage>> watchMessages(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(const <TripMessage>[]);
    }

    return _messagesCol(cleanId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs.map(TripMessage.fromDoc).toList(),
        );
  }

  Stream<DateTime?> watchMyLastReadAt(String tripId) {
    final cleanId = tripId.trim();
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (cleanId.isEmpty || uid.isEmpty) {
      return Stream.value(null);
    }
    return _myReadStateDoc(cleanId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      final channels = data['channels'];
      final raw = channels is Map<String, dynamic>
          ? channels[_messagesChannelKey]
          : null;
      return switch (raw) {
        Timestamp ts => ts.toDate(),
        _ => null,
      };
    });
  }

  Future<void> markMyMessagesAsReadUpTo({
    required String tripId,
    required DateTime readUpTo,
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }
    await _myReadStateDoc(cleanTripId).set({
      'channels': {
        _messagesChannelKey: Timestamp.fromDate(readUpTo.toUtc()),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> sendMessage({
    required String tripId,
    required String text,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw StateError('Message vide');
    }
    if (trimmed.length > maxTextLength) {
      throw StateError('Message trop long');
    }

    await _messagesCol(cleanTripId).add({
      'text': trimmed,
      'authorId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMessage({
    required String tripId,
    required String messageId,
    required String text,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMessageId = messageId.trim();
    if (cleanTripId.isEmpty || cleanMessageId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw StateError('Message vide');
    }
    if (trimmed.length > maxTextLength) {
      throw StateError('Message trop long');
    }

    final ref = _messagesCol(cleanTripId).doc(cleanMessageId);
    await ref.update({
      'text': trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMessage({
    required String tripId,
    required String messageId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMessageId = messageId.trim();
    if (cleanTripId.isEmpty || cleanMessageId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    await _messagesCol(cleanTripId).doc(cleanMessageId).delete();
  }

  Stream<Map<String, List<TripMessageReaction>>> watchReactionsByMessage(
    String tripId,
  ) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(const <String, List<TripMessageReaction>>{});
    }

    return _messagesCol(cleanId).snapshots().map((snap) {
      final result = <String, List<TripMessageReaction>>{};
      for (final messageDoc in snap.docs) {
        final data = messageDoc.data();
        final reactionsRaw = data['reactionsByUser'];
        if (reactionsRaw is! Map<String, dynamic> || reactionsRaw.isEmpty) {
          result[messageDoc.id] = const <TripMessageReaction>[];
          continue;
        }

        final reactions = <TripMessageReaction>[];
        reactionsRaw.forEach((uid, rawValue) {
          final cleanUid = uid.trim();
          final emoji = rawValue is String ? rawValue.trim() : '';
          if (cleanUid.isEmpty || emoji.isEmpty) return;
          reactions.add(
            TripMessageReaction(
              userId: cleanUid,
              emoji: emoji,
              createdAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          );
        });
        result[messageDoc.id] = reactions;
      }
      return result;
    });
  }

  Stream<TripChatData> watchRecentChatData(
    String tripId, {
    required int pageSize,
  }) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(
        const TripChatData(
          messages: <TripMessage>[],
          reactionsByMessage: <String, List<TripMessageReaction>>{},
        ),
      );
    }

    return _messagesCol(cleanId)
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .snapshots()
        .map((snap) => _chatDataFromDocs(
              docsDescByCreatedAt: snap.docs,
              pageSize: pageSize,
            ));
  }

  Future<TripChatPage> fetchOlderChatPage({
    required String tripId,
    required int pageSize,
    required QueryDocumentSnapshot<Map<String, dynamic>> startAfterDoc,
  }) async {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return const TripChatPage(
        data: TripChatData(
          messages: <TripMessage>[],
          reactionsByMessage: <String, List<TripMessageReaction>>{},
        ),
        nextCursor: null,
        hasMore: false,
      );
    }

    final snap = await _messagesCol(cleanId)
        .orderBy('createdAt', descending: true)
        .startAfterDocument(startAfterDoc)
        .limit(pageSize)
        .get();
    final pageData = _chatDataFromDocs(
      docsDescByCreatedAt: snap.docs,
      pageSize: pageSize,
    );
    return TripChatPage(
      data: pageData,
      nextCursor: pageData.oldestLoadedDoc,
      hasMore: pageData.hasPotentialOlder,
    );
  }

  TripChatData _chatDataFromDocs({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docsDescByCreatedAt,
    required int pageSize,
  }) {
    final docsAscByCreatedAt = docsDescByCreatedAt.reversed.toList(growable: false);
    final messages = <TripMessage>[];
    final reactionsByMessage = <String, List<TripMessageReaction>>{};

    for (final doc in docsAscByCreatedAt) {
      messages.add(TripMessage.fromDoc(doc));
      reactionsByMessage[doc.id] = _parseReactionsByUser(doc.data());
    }

    return TripChatData(
      messages: messages,
      reactionsByMessage: reactionsByMessage,
      oldestLoadedDoc:
          docsDescByCreatedAt.isEmpty ? null : docsDescByCreatedAt.last,
      hasPotentialOlder: docsDescByCreatedAt.length >= pageSize,
    );
  }

  List<TripMessageReaction> _parseReactionsByUser(Map<String, dynamic> data) {
    final reactionsRaw = data['reactionsByUser'];
    if (reactionsRaw is! Map<String, dynamic> || reactionsRaw.isEmpty) {
      return const <TripMessageReaction>[];
    }
    final reactions = <TripMessageReaction>[];
    reactionsRaw.forEach((uid, rawValue) {
      final cleanUid = uid.trim();
      final emoji = rawValue is String ? rawValue.trim() : '';
      if (cleanUid.isEmpty || emoji.isEmpty) return;
      reactions.add(
        TripMessageReaction(
          userId: cleanUid,
          emoji: emoji,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    });
    return reactions;
  }

  Future<void> setMyReaction({
    required String tripId,
    required String messageId,
    required String emoji,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMessageId = messageId.trim();
    final cleanEmoji = emoji.trim();
    if (cleanTripId.isEmpty || cleanMessageId.isEmpty || cleanEmoji.isEmpty) {
      throw StateError('Parametres invalides');
    }

    final uid = user.uid.trim();
    await _messagesCol(cleanTripId).doc(cleanMessageId).set({
      'reactionsByUser': {uid: cleanEmoji},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _messageReactionsCol(tripId: cleanTripId, messageId: cleanMessageId)
        .doc(uid)
        .set({
      'emoji': cleanEmoji,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeMyReaction({
    required String tripId,
    required String messageId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMessageId = messageId.trim();
    if (cleanTripId.isEmpty || cleanMessageId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    final uid = user.uid.trim();
    await _messagesCol(cleanTripId).doc(cleanMessageId).set({
      'reactionsByUser': {uid: FieldValue.delete()},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _messageReactionsCol(tripId: cleanTripId, messageId: cleanMessageId)
        .doc(uid)
        .delete();
  }
}
