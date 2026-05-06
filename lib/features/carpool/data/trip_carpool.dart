import 'package:cloud_firestore/cloud_firestore.dart';

class TripCarpool {
  TripCarpool({
    required this.id,
    required this.tripId,
    required this.createdByUserId,
    required this.driverUserId,
    required this.meetingPointAddress,
    required this.nearestTransitStop,
    required this.departureAt,
    required this.availableSeats,
    required List<String> assignedParticipantIds,
    required this.goesShopping,
    required this.createdAt,
    required this.updatedAt,
  }) : assignedParticipantIds = _normalizeAssignedParticipants(
         assignedParticipantIds,
         driverUserId,
       ) {
    if (availableSeats < 1) {
      throw ArgumentError.value(
        availableSeats,
        'availableSeats',
        'must be at least 1',
      );
    }
    if (assignedParticipantIds.length > availableSeats) {
      throw ArgumentError(
        'assignedParticipantIds cannot exceed availableSeats',
      );
    }
  }

  final String id;
  final String tripId;
  final String createdByUserId;
  final String driverUserId;
  final String meetingPointAddress;
  final String nearestTransitStop;
  final DateTime departureAt;
  final int availableSeats;
  final List<String> assignedParticipantIds;
  final bool goesShopping;
  final DateTime createdAt;
  final DateTime updatedAt;

  static List<String> _normalizeAssignedParticipants(
    List<String> rawIds,
    String driverUserId,
  ) {
    final driverId = driverUserId.trim();
    final uniqueIds = <String>{
      ...rawIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
    };
    if (driverId.isNotEmpty) {
      uniqueIds.add(driverId);
    }
    return uniqueIds.toList(growable: false);
  }

  static DateTime _readDate(dynamic raw, DateTime fallback) {
    return switch (raw) {
      Timestamp ts => ts.toDate(),
      String iso => DateTime.tryParse(iso) ?? fallback,
      _ => fallback,
    };
  }

  factory TripCarpool.fromMap({
    required String id,
    required String tripId,
    required Map<String, dynamic> data,
  }) {
    final now = DateTime.now();
    final driverUserId = (data['driverUserId'] as String? ?? '').trim();
    final assigned = ((data['assignedParticipantIds'] as List<dynamic>?) ?? const [])
        .map((entry) => entry.toString())
        .toList(growable: false);

    return TripCarpool(
      id: id,
      tripId: tripId,
      createdByUserId: (data['createdByUserId'] as String? ?? '').trim(),
      driverUserId: driverUserId,
      meetingPointAddress: (data['meetingPointAddress'] as String? ?? '').trim(),
      nearestTransitStop: (data['nearestTransitStop'] as String? ?? '').trim(),
      departureAt: _readDate(data['departureAt'], now),
      availableSeats: (data['availableSeats'] as num?)?.toInt() ?? 1,
      assignedParticipantIds: assigned,
      goesShopping: data['goesShopping'] == true,
      createdAt: _readDate(data['createdAt'], now),
      updatedAt: _readDate(data['updatedAt'], now),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'createdByUserId': createdByUserId.trim(),
      'driverUserId': driverUserId.trim(),
      'meetingPointAddress': meetingPointAddress.trim(),
      'nearestTransitStop': nearestTransitStop.trim(),
      'departureAt': Timestamp.fromDate(departureAt),
      'availableSeats': availableSeats,
      'assignedParticipantIds': assignedParticipantIds,
      'goesShopping': goesShopping,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
