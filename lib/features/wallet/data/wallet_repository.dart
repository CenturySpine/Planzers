import 'dart:async';
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
import 'package:planerz/features/wallet/data/wallet_local_store.dart';

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

/// Ids of the current traveler's documents of a trip that have a copy on
/// this device. Always read from the device storage (the browser may have
/// evicted copies), never assumed; refreshed after each download/removal.
final myWalletOfflineDocumentIdsProvider =
    FutureProvider.autoDispose.family<Set<String>, String>((ref, tripId) {
  return ref.watch(walletRepositoryProvider).offlineDocumentIds(tripId);
});

/// Documents whose download is in progress (list shows a spinner).
final walletDownloadingIdsProvider =
    NotifierProvider<WalletDownloadingIds, Set<String>>(WalletDownloadingIds.new);

class WalletDownloadingIds extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String id) => state = {...state, id};

  void remove(String id) => state = {...state}..remove(id);
}

/// Files the in-app PDF viewer loads on first use; fetched once online when a
/// PDF is downloaded so the offline worker keeps them.
const List<String> _pdfViewerEngineFiles = [
  'assets/packages/pdfrx/assets/pdfium_worker.js',
  'assets/packages/pdfrx/assets/pdfium.wasm',
  'assets/packages/pdfrx/assets/pdfium_client.js',
];

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
      // Only an up-to-date list proves a document is gone (e.g. deleted from
      // another device): drop its offline copy then.
      if (!snap.metadata.isFromCache && !snap.metadata.hasPendingWrites) {
        unawaited(
          _removeOrphanCopies(uid, tripId, documents.map((d) => d.id).toSet()),
        );
      }
      return documents;
    });
  }

  Future<void> _removeOrphanCopies(
    String uid,
    String tripId,
    Set<String> documentIds,
  ) async {
    try {
      final prefix = walletLocalTripPrefix(uid, tripId);
      for (final key in await walletLocalStore.keysWithPrefix(prefix)) {
        if (!documentIds.contains(key.substring(prefix.length))) {
          await walletLocalStore.remove(key);
        }
      }
    } catch (_) {}
  }

  Future<Set<String>> offlineDocumentIds(String tripId) async {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return const {};
    final prefix = walletLocalTripPrefix(uid, tripId.trim());
    final keys = await walletLocalStore.keysWithPrefix(prefix);
    return keys.map((key) => key.substring(prefix.length)).toSet();
  }

  /// Keeps a copy of the file on this device, in the app's own storage.
  Future<void> downloadForOffline({
    required String tripId,
    required WalletDocument document,
  }) async {
    final uid = _requireUid();
    final file = document.file;
    if (file == null) return;
    final bytes = await storage
        .ref(file.storagePath)
        .getData(walletMaxFileSizeBytes + 1);
    if (bytes == null) throw StateError('Fichier introuvable');
    await walletLocalStore.save(
      walletLocalKey(uid, tripId.trim(), document.id),
      bytes,
    );
    await walletLocalStore.requestPersistence();
    if (file.isPdf) await walletLocalStore.warmUp(_pdfViewerEngineFiles);
  }

  Future<void> removeFromDevice({
    required String tripId,
    required String documentId,
  }) async {
    final uid = _requireUid();
    await walletLocalStore.remove(walletLocalKey(uid, tripId.trim(), documentId));
  }

  /// The file content: the on-device copy when there is one, otherwise the
  /// online version (not kept). Throws [WalletUnavailableOfflineException]
  /// when neither can be reached.
  Future<Uint8List> readFileBytes({
    required String tripId,
    required String documentId,
    required String storagePath,
    required bool allowNetwork,
  }) async {
    final uid = _requireUid();
    final local = await walletLocalStore.read(
      walletLocalKey(uid, tripId.trim(), documentId),
    );
    if (local != null && local.isNotEmpty) return local;
    // Known offline: fail now rather than letting Storage retry for minutes.
    if (!allowNetwork) throw const WalletUnavailableOfflineException();
    try {
      final bytes = await storage
          .ref(storagePath)
          .getData(walletMaxFileSizeBytes + 1);
      if (bytes == null) throw const WalletUnavailableOfflineException();
      return bytes;
    } on FirebaseException {
      throw const WalletUnavailableOfflineException();
    }
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

  /// A scanned code is stored as its content only (redrawn when shown).
  Future<void> addBarcodeDocument({
    required String tripId,
    required String name,
    required WalletDocumentCategory category,
    required DateTime? eventDate,
    required WalletBarcode barcode,
  }) async {
    final uid = _requireUid();
    await _documentsRef(tripId, uid).add({
      'name': name.trim(),
      'category': category.name,
      'kind': WalletDocumentKind.barcode.name,
      if (eventDate != null) 'eventDate': Timestamp.fromDate(eventDate),
      'barcode': barcode.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  /// [activityId] null removes the link.
  Future<void> setDocumentActivity({
    required String tripId,
    required String documentId,
    required String? activityId,
  }) async {
    final uid = _requireUid();
    await _documentsRef(tripId, uid).doc(documentId).update({
      'activityId': activityId ?? FieldValue.delete(),
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
    try {
      await walletLocalStore.remove(walletLocalKey(uid, tripId.trim(), document.id));
    } catch (_) {}
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

class WalletUnavailableOfflineException implements Exception {
  const WalletUnavailableOfflineException();
}
