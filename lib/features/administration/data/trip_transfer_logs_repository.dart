import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tripTransferLogsRepositoryProvider =
    Provider<TripTransferLogsRepository>((ref) {
  return TripTransferLogsRepository(firestore: FirebaseFirestore.instance);
});

final tripTransferLogsProvider =
    StreamProvider.autoDispose<List<TripTransferLog>>((ref) {
  return ref.watch(tripTransferLogsRepositoryProvider).watchLatest();
});

/// Journals of the trip exports / imports (`tripTransferLogs`), written by
/// the Cloud Functions; the application owner reads and clears them.
class TripTransferLogsRepository {
  TripTransferLogsRepository({required this.firestore});

  final FirebaseFirestore firestore;

  /// Firestore batch limit.
  static const int _batchSize = 500;

  CollectionReference<Map<String, dynamic>> get _logs =>
      firestore.collection('tripTransferLogs');

  Stream<List<TripTransferLog>> watchLatest() {
    return _logs
        .orderBy('startedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(TripTransferLog.fromDoc).toList());
  }

  Future<void> delete(String logId) => _logs.doc(logId).delete();

  /// Deletes every journal, not only the ones listed.
  Future<void> deleteAll() async {
    while (true) {
      final snap = await _logs.limit(_batchSize).get();
      if (snap.docs.isEmpty) return;
      final batch = firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}

/// Journal of one trip export or import, written by the `exportTrip` /
/// `importTrip` Cloud Functions (`tripTransferLogs/{id}`).
class TripTransferLog {
  const TripTransferLog({
    required this.id,
    required this.isImport,
    required this.status,
    required this.startedAt,
    required this.durationMs,
    required this.tripTitle,
    required this.fileSizeBytes,
    required this.data,
  });

  final String id;
  final bool isImport;

  /// `running`, `success` or `error`; a run cut short (timeout) stays
  /// `running`.
  final String status;
  final DateTime? startedAt;
  final int? durationMs;
  final String tripTitle;
  final int? fileSizeBytes;
  final Map<String, dynamic> data;

  factory TripTransferLog.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final startedAt = data['startedAt'];
    return TripTransferLog(
      id: doc.id,
      isImport: data['kind'] == 'import',
      status: (data['status'] as String?) ?? '',
      startedAt: startedAt is Timestamp ? startedAt.toDate() : null,
      durationMs: (data['durationMs'] as num?)?.toInt(),
      tripTitle: (data['tripTitle'] as String?)?.trim() ?? '',
      fileSizeBytes: (data['fileSizeBytes'] as num?)?.toInt(),
      data: data,
    );
  }

  /// The whole journal as indented JSON, to paste in a bug report.
  String toPrettyJson() {
    return const JsonEncoder.withIndent('  ').convert(
      {'id': id, ..._jsonSafe(data) as Map<String, dynamic>},
    );
  }

  static Object? _jsonSafe(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    if (value is List) return value.map(_jsonSafe).toList();
    return value;
  }
}
