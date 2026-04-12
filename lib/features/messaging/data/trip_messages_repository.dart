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
}
