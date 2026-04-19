import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/core/firebase/firebase_target.dart';
import 'package:planzers/core/firebase/firebase_target_provider.dart';

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final target = ref.watch(firebaseTargetProvider);
  final configuredBucket = switch (target) {
    FirebaseTarget.preview => 'planzers-preview.firebasestorage.app',
    FirebaseTarget.prod => 'planzers.firebasestorage.app',
  };
  final rawBucket = (Firebase.app().options.storageBucket ?? '').trim();
  final effectiveBucket = rawBucket.isEmpty ? configuredBucket : rawBucket;
  final bucketUri =
      effectiveBucket.startsWith('gs://') ? effectiveBucket : 'gs://$effectiveBucket';
  return AccountRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    storage: FirebaseStorage.instanceFor(bucket: bucketUri),
  );
});

/// Stored under [account.foodAllergenCatalogIds] (merge-safe).
List<String> foodAllergenCatalogIdsFromUserData(Map<String, dynamic> data) {
  final account = (data['account'] as Map<String, dynamic>?) ?? const {};
  final raw = account['foodAllergenCatalogIds'] ?? data['foodAllergenCatalogIds'];
  if (raw is List) {
    return raw
        .map((e) => e.toString().trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

bool autoOpenCurrentTripOnLaunchEnabledFromUserData(Map<String, dynamic> data) {
  final account = (data['account'] as Map<String, dynamic>?) ?? const {};
  final preferences =
      (account['preferences'] as Map<String, dynamic>?) ?? const {};
  final raw = preferences['autoOpenCurrentTripOnLaunch'];
  if (raw is bool) {
    return raw;
  }
  return true;
}

final autoOpenCurrentTripOnLaunchProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(accountRepositoryProvider)
      .watchAutoOpenCurrentTripOnLaunchPreference();
});

class AccountRepository {
  AccountRepository({
    required this.firestore,
    required this.auth,
    required this.storage,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseStorage storage;

  String _googlePhotoUrlFromAuth(User? user) {
    if (user == null) return '';
    for (final info in user.providerData) {
      if (info.providerId == 'google.com') {
        final value = (info.photoURL ?? '').trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return '';
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMyUserDocument() {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Utilisateur non connecte');
    }
    return firestore.collection('users').doc(uid).snapshots();
  }

  Stream<bool> watchAutoOpenCurrentTripOnLaunchPreference() {
    return watchMyUserDocument().map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      return autoOpenCurrentTripOnLaunchEnabledFromUserData(data);
    });
  }

  Future<void> updateAutoOpenCurrentTripOnLaunchPreference(bool enabled) async {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Utilisateur non connecte');
    }
    final userRef = firestore.collection('users').doc(uid);
    await userRef.set({
      'account': {
        'preferences': {
          'autoOpenCurrentTripOnLaunch': enabled,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<String>> readMyFoodAllergenCatalogIds() async {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Utilisateur non connecte');
    }
    final snap = await firestore.collection('users').doc(uid).get();
    return foodAllergenCatalogIdsFromUserData(snap.data() ?? const {});
  }

  Future<void> updateFoodAllergenCatalogIds(List<String> catalogIds) async {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Utilisateur non connecte');
    }
    final userRef = firestore.collection('users').doc(uid);
    final cleaned = catalogIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    await userRef.set(
      {
        'account': {
          'foodAllergenCatalogIds': cleaned,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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

  Future<void> upsertMyProfilePhoto({
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final user = auth.currentUser;
    final uid = user?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Utilisateur non connecte');
    }
    if (bytes.isEmpty) {
      throw StateError('Image invalide');
    }

    final userRef = firestore.collection('users').doc(uid);
    final snapshot = await userRef.get();
    if (!snapshot.exists) {
      throw StateError('Compte utilisateur introuvable');
    }
    final data = snapshot.data() ?? const <String, dynamic>{};
    final account = (data['account'] as Map<String, dynamic>?) ?? const {};
    final googlePhotoUrl = _googlePhotoUrlFromAuth(user);
    final previousPath = (account['photoPath'] as String?)?.trim().isNotEmpty == true
        ? (account['photoPath'] as String).trim()
        : (data['photoPath'] as String?)?.trim().isNotEmpty == true
            ? (data['photoPath'] as String).trim()
            : '';

    final safeExt = fileExt.trim().toLowerCase().replaceAll('.', '');
    final ext = safeExt.isEmpty ? 'jpg' : safeExt;
    final objectPath =
        'users/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      _ => 'image/jpeg',
    };
    final objectRef = storage.ref(objectPath);
    await objectRef.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    final url = await objectRef.getDownloadURL();

    await userRef.set({
      'photoUrl': url,
      'photoPath': objectPath,
      'updatedAt': FieldValue.serverTimestamp(),
      if (googlePhotoUrl.isNotEmpty) 'googlePhotoUrl': googlePhotoUrl,
      'account': {
        'photoUrl': url,
        'photoPath': objectPath,
        'photoUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (googlePhotoUrl.isNotEmpty) 'googlePhotoUrl': googlePhotoUrl,
      },
    }, SetOptions(merge: true));

    try {
      await user?.updatePhotoURL(url);
    } catch (_) {}

    if (previousPath.isNotEmpty && previousPath != objectPath) {
      try {
        await storage.ref(previousPath).delete();
      } catch (_) {}
    }
  }

  Future<void> removeMyProfilePhoto() async {
    final user = auth.currentUser;
    final uid = user?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Utilisateur non connecte');
    }

    final userRef = firestore.collection('users').doc(uid);
    final snapshot = await userRef.get();
    if (!snapshot.exists) {
      throw StateError('Compte utilisateur introuvable');
    }
    final data = snapshot.data() ?? const <String, dynamic>{};
    final account = (data['account'] as Map<String, dynamic>?) ?? const {};
    final fallbackGooglePhoto = (account['googlePhotoUrl'] as String?)?.trim().isNotEmpty ==
            true
        ? (account['googlePhotoUrl'] as String).trim()
        : (data['googlePhotoUrl'] as String?)?.trim().isNotEmpty == true
            ? (data['googlePhotoUrl'] as String).trim()
            : _googlePhotoUrlFromAuth(user);
    final path = (account['photoPath'] as String?)?.trim().isNotEmpty == true
        ? (account['photoPath'] as String).trim()
        : (data['photoPath'] as String?)?.trim().isNotEmpty == true
            ? (data['photoPath'] as String).trim()
            : '';

    if (path.isNotEmpty) {
      try {
        await storage.ref(path).delete();
      } catch (_) {}
    }

    if (fallbackGooglePhoto.isNotEmpty) {
      await userRef.set({
        'photoUrl': fallbackGooglePhoto,
        'photoPath': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
        'googlePhotoUrl': fallbackGooglePhoto,
        'account': {
          'photoUrl': fallbackGooglePhoto,
          'photoPath': FieldValue.delete(),
          'photoUpdatedAt': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
          'googlePhotoUrl': fallbackGooglePhoto,
        },
      }, SetOptions(merge: true));
    } else {
      await userRef.set({
        'photoUrl': FieldValue.delete(),
        'photoPath': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
        'account': {
          'photoUrl': FieldValue.delete(),
          'photoPath': FieldValue.delete(),
          'photoUpdatedAt': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    }

    try {
      await user?.updatePhotoURL(
        fallbackGooglePhoto.isEmpty ? null : fallbackGooglePhoto,
      );
    } catch (_) {}
  }
}
