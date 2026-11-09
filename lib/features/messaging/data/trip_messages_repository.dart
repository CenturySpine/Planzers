import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/data/trip_message_kind.dart';
import 'package:planerz/features/messaging/data/trip_message_thread_scope.dart';

final tripMessagesRepositoryProvider = Provider<TripMessagesRepository>((ref) {
  final target = ref.watch(firebaseTargetProvider);
  final configuredBucket = switch (target) {
    FirebaseTarget.preview => 'planerz-preview.firebasestorage.app',
    FirebaseTarget.prod => 'planerz.firebasestorage.app',
  };
  final rawBucket = (Firebase.app().options.storageBucket ?? '').trim();
  final effectiveBucket = rawBucket.isEmpty ? configuredBucket : rawBucket;
  final bucketUri = effectiveBucket.startsWith('gs://')
      ? effectiveBucket
      : 'gs://$effectiveBucket';
  return TripMessagesRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    storage: FirebaseStorage.instanceFor(bucket: bucketUri),
  );
});

/// Most recent main-thread messages of a trip (bounded), oldest first.
///
/// Only used as a fallback to count unread messages when the server-side
/// counters are not available yet.
final tripRecentMessagesStreamProvider =
    StreamProvider.autoDispose.family<List<TripMessage>, String>((ref, tripId) {
  return ref
      .watch(tripMessagesRepositoryProvider)
      .watchLatest(
        tripId,
        scope: const TripMessageThreadScope.main(),
        limit: 50,
      )
      .map((window) => window.messages);
});

/// Identifies one conversation: a trip plus a thread inside it.
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

/// A slice of a conversation, oldest message first.
class TripChatWindow {
  const TripChatWindow({
    required this.messages,
    required this.olderCursor,
    required this.mayHaveOlder,
  });

  static const empty = TripChatWindow(
    messages: <TripMessage>[],
    olderCursor: null,
    mayHaveOlder: false,
  );

  final List<TripMessage> messages;

  /// Opaque position to pass to `fetchOlder` to continue before this slice.
  final Object? olderCursor;

  /// True when the slice was full, so older messages may exist.
  final bool mayHaveOlder;
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

  String? get currentUserId {
    final uid = auth.currentUser?.uid.trim() ?? '';
    return uid.isEmpty ? null : uid;
  }

  CollectionReference<Map<String, dynamic>> _messagesCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('messages');
  }

  /// Pre-allocates a message id so the message can be shown before it is
  /// written.
  String newMessageId(String tripId) => _messagesCol(tripId.trim()).doc().id;

  /// Live view of the [limit] most recent messages of a thread.
  Stream<TripChatWindow> watchLatest(
    String tripId, {
    required TripMessageThreadScope scope,
    required int limit,
  }) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) return Stream.value(TripChatWindow.empty);
    return _messagesQueryForScope(cleanId, scope: scope)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => _windowFromDocs(snap.docs, scope: scope, limit: limit));
  }

  /// One-shot page of messages older than [cursor].
  Future<TripChatWindow> fetchOlder(
    String tripId, {
    required TripMessageThreadScope scope,
    required Object cursor,
    required int limit,
  }) async {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty ||
        cursor is! DocumentSnapshot<Map<String, dynamic>>) {
      return TripChatWindow.empty;
    }
    final snap = await _messagesQueryForScope(cleanId, scope: scope)
        .orderBy('createdAt', descending: true)
        .startAfterDocument(cursor)
        .limit(limit)
        .get();
    return _windowFromDocs(snap.docs, scope: scope, limit: limit);
  }

  /// Reads one message of a thread, or null when it no longer exists (or
  /// belongs to another thread).
  Future<TripMessage?> fetchMessage(
    String tripId, {
    required TripMessageThreadScope scope,
    required String messageId,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanMessageId = messageId.trim();
    if (cleanTripId.isEmpty || cleanMessageId.isEmpty) return null;
    final doc = await _messagesCol(cleanTripId).doc(cleanMessageId).get();
    if (!doc.exists) return null;
    final message = TripMessage.fromDoc(doc);
    return _matchesScope(message: message, scope: scope) ? message : null;
  }

  Future<void> sendTextMessage({
    required String tripId,
    required String messageId,
    required String text,
    required TripMessageThreadScope scope,
    String? replyToMessageId,
  }) async {
    final uid = _requireUid();
    final trimmed = _validText(text);
    final payload = <String, dynamic>{
      'text': trimmed,
      'authorId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      ..._threadFields(scope),
      ..._replyField(replyToMessageId),
    };
    await _messagesCol(_validId(tripId)).doc(_validId(messageId)).set(payload);
  }

  Future<void> sendImageMessage({
    required String tripId,
    required String messageId,
    required Uint8List bytes,
    required String fileExt,
    required TripMessageThreadScope scope,
    String? replyToMessageId,
    String? caption,
    double? imageWidth,
    double? imageHeight,
    void Function(double progress)? onUploadProgress,
  }) async {
    final uid = _requireUid();
    final cleanTripId = _validId(tripId);
    final cleanMessageId = _validId(messageId);
    if (bytes.isEmpty) throw StateError('Image invalide');
    if (bytes.length > maxImageBytes) {
      throw StateError('Image trop volumineuse');
    }
    final trimmedCaption = (caption ?? '').trim();
    if (trimmedCaption.length > maxTextLength) {
      throw StateError('Message trop long');
    }

    final storageSegmentRe = RegExp(r'^[A-Za-z0-9_-]+$');
    if (!storageSegmentRe.hasMatch(cleanTripId) ||
        !storageSegmentRe.hasMatch(cleanMessageId) ||
        !storageSegmentRe.hasMatch(uid)) {
      throw StateError('Parametres invalides');
    }

    final safeExt = fileExt.trim().toLowerCase().replaceAll('.', '');
    final ext = safeExt.isEmpty ? 'jpg' : safeExt;
    final objectPath = 'trips/$cleanTripId/messages/$uid/$cleanMessageId.$ext';
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
      SettableMetadata(
        contentType: contentType,
        customMetadata: {'authorId': uid},
      ),
    );
    StreamSubscription<TaskSnapshot>? progressSub;
    if (onUploadProgress != null) {
      progressSub = uploadTask.snapshotEvents.listen(
        (event) {
          final total = event.totalBytes;
          if (total > 0) onUploadProgress(event.bytesTransferred / total);
        },
        onError: (_) {},
      );
    }
    final String downloadUrl;
    try {
      await uploadTask;
      downloadUrl = await objectRef.getDownloadURL();
    } finally {
      await progressSub?.cancel();
    }

    final payload = <String, dynamic>{
      'type': TripMessageKind.image.firestoreValue,
      'imageUrl': downloadUrl,
      'imageStoragePath': objectPath,
      'authorId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      if (imageWidth != null && imageHeight != null) ...{
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
      },
      if (trimmedCaption.isNotEmpty) 'text': trimmedCaption,
      ..._threadFields(scope),
      ..._replyField(replyToMessageId),
    };

    try {
      await _messagesCol(cleanTripId).doc(cleanMessageId).set(payload);
    } catch (e) {
      try {
        await objectRef.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> updateMessageText({
    required String tripId,
    required String messageId,
    required String text,
  }) async {
    _requireUid();
    final trimmed = _validText(text);
    await _messagesCol(_validId(tripId)).doc(_validId(messageId)).update({
      'text': trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMessage({
    required String tripId,
    required String messageId,
    String? imageStoragePath,
  }) async {
    _requireUid();
    await _messagesCol(_validId(tripId)).doc(_validId(messageId)).delete();
    final storagePath = imageStoragePath?.trim() ?? '';
    if (storagePath.isNotEmpty) {
      try {
        await storage.ref(storagePath).delete();
      } catch (_) {}
    }
  }

  /// Sets the current user's reaction on a message, or removes it when
  /// [emoji] is null.
  Future<void> setMyReaction({
    required String tripId,
    required String messageId,
    required String? emoji,
  }) async {
    final uid = _requireUid();
    final cleanEmoji = emoji?.trim() ?? '';
    await _messagesCol(_validId(tripId)).doc(_validId(messageId)).set(
      {
        'reactionsByUser': {
          uid: cleanEmoji.isEmpty ? FieldValue.delete() : cleanEmoji,
        },
      },
      SetOptions(merge: true),
    );
  }

  TripChatWindow _windowFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docsNewestFirst, {
    required TripMessageThreadScope scope,
    required int limit,
  }) {
    final messages = <TripMessage>[];
    for (final doc in docsNewestFirst.reversed) {
      final message = TripMessage.fromDoc(doc);
      if (_matchesScope(message: message, scope: scope)) messages.add(message);
    }
    return TripChatWindow(
      messages: messages,
      olderCursor: docsNewestFirst.isEmpty ? null : docsNewestFirst.last,
      mayHaveOlder: docsNewestFirst.length >= limit,
    );
  }

  bool _matchesScope({
    required TripMessage message,
    required TripMessageThreadScope scope,
  }) {
    // Legacy messages without visibilityType are defaulted to tripAll by
    // fromFirestore, so they pass this check correctly for the main scope.
    if (message.visibilityType != scope.visibilityType) {
      return false;
    }
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
    Query<Map<String, dynamic>> query = _messagesCol(tripId);
    if (scope.isMain) {
      // Legacy main-thread messages have no threadType field, so the thread is
      // filtered on the client (see [_matchesScope]).
      return query.where(
        'visibilityType',
        isEqualTo: TripMessageVisibilityType.tripAll.firestoreValue,
      );
    }

    query = query
        .where('visibilityType', isEqualTo: scope.visibilityType.firestoreValue)
        .where('threadType', isEqualTo: scope.threadType.firestoreValue);

    if (scope.isObject) {
      query = query
          .where(
            'threadObjectType',
            isEqualTo: (scope.threadObjectType ?? '').trim(),
          )
          .where(
            'threadObjectId',
            isEqualTo: (scope.threadObjectId ?? '').trim(),
          );
    }
    return query;
  }

  Map<String, dynamic> _threadFields(TripMessageThreadScope scope) => {
        'threadType': scope.threadType.firestoreValue,
        'visibilityType': scope.visibilityType.firestoreValue,
        if (scope.isObject) ...{
          'threadObjectType': (scope.threadObjectType ?? '').trim(),
          'threadObjectId': (scope.threadObjectId ?? '').trim(),
        },
      };

  Map<String, dynamic> _replyField(String? replyToMessageId) {
    final cleanReplyId = replyToMessageId?.trim() ?? '';
    return cleanReplyId.isEmpty
        ? const <String, dynamic>{}
        : {'replyToMessageId': cleanReplyId};
  }

  String _requireUid() {
    final uid = currentUserId;
    if (uid == null) throw StateError('Utilisateur non connecte');
    return uid;
  }

  String _validId(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) throw StateError('Parametres invalides');
    return clean;
  }

  String _validText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) throw StateError('Message vide');
    if (trimmed.length > maxTextLength) throw StateError('Message trop long');
    return trimmed;
  }
}
