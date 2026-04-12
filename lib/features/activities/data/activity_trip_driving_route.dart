import 'package:cloud_firestore/cloud_firestore.dart';

/// Driving route from the trip vacation address to the activity address,
/// filled by Cloud Function (`tripDrivingRoute` on the activity document).
class ActivityTripDrivingRoute {
  const ActivityTripDrivingRoute({
    required this.status,
    this.distanceMeters,
    this.durationSeconds,
    this.distanceText,
    this.durationText,
    this.detail,
    this.errorMessage,
    this.calculatedAt,
  });

  final String status;
  final int? distanceMeters;
  final int? durationSeconds;
  final String? distanceText;
  final String? durationText;
  final String? detail;
  final String? errorMessage;
  final DateTime? calculatedAt;

  static ActivityTripDrivingRoute? fromFirestore(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final status = (m['status'] as String?)?.trim() ?? '';
    if (status.isEmpty) return null;

    final dm = m['distanceMeters'];
    final ds = m['durationSeconds'];
    final calculatedRaw = m['calculatedAt'];

    return ActivityTripDrivingRoute(
      status: status,
      distanceMeters: dm is num ? dm.toInt() : null,
      durationSeconds: ds is num ? ds.toInt() : null,
      distanceText: (m['distanceText'] as String?)?.trim(),
      durationText: (m['durationText'] as String?)?.trim(),
      detail: (m['detail'] as String?)?.trim(),
      errorMessage: (m['errorMessage'] as String?)?.trim(),
      calculatedAt: switch (calculatedRaw) {
        Timestamp ts => ts.toDate(),
        _ => null,
      },
    );
  }
}
