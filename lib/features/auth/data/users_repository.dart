import 'dart:async';

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

  /// Latest map of `users/{uid}.data()` for the given [ids].
  ///
  /// Firestore limits `whereIn` to 30 values; larger [ids] lists are queried in
  /// chunks and merged.
  Stream<Map<String, Map<String, dynamic>>> watchUsersDataByIds(
      List<String> ids) {
    final unique = <String>{};
    for (final id in ids) {
      final t = id.trim();
      if (t.isNotEmpty) unique.add(t);
    }
    if (unique.isEmpty) {
      return Stream.value(const <String, Map<String, dynamic>>{});
    }

    const maxIn = 30;
    final list = unique.toList();
    if (list.length <= maxIn) {
      return firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: list)
          .snapshots()
          .map((snap) => {for (final d in snap.docs) d.id: d.data()});
    }

    final chunks = <List<String>>[];
    for (var i = 0; i < list.length; i += maxIn) {
      final end = i + maxIn > list.length ? list.length : i + maxIn;
      chunks.add(list.sublist(i, end));
    }

    late final StreamController<Map<String, Map<String, dynamic>>> controller;
    final latest =
        List<Map<String, Map<String, dynamic>>?>.filled(chunks.length, null);
    var subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emitIfComplete() {
      if (latest.any((m) => m == null)) return;
      final out = <String, Map<String, dynamic>>{};
      for (final part in latest) {
        out.addAll(part!);
      }
      controller.add(out);
    }

    controller = StreamController<Map<String, Map<String, dynamic>>>(
      onListen: () {
        for (var i = 0; i < chunks.length; i++) {
          final index = i;
          subscriptions.add(
            firestore
                .collection('users')
                .where(FieldPath.documentId, whereIn: chunks[index])
                .snapshots()
                .listen((snap) {
              latest[index] = {
                for (final d in snap.docs) d.id: d.data(),
              };
              emitIfComplete();
            }),
          );
        }
      },
      onCancel: () {
        for (final s in subscriptions) {
          s.cancel();
        }
        subscriptions = [];
      },
    );

    return controller.stream;
  }
}
