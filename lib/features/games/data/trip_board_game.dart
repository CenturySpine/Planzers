import 'package:cloud_firestore/cloud_firestore.dart';

class TripBoardGame {
  TripBoardGame({
    required this.id,
    required this.name,
    required this.linkUrl,
    required this.linkPreview,
    required this.createdBy,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String linkUrl;
  final Map<String, dynamic> linkPreview;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;

  static Map<String, dynamic> _previewFromFirestore(dynamic raw) {
    if (raw is! Map) return const {};
    return Map<String, dynamic>.from(raw);
  }

  static DateTime _dateFromFirestore(dynamic raw) {
    return switch (raw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s) ?? DateTime.now(),
      _ => DateTime.now(),
    };
  }

  static DateTime? _optionalDateFromFirestore(dynamic raw) {
    return switch (raw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s),
      _ => null,
    };
  }

  factory TripBoardGame.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return TripBoardGame(
      id: doc.id,
      name: (data['name'] as String?)?.trim() ?? '',
      linkUrl: (data['linkUrl'] as String?)?.trim() ?? '',
      linkPreview: _previewFromFirestore(data['linkPreview']),
      createdBy: (data['createdBy'] as String?)?.trim() ?? '',
      createdAt: _dateFromFirestore(data['createdAt']),
      updatedAt: _optionalDateFromFirestore(data['updatedAt']),
    );
  }
}
