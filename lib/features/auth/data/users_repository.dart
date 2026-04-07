import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(firestore: FirebaseFirestore.instance);
});

class UsersRepository {
  UsersRepository({required this.firestore});

  final FirebaseFirestore firestore;

  Future<void> ensureUserDocument(User user) async {
    final userRef = firestore.collection('users').doc(user.uid);

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      final now = FieldValue.serverTimestamp();
      final data = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoUrl': user.photoURL,
        'account': {
          'email': user.email,
          'photoUrl': user.photoURL,
        },
        'lastSignInAt': now,
      };

      if (snapshot.exists) {
        transaction.set(userRef, data, SetOptions(merge: true));
      } else {
        transaction.set(userRef, {
          ...data,
          'createdAt': now,
        });
      }
    });
  }
}
