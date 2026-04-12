import 'package:cloud_firestore/cloud_firestore.dart';

/// Proposed outing / activity for a trip
/// (`trips/{tripId}/activities/{activityId}`).
class TripActivity {
  TripActivity({
    required this.id,
    required this.label,
    required this.category,
    required this.linkUrl,
    required this.itinerary,
    required this.freeComments,
    required this.createdBy,
    required this.createdAt,
    this.linkPreview = const {},
  });

  final String id;
  final String label;
  final TripActivityCategory category;
  final String linkUrl;
  final String itinerary;
  final String freeComments;
  final String createdBy;
  final DateTime createdAt;

  /// Same shape as trip `linkPreview` (filled by Cloud Function).
  final Map<String, dynamic> linkPreview;

  static Map<String, dynamic> _previewFromFirestore(dynamic raw) {
    if (raw is! Map) return const {};
    return Map<String, dynamic>.from(raw);
  }

  factory TripActivity.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    final createdAt = switch (createdAtRaw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s) ?? DateTime.now(),
      _ => DateTime.now(),
    };

    return TripActivity(
      id: doc.id,
      label: (data['label'] as String?) ?? '',
      category: TripActivityCategory.fromFirestore(data['category']),
      linkUrl: (data['linkUrl'] as String?) ?? '',
      itinerary: (data['itinerary'] as String?) ?? '',
      freeComments: (data['freeComments'] as String?) ?? '',
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt: createdAt,
      linkPreview: _previewFromFirestore(data['linkPreview']),
    );
  }
}

enum TripActivityCategory {
  sport,
  shopping,
  visit,
  restaurant;

  static TripActivityCategory fromFirestore(dynamic raw) {
    final s = (raw is String ? raw : raw?.toString() ?? '').trim();
    for (final e in TripActivityCategory.values) {
      if (e.firestoreValue == s) return e;
    }
    return TripActivityCategory.visit;
  }

  /// Stored in Firestore.
  String get firestoreValue => switch (this) {
        TripActivityCategory.sport => 'sport',
        TripActivityCategory.shopping => 'shopping',
        TripActivityCategory.visit => 'visit',
        TripActivityCategory.restaurant => 'restaurant',
      };
}
