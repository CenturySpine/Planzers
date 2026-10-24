import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tripTransferLogsProvider =
    StreamProvider.autoDispose<List<TripTransferLog>>((ref) {
  return FirebaseFirestore.instance
      .collection('tripTransferLogs')
      .orderBy('startedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs.map(TripTransferLog.fromDoc).toList());
});

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
