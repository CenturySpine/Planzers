import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/account/data/account_preferences.dart';

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

final autoOpenCurrentTripEnabledProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(accountRepositoryProvider)
      .watchMyUserDocument()
      .map((snapshot) => readAutoOpenCurrentTripPreference(snapshot.data()));
});

class AccountRepository {
  AccountRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMyUserDocument() {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Utilisateur non connecte');
    }
    return firestore.collection('users').doc(uid).snapshots();
  }

  Future<void> updateAccountName(String accountName) async {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Utilisateur non connecte');
    }

    final userRef = firestore.collection('users').doc(uid);
    await userRef.set({
      'account': {
        'name': accountName.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateAutoOpenCurrentTripPreference(bool enabled) async {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Utilisateur non connecte');
    }

    final userRef = firestore.collection('users').doc(uid);
    await userRef.set({
      'account': {
        autoOpenCurrentTripPreferenceKey: enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
