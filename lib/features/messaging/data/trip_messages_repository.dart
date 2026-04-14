import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/messaging/data/trip_message.dart';

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
}
