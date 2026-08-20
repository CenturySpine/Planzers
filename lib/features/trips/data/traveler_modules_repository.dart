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
/// to that participant. Each module owns its own sub-object in the
/// Firestore doc (own key, own shape) so adding a future module never
/// means adding new flat sibling fields here.
class RidgegearModuleConfig {
  const RidgegearModuleConfig({
    this.enabled = false,
    this.projectId,
    this.projectName,
  });

  final bool enabled;
  final String? projectId;
  final String? projectName;

  factory RidgegearModuleConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const RidgegearModuleConfig();
    return RidgegearModuleConfig(
      enabled: map['enabled'] == true,
      projectId: (map['projectId'] as String?)?.trim().isNotEmpty == true
          ? (map['projectId'] as String).trim()
          : null,
      projectName: (map['projectName'] as String?)?.trim().isNotEmpty == true
          ? (map['projectName'] as String).trim()
          : null,
    );
  }
}

class TravelerModules {
  const TravelerModules({
    this.ridgegear = const RidgegearModuleConfig(),
    this.walletEnabled = false,
  });

  final RidgegearModuleConfig ridgegear;
  final bool walletEnabled;

  factory TravelerModules.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const TravelerModules();
    return TravelerModules(
      ridgegear: RidgegearModuleConfig.fromMap(
        map['ridgegear'] as Map<String, dynamic>?,
      ),
      walletEnabled: (map['wallet'] as Map<String, dynamic>?)?['enabled'] == true,
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

  DocumentReference<Map<String, dynamic>>? _myDocRef(String tripId) {
    final uid = auth.currentUser?.uid.trim() ?? '';
    final cleanTripId = tripId.trim();
    if (uid.isEmpty || cleanTripId.isEmpty) return null;
    return firestore
        .collection('trips')
        .doc(cleanTripId)
        .collection('travelerModules')
        .doc(uid);
  }

  Stream<TravelerModules> watchMyTravelerModules(String tripId) {
    final docRef = _myDocRef(tripId);
    if (docRef == null) return Stream.value(const TravelerModules());
    return docRef.snapshots().map((snap) => TravelerModules.fromMap(snap.data()));
  }

  Future<void> setWalletEnabled({
    required String tripId,
    required bool enabled,
  }) async {
    final docRef = _myDocRef(tripId);
    if (docRef == null) throw StateError('Utilisateur ou voyage invalide');
    await docRef.set({
      'wallet': {'enabled': enabled},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Turns the module on/off in the trip without touching the connected
  /// project — used when the traveler adds/removes the module from their
  /// list. Connecting to Ridgegear and picking a project happens later,
  /// on demand, when they tap the module cartouche.
  Future<void> setRidgegearEnabled({
    required String tripId,
    required bool enabled,
  }) async {
    final docRef = _myDocRef(tripId);
    if (docRef == null) throw StateError('Utilisateur ou voyage invalide');
    await docRef.set({
      'ridgegear': {'enabled': enabled},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setRidgegearProject({
    required String tripId,
    required String projectId,
    required String projectName,
  }) async {
    final docRef = _myDocRef(tripId);
    if (docRef == null) throw StateError('Utilisateur ou voyage invalide');
    await docRef.set({
      'ridgegear': {
        'enabled': true,
        'projectId': projectId,
        'projectName': projectName,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> disableRidgegear(String tripId) async {
    final docRef = _myDocRef(tripId);
    if (docRef == null) throw StateError('Utilisateur ou voyage invalide');
    await docRef.set({
      'ridgegear': {
        'enabled': false,
        'projectId': null,
        'projectName': null,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
