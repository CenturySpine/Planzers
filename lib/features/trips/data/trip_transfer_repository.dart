import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';

final tripTransferRepositoryProvider = Provider<TripTransferRepository>((ref) {
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
  return TripTransferRepository(
    auth: FirebaseAuth.instance,
    storage: FirebaseStorage.instanceFor(bucket: bucketUri),
    functions: FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion),
  );
});

/// The file was exported from another app version: both sides must run the
/// exact same version, the file holding the data as stored.
class TripTransferVersionMismatchException implements Exception {
  const TripTransferVersionMismatchException({
    required this.fileVersion,
    required this.appVersion,
  });

  final String fileVersion;
  final String appVersion;
}

/// The file is not a trip export.
class TripTransferInvalidFileException implements Exception {
  const TripTransferInvalidFileException();
}

/// Export of a trip to a JSON file, and import of such a file as a new trip
/// (e.g. from preview to prod), done by the `exportTrip` / `importTrip`
/// Cloud Functions for application owners only. The file goes through the
/// user's Storage folder both ways, the embedded files being too large for a
/// callable payload. Each run leaves a journal in the administration section.
class TripTransferRepository {
  TripTransferRepository({
    required this.auth,
    required this.storage,
    required this.functions,
  });

  final FirebaseAuth auth;
  final FirebaseStorage storage;
  final FirebaseFunctions functions;

  static const _callableTimeout = Duration(minutes: 9);

  Future<String> _appVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  /// JSON file of the trip.
  Future<Uint8List> exportTrip({required String tripId}) async {
    final result = await functions
        .httpsCallable(
          'exportTrip',
          options: HttpsCallableOptions(timeout: _callableTimeout),
        )
        .call<Map<String, dynamic>>({
      'tripId': tripId.trim(),
      'appVersion': await _appVersion(),
    });
    final storagePath = (result.data['storagePath'] as String?)?.trim() ?? '';
    final sizeBytes = (result.data['sizeBytes'] as num?)?.toInt() ?? 0;
    if (storagePath.isEmpty || sizeBytes <= 0) {
      throw StateError('Export invalide');
    }
    final fileRef = storage.ref(storagePath);
    try {
      final bytes = await fileRef.getData(sizeBytes + 1);
      if (bytes == null) throw StateError('Export introuvable');
      return bytes;
    } finally {
      try {
        await fileRef.delete();
      } catch (_) {}
    }
  }

  /// Creates a new trip, owned by the current user, from an exported file;
  /// returns its id.
  Future<String> importTrip({required Uint8List bytes}) async {
    final uid = auth.currentUser?.uid ?? '';
    if (uid.isEmpty) throw StateError('Utilisateur non connecté');
    final fileRef = storage.ref(
      'users/$uid/tripTransfers/import-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await fileRef.putData(
      bytes,
      SettableMetadata(contentType: 'application/json'),
    );
    try {
      final result = await functions
          .httpsCallable(
            'importTrip',
            options: HttpsCallableOptions(timeout: _callableTimeout),
          )
          .call<Map<String, dynamic>>({
        'storagePath': fileRef.fullPath,
        'appVersion': await _appVersion(),
      });
      final tripId = (result.data['tripId'] as String?)?.trim() ?? '';
      if (tripId.isEmpty) throw StateError('Import invalide');
      return tripId;
    } on FirebaseFunctionsException catch (e) {
      // The function removes the file once read; this covers earlier failures.
      try {
        await fileRef.delete();
      } catch (_) {}
      final details = e.details is Map ? e.details as Map : const {};
      switch (details['reason']) {
        case 'version-mismatch':
          throw TripTransferVersionMismatchException(
            fileVersion: (details['fileVersion'] as String?) ?? '',
            appVersion: (details['appVersion'] as String?) ?? '',
          );
        case 'invalid-file':
          throw const TripTransferInvalidFileException();
      }
      rethrow;
    }
  }
}

/// Default name of an exported file: `planerz-<title>-<date>-v<version>.json`.
Future<String> tripExportFileName({
  required String tripTitle,
  required DateTime exportedAt,
}) async {
  const accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ç': 'c', 'é': 'e', 'è': 'e',
    'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ô': 'o', 'ö': 'o',
    'ó': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ÿ': 'y', 'ñ': 'n',
    'œ': 'oe', 'æ': 'ae',
  };
  final folded = tripTitle
      .toLowerCase()
      .split('')
      .map((char) => accents[char] ?? char)
      .join();
  final slug = folded
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final date = '${exportedAt.year.toString().padLeft(4, '0')}-'
      '${exportedAt.month.toString().padLeft(2, '0')}-'
      '${exportedAt.day.toString().padLeft(2, '0')}';
  final version = (await PackageInfo.fromPlatform()).version;
  final titlePart = slug.isEmpty ? '' : '-$slug';
  return 'planerz$titlePart-$date-v$version.json';
}
