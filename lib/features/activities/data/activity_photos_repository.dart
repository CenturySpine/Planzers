import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/features/activities/data/activity_photo.dart';
import 'package:planerz/features/activities/data/activity_photo_encoding.dart';

final activityPhotosRepositoryProvider =
    Provider<ActivityPhotosRepository>((ref) {
  final target = ref.watch(firebaseTargetProvider);
  final configuredBucket = switch (target) {
    FirebaseTarget.preview => 'planerz-preview.firebasestorage.app',
    FirebaseTarget.prod => 'planerz.firebasestorage.app',
  };
  final rawBucket = (Firebase.app().options.storageBucket ?? '').trim();
  final effectiveBucket = rawBucket.isEmpty ? configuredBucket : rawBucket;
  final bucketUri = effectiveBucket.startsWith('gs://')
      ? effectiveBucket
      : 'gs://$effectiveBucket';
  return ActivityPhotosRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    storage: FirebaseStorage.instanceFor(bucket: bucketUri),
  );
});

/// The current traveler's photos for a trip, all activities together.
final myActivityPhotosStreamProvider = StreamProvider.autoDispose
    .family<List<ActivityPhoto>, String>((ref, tripId) {
  return ref.watch(activityPhotosRepositoryProvider).watchMyPhotos(tripId);
});

class ActivityPhotosRepository {
  ActivityPhotosRepository({
    required this.firestore,
    required this.auth,
    required this.storage,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseStorage storage;

  static final RegExp _safeSegment = RegExp(r'^[A-Za-z0-9_-]+$');

  String _requireUid() {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) throw StateError('Utilisateur non connecté');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _photosRef(
    String tripId,
    String uid,
  ) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('travelerModules')
        .doc(uid)
        .collection('activityPhotos');
  }

  Stream<List<ActivityPhoto>> watchMyPhotos(String tripId) {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty || tripId.trim().isEmpty) {
      return Stream.value(const <ActivityPhoto>[]);
    }
    return _photosRef(tripId, uid).snapshots().map(
          (snap) => snap.docs.map(ActivityPhoto.fromDoc).toList()
            ..sort(compareActivityPhotos),
        );
  }

  /// Reduces the photo, uploads it with its thumbnail, then records it. If
  /// anything fails, the uploaded files are removed so no orphan stays in
  /// Storage. The daily limit is checked by the caller.
  Future<void> addPhoto({
    required String tripId,
    required String activityId,
    required Uint8List bytes,
  }) async {
    final uid = _requireUid();
    final cleanTripId = tripId.trim();
    final cleanActivityId = activityId.trim();
    if (!_safeSegment.hasMatch(cleanTripId) ||
        !_safeSegment.hasMatch(cleanActivityId) ||
        !_safeSegment.hasMatch(uid)) {
      throw StateError('Paramètres invalides');
    }
    final prepared = await prepareActivityPhoto(bytes);

    final docRef = _photosRef(cleanTripId, uid).doc();
    final photoRef =
        storage.ref(activityPhotoStoragePath(uid, cleanTripId, docRef.id));
    final thumbRef = storage
        .ref(activityPhotoThumbStoragePath(uid, cleanTripId, docRef.id));
    // Files are never replaced, so they can stay cached on the device.
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      cacheControl: 'private, max-age=31536000, immutable',
      customMetadata: {'tripId': cleanTripId, 'activityId': cleanActivityId},
    );
    try {
      await photoRef.putData(prepared.photo, metadata);
      await thumbRef.putData(prepared.thumbnail, metadata);
      await docRef.set({
        'activityId': cleanActivityId,
        'url': await photoRef.getDownloadURL(),
        'thumbUrl': await thumbRef.getDownloadURL(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      for (final ref in [photoRef, thumbRef]) {
        try {
          await ref.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Removes the record first (the photo disappears even if the file cleanup
  /// fails; the server removes the files too), then the files, best effort.
  Future<void> deletePhoto({
    required String tripId,
    required ActivityPhoto photo,
  }) async {
    final uid = _requireUid();
    final cleanTripId = tripId.trim();
    await _photosRef(cleanTripId, uid).doc(photo.id).delete();
    for (final path in [
      activityPhotoStoragePath(uid, cleanTripId, photo.id),
      activityPhotoThumbStoragePath(uid, cleanTripId, photo.id),
    ]) {
      try {
        await storage.ref(path).delete();
      } catch (_) {}
    }
  }
}
