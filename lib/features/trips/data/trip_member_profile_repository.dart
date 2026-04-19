import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/trips/data/trip_member_stay.dart';

final tripMemberProfileRepositoryProvider =
    Provider<TripMemberProfileRepository>((ref) {
  return TripMemberProfileRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// [TripMemberStay] for the current user on a trip (`trips/{tripId}/members/{uid}`).
final tripMemberStayStreamProvider =
    StreamProvider.autoDispose.family<TripMemberStay?, String>((ref, tripId) {
  return ref.watch(tripMemberProfileRepositoryProvider).watchMyStay(tripId);
});

class TripMemberProfileRepository {
  TripMemberProfileRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  DocumentReference<Map<String, dynamic>> _memberRef({
    required String tripId,
    required String uid,
  }) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('members')
        .doc(uid.trim());
  }

  Stream<TripMemberStay?> watchMyStay(String tripId) {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return const Stream<TripMemberStay?>.empty();
    }
    final cleanTrip = tripId.trim();
    if (cleanTrip.isEmpty) {
      return const Stream<TripMemberStay?>.empty();
    }
    return _memberRef(tripId: cleanTrip, uid: uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return TripMemberStay.tryFromFirestore(data);
    });
  }

  Future<void> upsertMyStay({
    required String tripId,
    required TripMemberStay stay,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }
    final cleanTrip = tripId.trim();
    if (cleanTrip.isEmpty) {
      throw StateError('Voyage invalide');
    }
    await _memberRef(tripId: cleanTrip, uid: user.uid).set(
      {
        ...stay.toFirestoreMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
