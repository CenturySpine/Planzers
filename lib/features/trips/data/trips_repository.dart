import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/trips/data/trip.dart';

final tripsRepositoryProvider = Provider<TripsRepository>((ref) {
  return TripsRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

final tripsStreamProvider = StreamProvider<List<Trip>>((ref) {
  return ref.watch(tripsRepositoryProvider).watchMyTrips();
});

class TripsRepository {
  TripsRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  Stream<List<Trip>> watchMyTrips() {
    final user = auth.currentUser;
    if (user == null) {
      return Stream.value(const <Trip>[]);
    }

    return firestore
        .collection('trips')
        .where('memberIds', arrayContains: user.uid)
        .snapshots()
        .map((snapshot) {
          final trips = snapshot.docs
              .map((doc) => Trip.fromMap(doc.id, doc.data()))
              .toList();
          trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return trips;
        });
  }

  Future<void> createTrip({
    required String title,
    required String destination,
    String address = '',
    String linkUrl = '',
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final doc = firestore.collection('trips').doc();
    await doc.set({
      'title': title.trim(),
      'destination': destination.trim(),
      'address': address.trim(),
      'linkUrl': linkUrl.trim(),
      'ownerId': user.uid,
      'memberIds': <String>[user.uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteTrip({
    required String tripId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final docRef = firestore.collection('trips').doc(tripId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      return;
    }

    final data = snapshot.data();
    final ownerId = (data?['ownerId'] as String?) ?? '';
    if (ownerId != user.uid) {
      throw StateError('Seul le proprietaire peut supprimer ce voyage');
    }

    await docRef.delete();
  }

  Future<void> updateTrip({
    required String tripId,
    required String title,
    required String destination,
    required String address,
    required String linkUrl,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final docRef = firestore.collection('trips').doc(tripId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data();
    final ownerId = (data?['ownerId'] as String?) ?? '';
    if (ownerId != user.uid) {
      throw StateError('Seul le proprietaire peut modifier ce voyage');
    }

    await docRef.update({
      'title': title.trim(),
      'destination': destination.trim(),
      'address': address.trim(),
      'linkUrl': linkUrl.trim(),
    });
  }
}
