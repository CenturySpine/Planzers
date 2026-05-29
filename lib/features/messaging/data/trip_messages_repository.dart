import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/data/trip_message_kind.dart';
import 'package:planerz/features/messaging/data/trip_message_reaction.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';
import 'package:planerz/features/trips/data/trip.dart';

final tripMessagesRepositoryProvider = Provider<TripMessagesRepository>((ref) {
  final target = ref.watch(firebaseTargetProvider);
  final configuredBucket = switch (target) {
    FirebaseTarget.preview => 'planerz-preview.firebasestorage.app',
    FirebaseTarget.prod => 'planerz.firebasestorage.app',
  };
  final rawBucket = (Firebase.app().options.storageBucket ?? '').trim();
  final effectiveBucket = rawBucket.isEmpty ? configuredBucket : rawBucket;
  final bucketUri =
      effectiveBucket.startsWith('gs://') ? effectiveBucket : 'gs://$effectiveBucket';
  return TripMessagesRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    storage: FirebaseStorage.instanceFor(bucket: bucketUri),
  );
});

final tripMessagesStreamProvider =
    StreamProvider.autoDispose.family<List<TripMessage>, String>((ref, tripId) {
  return ref
      .watch(tripMessagesRepositoryProvider)
      .watchMessages(tripId, scope: const TripMessageThreadScope.main());
});

final tripMessagesScopedStreamProvider = StreamProvider.autoDispose
    .family<List<TripMessage>, TripMessageThreadRequest>((ref, args) {
  return ref
      .watch(tripMessagesRepositoryProvider)
      .watchMessages(args.tripId, scope: args.scope);
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
  return ref.watch(tripMessagesRepositoryProvider).watchRecentChatData(
        tripId,
        pageSize: 50,
        scope: const TripMessageThreadScope.main(),
      );
});

final tripChatDataScopedStreamProvider = StreamProvider.autoDispose
    .family<TripChatData, TripMessageThreadRequest>((ref, args) {
  return ref.watch(tripMessagesRepositoryProvider).watchRecentChatData(
        args.tripId,
        pageSize: 50,
        scope: args.scope,
      );
});

class TripMessageThreadRequest {
  const TripMessageThreadRequest({
    required this.tripId,
    required this.scope,
  });

  final String tripId;
  final TripMessageThreadScope scope;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TripMessageThreadRequest) return false;
    return other.tripId == tripId &&
        other.scope.threadType == scope.threadType &&
        other.scope.threadObjectType == scope.threadObjectType &&
        other.scope.threadObjectId == scope.threadObjectId &&
        other.scope.visibilityType == scope.visibilityType;
  }

  @override
  int get hashCode => Object.hash(
        tripId,
        scope.threadType,
        scope.threadObjectType,
        scope.threadObjectId,
        scope.visibilityType,
      );
}

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
    required this.storage,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseStorage storage;

  static const int maxTextLength = 4000;
  static const int maxImageBytes = 10 * 1024 * 1024;
  static const String _messagesChannelKey = 'messages';

  CollectionReference<Map<String, dynamic>> _messagesCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('messages');
  }

  CollectionReference<Map<String, dynamic>> _messageReactionsCol({
    required String tripId,
    required String messageId,
  }) {
    return _messagesCol(tripId).doc(messageId).collection('reactions');
  }

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

  Stream<List<TripMessage>> watchMessages(
    String tripId, {
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
  }) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(const <TripMessage>[]);
    }
    return _messagesQueryForScope(cleanId, scope: scope)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(TripMessage.fromDoc).where((message) {
              return _matchesScope(message: message, scope: scope);
            }).toList(growable: false));
  }

  Stream<DateTime?> watchMyLastReadAt(
    String tripId, {
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
  }) {
    final cleanTripId = tripId.trim();
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (cleanTripId.isEmpty || uid.isEmpty) {
      return Stream.value(null);
    }
    return _myReadStateDoc(cleanTripId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      final channels = data['channels'];
      final raw = channels is Map<String, dynamic>
          ? channels[_channelKeyForScope(scope)]
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
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }
    await _myReadStateDoc(cleanTripId).set(
      {
        'channels': {
          _channelKeyForScope(scope): Timestamp.fromDate(readUpTo.toUtc()),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> sendMessage({
    required String tripId,
    required String text,
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
    String? replyToMessageId,
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

    if (scope.isAdmin) {
      await _assertIsTripAdmin(cleanTripId, user.uid);
    }

    final payload = <String, dynamic>{
      'text': trimmed,
      'authorId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (!scope.isMain) {
      payload['threadType'] = scope.threadType.firestoreValue;
      payload['visibilityType'] = scope.visibilityType.firestoreValue;
      if (scope.isObject) {
        payload['threadObjectType'] = (scope.threadObjectType ?? '').trim();
        payload['threadObjectId'] = (scope.threadObjectId ?? '').trim();
      }
    }
    final cleanReplyId = replyToMessageId?.trim();
    if (cleanReplyId != null && cleanReplyId.isNotEmpty) {
      payload['replyToMessageId'] = cleanReplyId;
    }
    await _messagesCol(cleanTripId).add(payload);
  }

  /// Pre-allocates a Firestore message document id for optimistic UI.
  String newImageMessageId(String tripId) =>
      _messagesCol(tripId.trim()).doc().id;

  Future<(double, double)?> decodeImageDimensions(Uint8List bytes) =>
      _decodeImageDimensions(bytes);

  Future<void> sendImageMessage({
    required String tripId,
    required String messageId,
    required Uint8List bytes,
    required String fileExt,
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
    String? replyToMessageId,
    String? caption,
    void Function(double progress)? onUploadProgress,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }
    if (bytes.isEmpty) {
      throw StateError('Image invalide');
    }
    if (bytes.length > maxImageBytes) {
      throw StateError('Image trop volumineuse');
    }

    final trimmedCaption = (caption ?? '').trim();
    if (trimmedCaption.length > maxTextLength) {
      throw StateError('Message trop long');
    }

    if (scope.isAdmin) {
      await _assertIsTripAdmin(cleanTripId, user.uid);
    }

    final cleanMessageId = messageId.trim();
    if (cleanMessageId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    final dimensions = await _decodeImageDimensions(bytes);
    final safeExt = fileExt.trim().toLowerCase().replaceAll('.', '');
    final ext = safeExt.isEmpty ? 'jpg' : safeExt;
    final messageRef = _messagesCol(cleanTripId).doc(cleanMessageId);
    final objectPath = 'trips/$cleanTripId/messages/$cleanMessageId.$ext';
    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };

    final objectRef = storage.ref(objectPath);
    final uploadTask = objectRef.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    if (onUploadProgress != null) {
      uploadTask.snapshotEvents.listen((event) {
        final total = event.totalBytes;
        if (total > 0) {
          onUploadProgress(event.bytesTransferred / total);
        }
      });
    }
    await uploadTask;
    final downloadUrl = await objectRef.getDownloadURL();

    final payload = <String, dynamic>{
      'type': TripMessageKind.image.firestoreValue,
      'imageUrl': downloadUrl,
      'imageStoragePath': objectPath,
      'authorId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (dimensions != null) {
      payload['imageWidth'] = dimensions.$1;
      payload['imageHeight'] = dimensions.$2;
    }
    if (trimmedCaption.isNotEmpty) {
      payload['text'] = trimmedCaption;
    }
    if (!scope.isMain) {
      payload['threadType'] = scope.threadType.firestoreValue;
      payload['visibilityType'] = scope.visibilityType.firestoreValue;
      if (scope.isObject) {
        payload['threadObjectType'] = (scope.threadObjectType ?? '').trim();
        payload['threadObjectId'] = (scope.threadObjectId ?? '').trim();
      }
    }
    final cleanReplyId = replyToMessageId?.trim();
    if (cleanReplyId != null && cleanReplyId.isNotEmpty) {
      payload['replyToMessageId'] = cleanReplyId;
    }

    try {
      await messageRef.set(payload);
    } catch (e) {
      try {
        await objectRef.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> updateMessage({
    required String tripId,
    required String messageId,
    required String text,
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
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

    if (scope.isAdmin) {
      await _assertIsTripAdmin(cleanTripId, user.uid);
    }

    final message = await _loadScopedMessage(
      tripId: cleanTripId,
      messageId: cleanMessageId,
      scope: scope,
    );
    if (message.isImage) {
      throw StateError('Message non modifiable');
    }
    await _messagesCol(cleanTripId).doc(message.id).update({
      'text': trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMessage({
    required String tripId,
    required String messageId,
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
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
    if (scope.isAdmin) {
      await _assertIsTripAdmin(cleanTripId, user.uid);
    }
    final message = await _loadScopedMessage(
      tripId: cleanTripId,
      messageId: cleanMessageId,
      scope: scope,
    );
    await _messagesCol(cleanTripId).doc(message.id).delete();
    final storagePath = message.imageStoragePath?.trim() ?? '';
    if (storagePath.isNotEmpty) {
      try {
        await storage.ref(storagePath).delete();
      } catch (_) {}
    }
  }

  Stream<Map<String, List<TripMessageReaction>>> watchReactionsByMessage(
    String tripId, {
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
  }) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(const <String, List<TripMessageReaction>>{});
    }
    return _messagesQueryForScope(cleanId, scope: scope).snapshots().map((snap) {
      final result = <String, List<TripMessageReaction>>{};
      for (final messageDoc in snap.docs) {
        final message = TripMessage.fromDoc(messageDoc);
        if (!_matchesScope(message: message, scope: scope)) continue;
        result[messageDoc.id] = _parseReactionsByUser(messageDoc.data());
      }
      return result;
    });
  }

  Stream<TripChatData> watchRecentChatData(
    String tripId, {
    required int pageSize,
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
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
    return _messagesQueryForScope(cleanId, scope: scope)
        .orderBy('createdAt', descending: true)
        .limit(_queryPageSizeForRequestedPage(pageSize))
        .snapshots()
        .map((snap) {
      return _chatDataFromDocs(
        docsDescByCreatedAt: snap.docs,
        pageSize: pageSize,
        scope: scope,
      );
    });
  }

  Future<TripChatPage> fetchOlderChatPage({
    required String tripId,
    required int pageSize,
    required QueryDocumentSnapshot<Map<String, dynamic>> startAfterDoc,
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
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

    final snap = await _messagesQueryForScope(cleanId, scope: scope)
        .orderBy('createdAt', descending: true)
        .startAfterDocument(startAfterDoc)
        .limit(_queryPageSizeForRequestedPage(pageSize))
        .get();
    final pageData = _chatDataFromDocs(
      docsDescByCreatedAt: snap.docs,
      pageSize: pageSize,
      scope: scope,
    );
    return TripChatPage(
      data: pageData,
      nextCursor: pageData.oldestLoadedDoc,
      hasMore: pageData.hasPotentialOlder,
    );
  }

  Future<void> setMyReaction({
    required String tripId,
    required String messageId,
    required String emoji,
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
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
    if (scope.isAdmin) {
      await _assertIsTripAdmin(cleanTripId, user.uid);
    }
    await _loadScopedMessage(
      tripId: cleanTripId,
      messageId: cleanMessageId,
      scope: scope,
    );

    final uid = user.uid.trim();
    await _messagesCol(cleanTripId).doc(cleanMessageId).set(
      {
        'reactionsByUser': {uid: cleanEmoji},
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await _messageReactionsCol(tripId: cleanTripId, messageId: cleanMessageId)
        .doc(uid)
        .set(
      {
        'emoji': cleanEmoji,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> removeMyReaction({
    required String tripId,
    required String messageId,
    TripMessageThreadScope scope = const TripMessageThreadScope.main(),
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
    if (scope.isAdmin) {
      await _assertIsTripAdmin(cleanTripId, user.uid);
    }
    await _loadScopedMessage(
      tripId: cleanTripId,
      messageId: cleanMessageId,
      scope: scope,
    );

    final uid = user.uid.trim();
    await _messagesCol(cleanTripId).doc(cleanMessageId).set(
      {
        'reactionsByUser': {uid: FieldValue.delete()},
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await _messageReactionsCol(tripId: cleanTripId, messageId: cleanMessageId)
        .doc(uid)
        .delete();
  }

  TripChatData _chatDataFromDocs({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docsDescByCreatedAt,
    required int pageSize,
    required TripMessageThreadScope scope,
  }) {
    final filteredDesc = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in docsDescByCreatedAt) {
      final message = TripMessage.fromDoc(doc);
      if (!_matchesScope(message: message, scope: scope)) continue;
      filteredDesc.add(doc);
      if (filteredDesc.length >= pageSize) break;
    }

    final docsAsc = filteredDesc.reversed.toList(growable: false);
    final messages = <TripMessage>[];
    final reactionsByMessage = <String, List<TripMessageReaction>>{};
    for (final doc in docsAsc) {
      messages.add(TripMessage.fromDoc(doc));
      reactionsByMessage[doc.id] = _parseReactionsByUser(doc.data());
    }

    return TripChatData(
      messages: messages,
      reactionsByMessage: reactionsByMessage,
      oldestLoadedDoc: filteredDesc.isEmpty ? null : filteredDesc.last,
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

  Future<TripMessage> _loadScopedMessage({
    required String tripId,
    required String messageId,
    required TripMessageThreadScope scope,
  }) async {
    final doc = await _messagesCol(tripId).doc(messageId).get();
    if (!doc.exists) {
      throw StateError('Message introuvable');
    }
    final message = TripMessage.fromDoc(doc);
    if (!_matchesScope(message: message, scope: scope)) {
      throw StateError('Message hors thread');
    }
    return message;
  }

  bool _matchesScope({
    required TripMessage message,
    required TripMessageThreadScope scope,
  }) {
    return scope.matchesMessageFields(
      messageThreadType: message.threadType,
      messageThreadObjectType: message.threadObjectType,
      messageThreadObjectId: message.threadObjectId,
    );
  }

  Query<Map<String, dynamic>> _messagesQueryForScope(
    String tripId, {
    required TripMessageThreadScope scope,
  }) {
    // Keep query index-free (orderBy only), then filter by scope in-memory.
    // This avoids requiring composite indexes for admin/object threads.
    return _messagesCol(tripId);
  }

  int _queryPageSizeForRequestedPage(int requestedPageSize) {
    final buffered = requestedPageSize * 3;
    return buffered < requestedPageSize ? requestedPageSize : buffered;
  }

  Future<void> _assertIsTripAdmin(String tripId, String userId) async {
    final cleanTripId = tripId.trim();
    final cleanUserId = userId.trim();
    if (cleanTripId.isEmpty || cleanUserId.isEmpty) {
      throw StateError('Parametres invalides');
    }
    final doc = await firestore.collection('trips').doc(cleanTripId).get();
    if (!doc.exists) {
      throw StateError('Voyage introuvable');
    }
    final trip = Trip.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
    if (!trip.memberHasAdminRole(cleanUserId)) {
      throw StateError('Acces reserve aux administrateurs');
    }
  }

  String _channelKeyForScope(TripMessageThreadScope scope) {
    if (scope.isMain) {
      return _messagesChannelKey;
    }
    return scope.channelKey;
  }

  Future<(double, double)?> _decodeImageDimensions(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width.toDouble();
      final height = image.height.toDouble();
      image.dispose();
      if (width <= 0 || height <= 0) return null;
      return (width, height);
    } catch (_) {
      return null;
    }
  }
}
