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
import 'package:planerz/features/trips/data/trips_repository.dart';

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

/// The current traveler's photos for a trip, all activities and meals
/// together.
final myActivityPhotosStreamProvider = StreamProvider.autoDispose
    .family<List<ActivityPhoto>, String>((ref, tripId) {
  return ref.watch(activityPhotosRepositoryProvider).watchMyPhotos(tripId);
});

/// Another member's shared photos for a trip.
final sharedActivityPhotosOfMemberStreamProvider = StreamProvider.autoDispose
    .family<List<ActivityPhoto>, ({String tripId, String memberId})>(
        (ref, args) {
  return ref
      .watch(activityPhotosRepositoryProvider)
      .watchSharedPhotos(args.tripId, args.memberId);
});

/// The current traveler's favorite photo choices, by activity or meal id.
final myActivityFavoritesStreamProvider = StreamProvider.autoDispose
    .family<Map<String, ActivityFavoriteRef>, String>((ref, tripId) {
  return ref.watch(activityPhotosRepositoryProvider).watchMyFavorites(tripId);
});

/// Keys of the photos the current traveler reported, hidden for them.
final myReportedPhotoKeysStreamProvider =
    StreamProvider.autoDispose.family<Set<String>, String>((ref, tripId) {
  return ref
      .watch(activityPhotosRepositoryProvider)
      .watchMyReportedPhotoKeys(tripId);
});

/// The reports of every trip, for the application owner.
final allPhotoReportsStreamProvider =
    StreamProvider.autoDispose<List<PhotoReport>>((ref) {
  return ref.watch(activityPhotosRepositoryProvider).watchAllReports();
});

/// One photo, wherever it is stored; null once deleted. Reading a photo
/// made private fails, which callers show as gone too.
final activityPhotoStreamProvider = StreamProvider.autoDispose
    .family<ActivityPhoto?, ({String tripId, String ownerId, String photoId})>(
  (ref, args) => ref
      .watch(activityPhotosRepositoryProvider)
      .watchPhoto(args.tripId, args.ownerId, args.photoId),
);

/// The photos the current traveler sees on a trip: their own first, then
/// the other members' shared ones, minus those they reported.
final visibleActivityPhotosProvider =
    Provider.autoDispose.family<List<ActivityPhoto>, String>((ref, tripId) {
  final myUid = ref.watch(activityPhotosRepositoryProvider).currentUid;
  final mine =
      ref.watch(myActivityPhotosStreamProvider(tripId)).asData?.value ??
          const <ActivityPhoto>[];
  final memberIds =
      ref.watch(tripStreamProvider(tripId)).asData?.value?.memberUserIds ??
          const <String>[];
  final hidden =
      ref.watch(myReportedPhotoKeysStreamProvider(tripId)).asData?.value ??
          const <String>{};
  final others = <ActivityPhoto>[
    for (final memberId in memberIds)
      if (memberId != myUid)
        ...?ref
            .watch(sharedActivityPhotosOfMemberStreamProvider(
              (tripId: tripId, memberId: memberId),
            ))
            .asData
            ?.value,
  ].where((photo) => !hidden.contains(photo.key)).toList()
    ..sort(compareActivityPhotos);
  return [...mine, ...others];
});

/// The current traveler's favorite photo of each activity or meal, by its
/// id.
final activityFavoritePhotosProvider = Provider.autoDispose
    .family<Map<String, ActivityPhoto>, String>((ref, tripId) {
  return resolveActivityFavorites(
    favorites:
        ref.watch(myActivityFavoritesStreamProvider(tripId)).asData?.value ??
            const <String, ActivityFavoriteRef>{},
    visiblePhotos: ref.watch(visibleActivityPhotosProvider(tripId)),
    myPhotos: ref.watch(myActivityPhotosStreamProvider(tripId)).asData?.value ??
        const <ActivityPhoto>[],
  );
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

  String get currentUid => auth.currentUser?.uid.trim() ?? '';

  String _requireUid() {
    final uid = currentUid;
    if (uid.isEmpty) throw StateError('Utilisateur non connecté');
    return uid;
  }

  DocumentReference<Map<String, dynamic>> _moduleRef(
    String tripId,
    String uid,
  ) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('travelerModules')
        .doc(uid);
  }

  CollectionReference<Map<String, dynamic>> _photosRef(
    String tripId,
    String uid,
  ) {
    return _moduleRef(tripId, uid).collection('activityPhotos');
  }

  CollectionReference<Map<String, dynamic>> _reportsRef(String tripId) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('photoReports');
  }

  Stream<List<ActivityPhoto>> watchSharedPhotos(
    String tripId,
    String memberId,
  ) {
    if (tripId.trim().isEmpty || memberId.trim().isEmpty) {
      return Stream.value(const <ActivityPhoto>[]);
    }
    return _photosRef(tripId, memberId.trim())
        .where('shared', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map(ActivityPhoto.fromDoc).toList());
  }

  Stream<ActivityPhoto?> watchPhoto(
    String tripId,
    String ownerId,
    String photoId,
  ) {
    return _photosRef(tripId, ownerId)
        .doc(photoId)
        .snapshots()
        .map((doc) => doc.exists ? ActivityPhoto.fromDoc(doc) : null);
  }

  Stream<Map<String, ActivityFavoriteRef>> watchMyFavorites(String tripId) {
    final uid = currentUid;
    if (uid.isEmpty || tripId.trim().isEmpty) {
      return Stream.value(const <String, ActivityFavoriteRef>{});
    }
    return _moduleRef(tripId, uid)
        .collection('activityFavorites')
        .snapshots()
        .map((snap) => {
              for (final doc in snap.docs)
                doc.id: ActivityFavoriteRef.fromDoc(doc),
            });
  }

  Stream<Set<String>> watchMyReportedPhotoKeys(String tripId) {
    final uid = currentUid;
    if (uid.isEmpty || tripId.trim().isEmpty) {
      return Stream.value(const <String>{});
    }
    return _reportsRef(tripId)
        .where('reporterId', isEqualTo: uid)
        .snapshots()
        .map((snap) =>
            {for (final doc in snap.docs) PhotoReport.fromDoc(doc).photoKey});
  }

  Stream<List<PhotoReport>> watchAllReports() {
    return firestore
        .collectionGroup('photoReports')
        .snapshots()
        .map(_sortedReports);
  }

  /// Newest first.
  static List<PhotoReport> _sortedReports(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final reports = snap.docs.map(PhotoReport.fromDoc).toList();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    reports
        .sort((a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch));
    return reports;
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
    required PhotoSubject subject,
    required Uint8List bytes,
  }) async {
    final uid = _requireUid();
    final cleanTripId = tripId.trim();
    final cleanSubjectId = subject.id.trim();
    if (!_safeSegment.hasMatch(cleanTripId) ||
        !_safeSegment.hasMatch(cleanSubjectId) ||
        !_safeSegment.hasMatch(uid)) {
      throw StateError('Paramètres invalides');
    }
    final prepared = await prepareActivityPhoto(bytes);

    final docRef = _photosRef(cleanTripId, uid).doc();
    final photoRef =
        storage.ref(activityPhotoStoragePath(uid, cleanTripId, docRef.id));
    final thumbRef =
        storage.ref(activityPhotoThumbStoragePath(uid, cleanTripId, docRef.id));
    // Files are never replaced, so they can stay cached on the device.
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      cacheControl: 'private, max-age=31536000, immutable',
      customMetadata: {
        'tripId': cleanTripId,
        subject.firestoreField: cleanSubjectId,
      },
    );
    try {
      await photoRef.putData(prepared.photo, metadata);
      await thumbRef.putData(prepared.thumbnail, metadata);
      await docRef.set({
        subject.firestoreField: cleanSubjectId,
        'url': await photoRef.getDownloadURL(),
        'thumbUrl': await thumbRef.getDownloadURL(),
        'shared': true,
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

  /// Sets the photo's caption (its length is capped by the caption field);
  /// an empty one removes it.
  Future<void> updateCaption({
    required String tripId,
    required ActivityPhoto photo,
    required String caption,
  }) async {
    final uid = _requireUid();
    final clean = caption.trim();
    await _photosRef(tripId.trim(), uid).doc(photo.id).update({
      'caption': clean.isEmpty ? FieldValue.delete() : clean,
    });
  }

  /// Shares the photo with the other trip members, or makes it private.
  Future<void> setShared({
    required String tripId,
    required ActivityPhoto photo,
    required bool shared,
  }) async {
    final uid = _requireUid();
    await _photosRef(tripId.trim(), uid).doc(photo.id).update({
      'shared': shared ? true : FieldValue.delete(),
    });
  }

  /// Makes [photo] (the traveler's or another member's) their favorite of
  /// the activity or meal [subjectId], or clears it when [photo] is null.
  /// Also drops the former favorite mark from their own photos of it.
  Future<void> setFavorite({
    required String tripId,
    required String subjectId,
    required ActivityPhoto? photo,
    required Iterable<ActivityPhoto> myPhotos,
  }) async {
    final uid = _requireUid();
    final cleanTripId = tripId.trim();
    final batch = firestore.batch();
    final favoriteRef = _moduleRef(cleanTripId, uid)
        .collection('activityFavorites')
        .doc(subjectId);
    if (photo == null) {
      batch.delete(favoriteRef);
    } else {
      batch.set(favoriteRef, {
        'ownerId': photo.ownerId,
        'photoId': photo.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    for (final mine in myPhotos) {
      if (mine.subjectId == subjectId && mine.favorite) {
        batch.update(
          _photosRef(cleanTripId, uid).doc(mine.id),
          {'favorite': FieldValue.delete()},
        );
      }
    }
    await batch.commit();
  }

  /// Reports another member's shared photo; it stays hidden for the
  /// reporter.
  Future<void> reportPhoto({
    required String tripId,
    required ActivityPhoto photo,
    required PhotoReportReason reason,
  }) async {
    final uid = _requireUid();
    final id = PhotoReport.idFor(
      reporterId: uid,
      photoOwnerId: photo.ownerId,
      photoId: photo.id,
    );
    await _reportsRef(tripId).doc(id).set({
      'photoOwnerId': photo.ownerId,
      'photoId': photo.id,
      'activityId': photo.activityId,
      'reporterId': uid,
      'reason': reason.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Records how the application owner handled reports (they are kept as
  /// history); the photo stays hidden for each reporter.
  Future<void> resolveReports({
    required String tripId,
    required Iterable<String> reportIds,
    required PhotoReportResolution resolution,
  }) async {
    final batch = firestore.batch();
    for (final reportId in reportIds) {
      batch.update(_reportsRef(tripId).doc(reportId), {
        'resolution': resolution.name,
        'resolvedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Deletes another member's photo (trip admin or application owner); its
  /// files are removed server-side. The application owner passes the
  /// photo's pending reports, recorded as handled by this deletion; trip
  /// admins cannot see reports and pass none.
  Future<void> deletePhotoAsModerator({
    required String tripId,
    required String ownerId,
    required String photoId,
    required Iterable<String> pendingReportIds,
  }) async {
    final batch = firestore.batch();
    batch.delete(_photosRef(tripId, ownerId).doc(photoId));
    for (final reportId in pendingReportIds) {
      batch.update(_reportsRef(tripId).doc(reportId), {
        'resolution': PhotoReportResolution.photoRemoved.name,
        'resolvedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
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
