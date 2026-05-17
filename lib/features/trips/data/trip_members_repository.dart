import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/trips/data/trip_member.dart';

final tripMembersRepositoryProvider = Provider<TripMembersRepository>((ref) {
  return TripMembersRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Stream of [TripMember] documents for a trip (`trips/{tripId}/participants/*`).
final tripParticipantsStreamProvider =
    StreamProvider.autoDispose.family<List<TripMember>, String>((ref, tripId) {
  return ref.watch(tripMembersRepositoryProvider).streamParticipants(tripId);
});

class TripMembersRepository {
  TripMembersRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> _participantsRef(String tripId) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('participants');
  }

  Stream<List<TripMember>> streamParticipants(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) return const Stream.empty();
    return _participantsRef(cleanId).snapshots().map(
          (snap) => snap.docs
              .map((doc) => TripMember.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> addParticipant({
    required String tripId,
    required String participantName,
  }) async {
    final cleanId = tripId.trim();
    final name = participantName.trim();
    if (cleanId.isEmpty) throw StateError('Voyage invalide');
    if (name.isEmpty) throw StateError('Nom obligatoire');
    await _participantsRef(cleanId).add({
      'participantName': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateParticipantName({
    required String tripId,
    required String memberId,
    required String participantName,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanMemberId = memberId.trim();
    final name = participantName.trim();
    if (cleanTripId.isEmpty || cleanMemberId.isEmpty) {
      throw StateError('Paramètres invalides');
    }
    if (name.isEmpty) throw StateError('Nom obligatoire');
    await _participantsRef(cleanTripId).doc(cleanMemberId).update({
      'participantName': name,
    });
  }

  Future<void> removeParticipant({
    required String tripId,
    required String memberId,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanMemberId = memberId.trim();
    if (cleanTripId.isEmpty || cleanMemberId.isEmpty) {
      throw StateError('Paramètres invalides');
    }
    await _participantsRef(cleanTripId).doc(cleanMemberId).delete();
  }

  /// Sets [userId] on an existing participant document (claim flow).
  Future<void> claimParticipant({
    required String tripId,
    required String memberId,
    required String userId,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanMemberId = memberId.trim();
    final cleanUserId = userId.trim();
    if (cleanTripId.isEmpty || cleanMemberId.isEmpty || cleanUserId.isEmpty) {
      throw StateError('Paramètres invalides');
    }
    await _participantsRef(cleanTripId).doc(cleanMemberId).update({
      'userId': cleanUserId,
    });
  }
}
