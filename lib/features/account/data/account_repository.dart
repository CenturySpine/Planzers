import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
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
    final trimmed = accountName.trim();
    await userRef.set({
      'account': {
        'name': trimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final tripsSnap = await firestore
        .collection('trips')
        .where('memberIds', arrayContains: uid)
        .get();
    if (tripsSnap.docs.isEmpty) {
      return;
    }

    var batch = firestore.batch();
    var opCount = 0;
    for (final doc in tripsSnap.docs) {
      if (trimmed.isEmpty) {
        batch.update(doc.reference, {
          'memberPublicLabels.$uid': FieldValue.delete(),
        });
      } else {
        batch.update(doc.reference, {
          'memberPublicLabels.$uid': trimmed,
        });
      }
      opCount++;
      if (opCount >= 450) {
        await batch.commit();
        batch = firestore.batch();
        opCount = 0;
      }
    }
    if (opCount > 0) {
      await batch.commit();
    }
  }
}
