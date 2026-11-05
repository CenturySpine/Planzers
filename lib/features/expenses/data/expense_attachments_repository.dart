import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/features/activities/data/activity_photo_encoding.dart';
import 'package:planerz/features/expenses/data/expense_attachment.dart';

final expenseAttachmentsRepositoryProvider =
    Provider<ExpenseAttachmentsRepository>((ref) {
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
  return ExpenseAttachmentsRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    storage: FirebaseStorage.instanceFor(bucket: bucketUri),
  );
});

typedef ExpenseAttachmentsScope = ({String tripId, String expenseId});

/// The receipts of one expense, oldest first.
final expenseAttachmentsStreamProvider = StreamProvider.autoDispose
    .family<List<ExpenseAttachment>, ExpenseAttachmentsScope>((ref, scope) {
  return ref
      .watch(expenseAttachmentsRepositoryProvider)
      .watchAttachments(scope.tripId, scope.expenseId);
});

class ExpenseAttachmentsRepository {
  ExpenseAttachmentsRepository({
    required this.firestore,
    required this.auth,
    required this.storage,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseStorage storage;

  static final RegExp _safeSegment = RegExp(r'^[A-Za-z0-9_-]+$');

  CollectionReference<Map<String, dynamic>> _attachmentsRef(
    String tripId,
    String expenseId,
  ) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('expenses')
        .doc(expenseId.trim())
        .collection('attachments');
  }

  Stream<List<ExpenseAttachment>> watchAttachments(
    String tripId,
    String expenseId,
  ) {
    if (tripId.trim().isEmpty || expenseId.trim().isEmpty) {
      return Stream.value(const <ExpenseAttachment>[]);
    }
    return _attachmentsRef(tripId, expenseId).snapshots().map(
          (snap) => snap.docs.map(ExpenseAttachment.fromDoc).toList()
            ..sort(compareExpenseAttachments),
        );
  }

  /// Reduces the photo like an activity photo, uploads it with its
  /// thumbnail, then records it. If anything fails, the uploaded files are
  /// removed so no orphan stays in Storage. The limit per expense is checked
  /// by the caller.
  Future<void> addAttachment({
    required String tripId,
    required String expenseId,
    required Uint8List bytes,
  }) async {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) throw StateError('Utilisateur non connecté');
    final cleanTripId = tripId.trim();
    final cleanExpenseId = expenseId.trim();
    if (!_safeSegment.hasMatch(cleanTripId) ||
        !_safeSegment.hasMatch(cleanExpenseId)) {
      throw StateError('Paramètres invalides');
    }
    final prepared = await prepareActivityPhoto(bytes);

    final docRef = _attachmentsRef(cleanTripId, cleanExpenseId).doc();
    final photoRef = storage.ref(
      expenseAttachmentStoragePath(cleanTripId, cleanExpenseId, docRef.id),
    );
    final thumbRef = storage.ref(
      expenseAttachmentThumbStoragePath(cleanTripId, cleanExpenseId, docRef.id),
    );
    // Files are never replaced, so they can stay cached on the device.
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      cacheControl: 'private, max-age=31536000, immutable',
      customMetadata: {
        'authorId': uid,
        'tripId': cleanTripId,
        'expenseId': cleanExpenseId,
      },
    );
    try {
      await photoRef.putData(prepared.photo, metadata);
      await thumbRef.putData(prepared.thumbnail, metadata);
      await docRef.set({
        'url': await photoRef.getDownloadURL(),
        'thumbUrl': await thumbRef.getDownloadURL(),
        'createdBy': uid,
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

  /// Removes the record; its files are removed server-side.
  Future<void> deleteAttachment({
    required String tripId,
    required String expenseId,
    required ExpenseAttachment attachment,
  }) async {
    await _attachmentsRef(tripId, expenseId).doc(attachment.id).delete();
  }
}
