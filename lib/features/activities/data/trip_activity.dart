import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planerz/features/activities/data/activity_trip_driving_route.dart';

/// Proposed outing / activity for a trip
/// (`trips/{tripId}/activities/{activityId}`).
class TripActivity {
  TripActivity({
    required this.id,
    required this.label,
    required this.category,
    required this.linkUrl,
    required this.address,
    required this.freeComments,
    required this.createdBy,
    required this.createdAt,
    this.done = false,
    this.plannedAt,
    this.durationMinutes,
    this.doneAt,
    this.linkPreview = const {},
    this.tripDrivingRoute,
    this.votes = const [],
  });

  final String id;
  final String label;
  final TripActivityCategory category;
  final String linkUrl;

  /// Place address for driving directions from the trip base address (optional).
  final String address;
  final String freeComments;
  final String createdBy;
  final DateTime createdAt;

  /// Whether participants consider this outing done.
  final bool done;
  final DateTime? plannedAt;

  /// Custom duration; null means the category default applies.
  final int? durationMinutes;
  final DateTime? doneAt;

  /// Same shape as trip `linkPreview` (filled by Cloud Function).
  final Map<String, dynamic> linkPreview;

  /// Driving distance/duration from trip `address` (Cloud Function).
  final ActivityTripDrivingRoute? tripDrivingRoute;

  /// UIDs of members who upvoted this suggestion.
  final List<String> votes;

  Duration get effectiveDuration =>
      Duration(minutes: durationMinutes ?? category.defaultDurationMinutes);

  DateTime? get plannedEndAt => plannedAt?.add(effectiveDuration);

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

    final doneRaw = data['done'];
    final done = doneRaw is bool
        ? doneRaw
        : doneRaw is String
            ? doneRaw.toLowerCase() == 'true'
            : false;
    final doneAtRaw = data['doneAt'];
    final doneAt = switch (doneAtRaw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s),
      _ => null,
    };
    final plannedAtRaw = data['plannedAt'];
    final plannedAt = switch (plannedAtRaw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s),
      _ => null,
    };

    return TripActivity(
      id: doc.id,
      label: (data['label'] as String?) ?? '',
      category: TripActivityCategory.fromFirestore(data['category']),
      linkUrl: (data['linkUrl'] as String?) ?? '',
      address: (data['address'] as String?) ?? '',
      freeComments: (data['freeComments'] as String?) ?? '',
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt: createdAt,
      done: done,
      plannedAt: plannedAt,
      durationMinutes: _durationFromFirestore(data['durationMinutes']),
      doneAt: done ? doneAt : null,
      linkPreview: _previewFromFirestore(data['linkPreview']),
      tripDrivingRoute:
          ActivityTripDrivingRoute.fromFirestore(data['tripDrivingRoute']),
      votes: _votesFromFirestore(data['votes']),
    );
  }

  static List<String> _votesFromFirestore(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList();
  }

  static int? _durationFromFirestore(dynamic raw) {
    if (raw is! num) return null;
    final minutes = raw.toInt();
    return minutes > 0 ? minutes : null;
  }
}

/// Upper bound for a custom duration (must match `firestore.rules`).
const int tripActivityMaxDurationMinutes = 7 * 24 * 60;

enum TripActivityCategory {
  sport,
  hiking,
  shopping,
  visit,
  restaurant,
  cafe,
  museum,
  show,
  nightlife,
  karaoke,
  games,
  beach,
  park,
  transport,
  accommodation,
  wellness,
  cooking,
  workshop,
  market,
  meeting;

  static TripActivityCategory fromFirestore(dynamic raw) {
    final s = (raw is String ? raw : raw?.toString() ?? '').trim();
    for (final e in TripActivityCategory.values) {
      if (e.firestoreValue == s) return e;
    }
    return TripActivityCategory.visit;
  }

  /// Applies until a custom duration is set: a night for accommodation,
  /// two hours for anything else.
  int get defaultDurationMinutes => switch (this) {
        TripActivityCategory.accommodation => 8 * 60,
        _ => 2 * 60,
      };

  /// Stored in Firestore.
  String get firestoreValue => switch (this) {
        TripActivityCategory.sport => 'sport',
        TripActivityCategory.hiking => 'hiking',
        TripActivityCategory.shopping => 'shopping',
        TripActivityCategory.visit => 'visit',
        TripActivityCategory.restaurant => 'restaurant',
        TripActivityCategory.cafe => 'cafe',
        TripActivityCategory.museum => 'museum',
        TripActivityCategory.show => 'show',
        TripActivityCategory.nightlife => 'nightlife',
        TripActivityCategory.karaoke => 'karaoke',
        TripActivityCategory.games => 'games',
        TripActivityCategory.beach => 'beach',
        TripActivityCategory.park => 'park',
        TripActivityCategory.transport => 'transport',
        TripActivityCategory.accommodation => 'accommodation',
        TripActivityCategory.wellness => 'wellness',
        TripActivityCategory.cooking => 'cooking',
        TripActivityCategory.workshop => 'workshop',
        TripActivityCategory.market => 'market',
        TripActivityCategory.meeting => 'meeting',
      };
}
