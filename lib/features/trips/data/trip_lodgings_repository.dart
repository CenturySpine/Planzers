import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_lodging.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';

final tripLodgingsRepositoryProvider = Provider<TripLodgingsRepository>((ref) {
  return TripLodgingsRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Lodgings stored for the trip (without the one built from its former
/// single link; see `effectiveTripLodgings`).
final tripLodgingsStreamProvider =
    StreamProvider.autoDispose.family<List<TripLodging>, String>((ref, tripId) {
  return ref.watch(tripLodgingsRepositoryProvider).watchLodgings(tripId);
});

class TripLodgingsRepository {
  TripLodgingsRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> _lodgingsCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('lodgings');
  }

  Stream<List<TripLodging>> watchLodgings(String tripId) {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      return Stream.value(const <TripLodging>[]);
    }
    return _lodgingsCol(cleanTripId)
        .snapshots()
        .map((snap) => snap.docs.map(TripLodging.fromDoc).toList());
  }

  /// Stores [next] as the trip's lodgings, [stored] being the ones read
  /// before: lodgings left out are deleted, the others written when they
  /// changed, and those not stored yet get a document of their own.
  Future<void> saveLodgings({
    required String tripId,
    required List<TripLodging> next,
    required List<TripLodging> stored,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final tripSnap = await tripRef.get();
    if (!tripSnap.exists || tripSnap.data() == null) {
      throw StateError('Voyage introuvable');
    }
    final trip = Trip.fromMap(tripSnap.id, tripSnap.data()!);
    if (!canEditTripGeneralInfoForTrip(trip: trip, userId: user.uid)) {
      throw StateError('Droits insuffisants pour modifier les hébergements');
    }

    final col = _lodgingsCol(cleanTripId);
    final storedById = {for (final lodging in stored) lodging.id: lodging};
    final keptIds = <String>{};
    final batch = firestore.batch();
    for (final lodging in next) {
      final before = storedById[lodging.id];
      if (before != null) {
        keptIds.add(lodging.id);
        if (before.sameContentAs(lodging)) continue;
        batch.set(
          col.doc(lodging.id),
          {
            ...lodging.toFirestore(),
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': user.uid,
          },
          SetOptions(merge: true),
        );
      } else {
        batch.set(
          col.doc(),
          {
            ...lodging.toFirestore(),
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': user.uid,
          },
          SetOptions(merge: true),
        );
      }
    }
    for (final lodging in stored) {
      if (!keptIds.contains(lodging.id)) batch.delete(col.doc(lodging.id));
    }
    // From now on, the former single link no longer stands for the lodging.
    if (!trip.lodgingsByNight) {
      batch.update(tripRef, {'lodgingsByNight': true});
    }
    await batch.commit();
  }
}
