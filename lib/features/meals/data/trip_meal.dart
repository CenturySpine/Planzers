import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planzers/features/trips/data/trip_day_part.dart';

/// A meal planned on a trip (Firestore: `trips/{tripId}/meals/{mealId}`).
class TripMeal {
  TripMeal({
    required this.id,
    required this.name,
    required this.mealDateKey,
    required this.mealDayPart,
    required this.participantIds,
    required this.createdBy,
    required this.createdAt,
    this.updatedAt,
    this.notes = '',
  });

  final String id;
  final String name;

  /// Date in YYYY-MM-DD format (must be consistent with [TripMemberStay.dateKeyFromDateTime]).
  final String mealDateKey;
  final TripDayPart mealDayPart;

  /// List of participant user IDs. Auto-calculated from [TripMemberStay]
  /// but can be manually overridden.
  final List<String> participantIds;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String notes;

  /// Convenience accessor for participant count.
  int get participantCount => participantIds.length;

  /// Parse meal date string to DateTime at midnight local time.
  DateTime get mealDateAsDateTime {
    final parts = mealDateKey.split('-');
    if (parts.length != 3) {
      return DateTime.now();
    }
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) {
      return DateTime.now();
    }
    return DateTime(y, m, d);
  }

  /// Format day part in French for display.
  String get dayPartLabelFr => tripDayPartLabelFr(mealDayPart);

  /// Comparison: date key string, then day part sort index.
  static int _compareChronological(TripMeal a, TripMeal b) {
    final cmpDate = a.mealDateKey.compareTo(b.mealDateKey);
    if (cmpDate != 0) return cmpDate;
    return tripDayPartSortIndex(a.mealDayPart)
        .compareTo(tripDayPartSortIndex(b.mealDayPart));
  }

  /// Sort list of meals chronologically (oldest first within each date, by day part).
  static List<TripMeal> sortedChronological(List<TripMeal> meals) {
    final sorted = meals.toList();
    sorted.sort(_compareChronological);
    return sorted;
  }

  factory TripMeal.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return TripMeal(
      id: doc.id,
      name: (data['name'] as String?)?.trim() ?? '',
      mealDateKey: (data['mealDateKey'] as String?)?.trim() ?? '',
      mealDayPart: tripDayPartFromFirestore(
            data['mealDayPart'] as String?,
          ) ??
          TripDayPart.midday,
      participantIds: ((data['participantIds'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString().trim())
          .where((id) => id.isNotEmpty)
          .toList(),
      notes: (data['notes'] as String?)?.trim() ?? '',
      createdBy: (data['createdBy'] as String?)?.trim() ?? '',
      createdAt: _parseDateOrNow(data['createdAt']),
      updatedAt: _parseOptionalDate(data['updatedAt']),
    );
  }

  static DateTime _parseDateOrNow(dynamic raw) {
    final dt = switch (raw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s),
      _ => null,
    };
    return dt ?? DateTime.now();
  }

  static DateTime? _parseOptionalDate(dynamic raw) {
    return switch (raw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s),
      _ => null,
    };
  }

  /// Map for creating a new meal in Firestore.
  Map<String, dynamic> toCreateMap() {
    return {
      'name': name.trim(),
      'mealDateKey': mealDateKey.trim(),
      'mealDayPart': tripDayPartToFirestore(mealDayPart),
      'participantIds': participantIds,
      'notes': notes.trim(),
      'createdBy': createdBy.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Map for updating an existing meal in Firestore.
  Map<String, dynamic> toUpdateMap() {
    return {
      'name': name.trim(),
      'mealDateKey': mealDateKey.trim(),
      'mealDayPart': tripDayPartToFirestore(mealDayPart),
      'participantIds': participantIds,
      'notes': notes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  TripMeal copyWith({
    String? id,
    String? name,
    String? mealDateKey,
    TripDayPart? mealDayPart,
    List<String>? participantIds,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? notes,
  }) {
    return TripMeal(
      id: id ?? this.id,
      name: name ?? this.name,
      mealDateKey: mealDateKey ?? this.mealDateKey,
      mealDayPart: mealDayPart ?? this.mealDayPart,
      participantIds: participantIds ?? this.participantIds,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() => 'TripMeal(id=$id, name=$name, date=$mealDateKey, '
      'part=$mealDayPart, participants=${participantIds.length})';
}
