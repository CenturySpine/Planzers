import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/features/wallet/data/wallet_document_category.dart';

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
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
  return WalletRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    storage: FirebaseStorage.instanceFor(bucket: bucketUri),
  );
});

/// The current traveler's documents for a trip, in chronological order.
final myWalletDocumentsStreamProvider = StreamProvider.autoDispose
    .family<List<WalletDocument>, String>((ref, tripId) {
  return ref.watch(walletRepositoryProvider).watchMyDocuments(tripId);
});

class WalletRepository {
  WalletRepository({
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

  CollectionReference<Map<String, dynamic>> _documentsRef(
    String tripId,
    String uid,
  ) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('travelerModules')
        .doc(uid)
        .collection('walletDocuments');
  }

  Stream<List<WalletDocument>> watchMyDocuments(String tripId) {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty || tripId.trim().isEmpty) {
      return Stream.value(const <WalletDocument>[]);
    }
    return _documentsRef(tripId, uid).snapshots().map((snap) {
      final documents = snap.docs.map(WalletDocument.fromDoc).toList()
        ..sort(compareWalletDocuments);
      return documents;
    });
  }

  /// Uploads the file, then records the document. If recording fails, the
  /// uploaded file is removed so no orphan stays in Storage.
  Future<void> addFileDocument({
    required String tripId,
    required String name,
    required WalletDocumentCategory category,
    required DateTime? eventDate,
    required Uint8List bytes,
    required String originalFileName,
    void Function(double progress)? onUploadProgress,
  }) async {
    final uid = _requireUid();
    final cleanTripId = tripId.trim();
    if (!_safeSegment.hasMatch(cleanTripId) || !_safeSegment.hasMatch(uid)) {
      throw StateError('Paramètres invalides');
    }
    final extension = walletFileExtension(originalFileName);
    final contentType = walletContentTypeByExtension[extension];
    if (contentType == null) throw const WalletUnsupportedFileException();
    if (bytes.lengthInBytes > walletMaxFileSizeBytes) {
      throw const WalletFileTooLargeException();
    }

    final docRef = _documentsRef(cleanTripId, uid).doc();
    final storagePath = 'users/$uid/wallet/$cleanTripId/${docRef.id}.$extension';
    final objectRef = storage.ref(storagePath);
    final uploadTask = objectRef.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: {'tripId': cleanTripId, 'documentId': docRef.id},
      ),
    );
    if (onUploadProgress != null) {
      uploadTask.snapshotEvents.listen(
        (event) {
          final total = event.totalBytes;
          if (total > 0) onUploadProgress(event.bytesTransferred / total);
        },
        onError: (_) {},
      );
    }
    await uploadTask;

    try {
      await docRef.set({
        'name': name.trim(),
        'category': category.name,
        'kind': WalletDocumentKind.file.name,
        if (eventDate != null) 'eventDate': Timestamp.fromDate(eventDate),
        'file': WalletDocumentFile(
          storagePath: storagePath,
          contentType: contentType,
          sizeBytes: bytes.lengthInBytes,
          originalFileName: originalFileName.trim(),
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      try {
        await objectRef.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> updateDocumentMetadata({
    required String tripId,
    required String documentId,
    required String name,
    required WalletDocumentCategory category,
    required DateTime? eventDate,
  }) async {
    final uid = _requireUid();
    await _documentsRef(tripId, uid).doc(documentId).update({
      'name': name.trim(),
      'category': category.name,
      'eventDate':
          eventDate == null ? FieldValue.delete() : Timestamp.fromDate(eventDate),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes the record first (the document disappears for the user even if
  /// the file cleanup fails), then the stored file, best effort.
  Future<void> deleteDocument({
    required String tripId,
    required WalletDocument document,
  }) async {
    final uid = _requireUid();
    await _documentsRef(tripId, uid).doc(document.id).delete();
    final storagePath = document.file?.storagePath;
    if (storagePath == null || storagePath.isEmpty) return;
    try {
      await storage.ref(storagePath).delete();
    } catch (_) {}
  }

  Future<String> fileDownloadUrl(String storagePath) {
    return storage.ref(storagePath).getDownloadURL();
  }
}

String walletFileExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

class WalletUnsupportedFileException implements Exception {
  const WalletUnsupportedFileException();
}

class WalletFileTooLargeException implements Exception {
  const WalletFileTooLargeException();
}
