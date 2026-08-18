import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tripArchiveRepositoryProvider = Provider<TripArchiveRepository>((ref) {
  return TripArchiveRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Trip IDs the current user has archived (hidden from their own trip list).
/// Per-user preference: independent of the trip's owner/admins and of any
/// other member's own archive choice.
final myArchivedTripIdsProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  return ref.watch(tripArchiveRepositoryProvider).watchMyArchivedTripIds();
});

/// Whether the current user has archived [tripId], derived from
/// [myArchivedTripIdsProvider].
final isTripArchivedForMeProvider =
    Provider.autoDispose.family<bool, String>((ref, tripId) {
  final archivedIds =
      ref.watch(myArchivedTripIdsProvider).asData?.value ?? const <String>{};
  return archivedIds.contains(tripId);
});

/// Stores which trips the current user has archived (`users/{uid}/archivedTrips/{tripId}`).
/// Purely a per-user preference: any user who is or was a trip member can
/// archive/unarchive a trip for themselves, regardless of role.
class TripArchiveRepository {
  TripArchiveRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>>? _myArchivedTripsRef() {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return null;
    return firestore.collection('users').doc(uid).collection('archivedTrips');
  }

  Stream<Set<String>> watchMyArchivedTripIds() {
    final ref = _myArchivedTripsRef();
    if (ref == null) return Stream.value(const <String>{});
    return ref.snapshots().map((snap) => snap.docs.map((doc) => doc.id).toSet());
  }

  Future<void> setTripArchivedForMe({
    required String tripId,
    required bool archived,
  }) async {
    final ref = _myArchivedTripsRef();
    if (ref == null) {
      throw StateError('Utilisateur non connecte');
    }
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }
    if (archived) {
      await ref.doc(cleanTripId).set({
        'archivedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.doc(cleanTripId).delete();
    }
  }
}
