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
    this.memberPublicLabels = const {},
    this.adminMemberIds = const [],
  });

  final String id;
  final String title;
  final String destination;
  final String address;
  final String linkUrl;
  final String ownerId;
  final List<String> memberIds;

  /// Co-admins (trip creator is always admin via [ownerId]).
  final List<String> adminMemberIds;
  final DateTime createdAt;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Public display strings for members (e.g. email local part), readable by all
  /// trip participants; populated by Cloud Functions / client on create.
  final Map<String, String> memberPublicLabels;

  static Map<String, String> memberPublicLabelsFromFirestore(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final key = k.toString();
      final val = (v is String ? v : v?.toString() ?? '').trim();
      if (key.isNotEmpty && val.isNotEmpty) {
        out[key] = val;
      }
    });
    return out;
  }

  static List<String> adminMemberIdsFromFirestore(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString().trim()).where((id) => id.isNotEmpty).toList();
  }

  /// Trip admins: creator plus [adminMemberIds] entries.
  bool isTripAdmin(String? userId) {
    final u = userId?.trim() ?? '';
    if (u.isEmpty) return false;
    if (u == ownerId.trim()) return true;
    return adminMemberIds.contains(u);
  }

  /// True when [memberId] has admin privileges (creator or listed co-admin).
  bool memberHasAdminRole(String memberId) {
    final id = memberId.trim();
    if (id.isEmpty) return false;
    if (id == ownerId.trim()) return true;
    return adminMemberIds.contains(id);
  }

  static DateTime? _parseOptionalDate(dynamic raw) {
    return switch (raw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s),
      _ => null,
    };
  }

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
      startDate: _parseOptionalDate(data['startDate']),
      endDate: _parseOptionalDate(data['endDate']),
      memberPublicLabels:
          memberPublicLabelsFromFirestore(data['memberPublicLabels']),
      adminMemberIds: adminMemberIdsFromFirestore(data['adminMemberIds']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'destination': destination,
      'address': address,
      'linkUrl': linkUrl,
      'ownerId': ownerId,
      'memberIds': memberIds,
      'createdAt': createdAt.toIso8601String(),
      if (startDate != null) 'startDate': startDate!.toIso8601String(),
      if (endDate != null) 'endDate': endDate!.toIso8601String(),
      if (memberPublicLabels.isNotEmpty) 'memberPublicLabels': memberPublicLabels,
      if (adminMemberIds.isNotEmpty) 'adminMemberIds': adminMemberIds,
    };
  }
}
