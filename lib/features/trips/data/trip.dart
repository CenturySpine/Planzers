import 'package:cloud_firestore/cloud_firestore.dart';

class Trip {
  Trip({
    required this.id,
    required this.title,
    required this.destination,
    required this.linkUrl,
    required this.ownerId,
    required this.memberIds,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String destination;
  final String linkUrl;
  final String ownerId;
  final List<String> memberIds;
  final DateTime createdAt;

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
      linkUrl: (data['linkUrl'] as String?) ?? '',
      ownerId: (data['ownerId'] as String?) ?? '',
      memberIds: ((data['memberIds'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'destination': destination,
      'linkUrl': linkUrl,
      'ownerId': ownerId,
      'memberIds': memberIds,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
