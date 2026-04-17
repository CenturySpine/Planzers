import 'package:cloud_firestore/cloud_firestore.dart';

class Trip {
  Trip({
    required this.id,
    required this.title,
    required this.destination,
    required this.address,
    required this.linkUrl,
    required this.ownerId,
    required this.memberIds,
    required this.createdAt,
    this.startDate,
    this.endDate,
  });

  final String id;
  final String title;
  final String destination;
  final String address;
  final String linkUrl;
  final String ownerId;
  final List<String> memberIds;
  final DateTime createdAt;
  final DateTime? startDate;
  final DateTime? endDate;

  factory Trip.fromMap(String id, Map<String, dynamic> data) {
    final createdAtRaw = data['createdAt'];
    final createdAt = switch (createdAtRaw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s) ?? DateTime.now(),
      _ => DateTime.now(),
    };

    return Trip(
      id: id,
      title: (data['title'] as String?) ?? '',
      destination: (data['destination'] as String?) ?? '',
      address: (data['address'] as String?) ?? '',
      linkUrl: (data['linkUrl'] as String?) ?? '',
      ownerId: (data['ownerId'] as String?) ?? '',
      memberIds: ((data['memberIds'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      createdAt: createdAt,
      startDate: _readDate(data['startDate']),
      endDate: _readDate(data['endDate']),
    );
  }

  Map<String, dynamic> toMap() {
    final result = <String, dynamic>{
      'title': title,
      'destination': destination,
      'address': address,
      'linkUrl': linkUrl,
      'ownerId': ownerId,
      'memberIds': memberIds,
      'createdAt': createdAt.toIso8601String(),
    };
    if (startDate != null) {
      result['startDate'] = startDate!.toIso8601String();
    }
    if (endDate != null) {
      result['endDate'] = endDate!.toIso8601String();
    }
    return result;
  }

  static DateTime? _readDate(dynamic raw) {
    return switch (raw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s),
      _ => null,
    };
  }
}
