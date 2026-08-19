import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final travelerModulesRepositoryProvider =
    Provider<TravelerModulesRepository>((ref) {
  return TravelerModulesRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

final myTravelerModulesStreamProvider =
    StreamProvider.autoDispose.family<TravelerModules, String>((ref, tripId) {
  return ref
      .watch(travelerModulesRepositoryProvider)
      .watchMyTravelerModules(tripId);
});

/// "Traveler modules" (e.g. Ridgegear, Wallet) — personal modules any
/// participant can enable/disable for themselves, independent of the
/// trip-wide module configuration set by the trip admin, and visible only
/// to that participant.
class TravelerModules {
  const TravelerModules({
    this.ridgegearEnabled = false,
    this.walletEnabled = false,
  });

  final bool ridgegearEnabled;
  final bool walletEnabled;

  factory TravelerModules.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const TravelerModules();
    return TravelerModules(
      ridgegearEnabled: map['ridgegearEnabled'] == true,
      walletEnabled: map['walletEnabled'] == true,
    );
  }
}

class TravelerModulesRepository {
  TravelerModulesRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  Stream<TravelerModules> watchMyTravelerModules(String tripId) {
    final uid = auth.currentUser?.uid.trim() ?? '';
    final cleanTripId = tripId.trim();
    if (uid.isEmpty || cleanTripId.isEmpty) {
      return Stream.value(const TravelerModules());
    }
    return firestore
        .collection('trips')
        .doc(cleanTripId)
        .collection('travelerModules')
        .doc(uid)
        .snapshots()
        .map((snap) => TravelerModules.fromMap(snap.data()));
  }

  Future<void> setModuleEnabled({
    required String tripId,
    bool? ridgegearEnabled,
    bool? walletEnabled,
  }) async {
    final uid = auth.currentUser?.uid.trim() ?? '';
    final cleanTripId = tripId.trim();
    if (uid.isEmpty) throw StateError('Utilisateur non connecté');
    if (cleanTripId.isEmpty) throw StateError('Voyage invalide');

    final update = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (ridgegearEnabled != null) update['ridgegearEnabled'] = ridgegearEnabled;
    if (walletEnabled != null) update['walletEnabled'] = walletEnabled;

    await firestore
        .collection('trips')
        .doc(cleanTripId)
        .collection('travelerModules')
        .doc(uid)
        .set(update, SetOptions(merge: true));
  }
}
