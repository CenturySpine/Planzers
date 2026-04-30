import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';

enum MealComponentKind {
  entree,
  plat,
  dessert;

  String get firestoreValue => switch (this) {
        MealComponentKind.entree => 'entree',
        MealComponentKind.plat => 'plat',
        MealComponentKind.dessert => 'dessert',
      };

  String get labelFr => switch (this) {
        MealComponentKind.entree => 'Entree',
        MealComponentKind.plat => 'Plat',
        MealComponentKind.dessert => 'Dessert',
      };

  static MealComponentKind fromFirestore(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    return switch (normalized) {
      'entree' => MealComponentKind.entree,
      'plat' => MealComponentKind.plat,
      'dessert' => MealComponentKind.dessert,
      'autre' => MealComponentKind.plat,
      _ => MealComponentKind.plat,
    };
  }
}

enum MealMode {
  cooked,
  restaurant,
  potluck;

  String get firestoreValue => switch (this) {
        MealMode.cooked => 'cooked',
        MealMode.restaurant => 'restaurant',
        MealMode.potluck => 'potluck',
      };

  static MealMode fromFirestore(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    return switch (normalized) {
      'restaurant' => MealMode.restaurant,
      'potluck' => MealMode.potluck,
      _ => MealMode.cooked,
    };
  }
}

enum MealPotluckCategory {
  salty,
  sweet,
  soft,
  alcohol;

  String get firestoreValue => switch (this) {
        MealPotluckCategory.salty => 'salty',
        MealPotluckCategory.sweet => 'sweet',
        MealPotluckCategory.soft => 'soft',
        MealPotluckCategory.alcohol => 'alcohol',
      };

  static MealPotluckCategory fromFirestore(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    return switch (normalized) {
      'sweet' => MealPotluckCategory.sweet,
      'soft' => MealPotluckCategory.soft,
      'alcohol' => MealPotluckCategory.alcohol,
      _ => MealPotluckCategory.salty,
    };
  }
}

class MealPotluckItem {
  const MealPotluckItem({
    required this.id,
    required this.label,
    required this.addedBy,
    this.category = MealPotluckCategory.salty,
    this.quantityUnits = 1,
  });

  final String id;
  final String label;
  final String addedBy;
  final MealPotluckCategory category;
  final int quantityUnits;

  factory MealPotluckItem.fromDynamic(dynamic raw) {
    if (raw is String) {
      return MealPotluckItem(
        id: 'legacy_${raw.hashCode}',
        label: raw.trim(),
        addedBy: '',
        category: MealPotluckCategory.salty,
        quantityUnits: 1,
      );
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final label = (map['label'] as String? ?? '').trim();
      final id = (map['id'] as String? ?? '').trim();
      final addedBy = (map['addedBy'] as String? ?? '').trim();
      final quantityRaw = map['quantityUnits'];
      return MealPotluckItem(
        id: id.isEmpty ? 'potluck_${label.hashCode}' : id,
        label: label,
        addedBy: addedBy,
        category: MealPotluckCategory.fromFirestore(map['category'] as String?),
        quantityUnits: switch (quantityRaw) {
          int n when n > 0 => n,
          num n when n > 0 => n.toInt(),
          _ => 1,
        },
      );
    }
    return const MealPotluckItem(id: '', label: '', addedBy: '');
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id.trim(),
      'label': label.trim(),
      'addedBy': addedBy.trim(),
      'category': category.firestoreValue,
      'quantityUnits': quantityUnits > 0 ? quantityUnits : 1,
    };
  }

  MealPotluckItem copyWith({
    String? id,
    String? label,
    String? addedBy,
    MealPotluckCategory? category,
    int? quantityUnits,
  }) {
    return MealPotluckItem(
      id: id ?? this.id,
      label: label ?? this.label,
      addedBy: addedBy ?? this.addedBy,
      category: category ?? this.category,
      quantityUnits: quantityUnits ?? this.quantityUnits,
    );
  }
}

class MealComponentIngredient {
  const MealComponentIngredient({
    required this.catalogItemId,
    required this.label,
    required this.quantityValue,
    required this.quantityUnit,
  });

  final String catalogItemId;
  final String label;
  final double quantityValue;
  final String quantityUnit;

  factory MealComponentIngredient.fromMap(Map<String, dynamic> map) {
    final quantityRaw = map['quantityValue'];
    return MealComponentIngredient(
      catalogItemId: (map['catalogItemId'] as String? ?? '').trim(),
      label: (map['label'] as String? ?? '').trim(),
      quantityValue: switch (quantityRaw) {
        num n => n.toDouble(),
        _ => 1.0,
      },
      quantityUnit: (map['quantityUnit'] as String? ?? 'unit').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'catalogItemId': catalogItemId.trim(),
      'label': label.trim(),
      'quantityValue': quantityValue > 0 ? quantityValue : 1.0,
      'quantityUnit':
          quantityUnit.trim().isEmpty ? 'unit' : quantityUnit.trim(),
    };
  }

  MealComponentIngredient copyWith({
    String? catalogItemId,
    String? label,
    double? quantityValue,
    String? quantityUnit,
  }) {
    return MealComponentIngredient(
      catalogItemId: catalogItemId ?? this.catalogItemId,
      label: label ?? this.label,
      quantityValue: quantityValue ?? this.quantityValue,
      quantityUnit: quantityUnit ?? this.quantityUnit,
    );
  }
}

class MealComponent {
  const MealComponent({
    required this.id,
    required this.kind,
    required this.order,
    required this.ingredients,
    this.title = '',
    this.lockedBy,
  });

  final String id;
  final MealComponentKind kind;
  final String title;
  final int order;
  final List<MealComponentIngredient> ingredients;
  final String? lockedBy;

  factory MealComponent.fromMap(Map<String, dynamic> map) {
    final orderRaw = map['order'];
    final ingredientsRaw = (map['ingredients'] as List<dynamic>? ?? const []);
    return MealComponent(
      id: (map['id'] as String? ?? '').trim(),
      kind: MealComponentKind.fromFirestore(map['kind'] as String?),
      title: (map['title'] as String? ?? '').trim(),
      order: switch (orderRaw) {
        int n => n,
        num n => n.toInt(),
        _ => 0,
      },
      ingredients: ingredientsRaw
          .whereType<Map>()
          .map((row) => MealComponentIngredient.fromMap(
                Map<String, dynamic>.from(row),
              ))
          .where((i) => i.label.isNotEmpty)
          .toList(growable: false),
      lockedBy: (map['lockedBy'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['lockedBy'] as String).trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id.trim(),
      'kind': kind.firestoreValue,
      'title': title.trim(),
      'order': order,
      'ingredients': ingredients.map((i) => i.toMap()).toList(growable: false),
      'lockedBy': lockedBy?.trim(),
    };
  }

  MealComponent copyWith({
    String? id,
    MealComponentKind? kind,
    String? title,
    int? order,
    List<MealComponentIngredient>? ingredients,
    Object? lockedBy = _noLockedByChange,
  }) {
    return MealComponent(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      order: order ?? this.order,
      ingredients: ingredients ?? this.ingredients,
      lockedBy: identical(lockedBy, _noLockedByChange)
          ? this.lockedBy
          : lockedBy as String?,
    );
  }
}

/// A meal planned on a trip (Firestore: `trips/{tripId}/meals/{mealId}`).
class TripMeal {
  TripMeal({
    required this.id,
    required this.mealDateKey,
    required this.mealDayPart,
    required this.participantIds,
    this.chefParticipantId,
    required this.createdBy,
    required this.createdAt,
    this.updatedAt,
    this.notes = '',
    this.components = const [],
    this.mealMode = MealMode.cooked,
    this.restaurantUrl = '',
    this.restaurantLinkPreview = const {},
    this.potluckItems = const [],
    this.componentsUserOrdered = false,
  });

  final String id;

  /// Date in YYYY-MM-DD format (must be consistent with [TripMemberStay.dateKeyFromDateTime]).
  final String mealDateKey;
  final TripDayPart mealDayPart;

  /// List of participant user IDs. Auto-calculated from [TripMemberStay]
  /// but can be manually overridden.
  final List<String> participantIds;
  final String? chefParticipantId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String notes;
  final List<MealComponent> components;
  final MealMode mealMode;
  final String restaurantUrl;

  /// Same shape as trip/activity `linkPreview` (filled by Cloud Function).
  final Map<String, dynamic> restaurantLinkPreview;

  final List<MealPotluckItem> potluckItems;
  final bool componentsUserOrdered;

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

  static Map<String, dynamic> _previewFromFirestore(dynamic raw) {
    if (raw is! Map) return const {};
    return Map<String, dynamic>.from(raw);
  }

  factory TripMeal.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return TripMeal(
      id: doc.id,
      mealDateKey: (data['mealDateKey'] as String?)?.trim() ?? '',
      mealDayPart: tripDayPartFromFirestore(
            data['mealDayPart'] as String?,
          ) ??
          TripDayPart.midday,
      participantIds: ((data['participantIds'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString().trim())
          .where((id) => id.isNotEmpty)
          .toList(),
      chefParticipantId:
          (data['chefParticipantId'] as String?)?.trim().isEmpty ?? true
              ? null
              : (data['chefParticipantId'] as String).trim(),
      notes: (data['notes'] as String?)?.trim() ?? '',
      components: ((data['components'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((raw) => MealComponent.fromMap(Map<String, dynamic>.from(raw)))
          .toList(growable: false)
        ..sort((a, b) => a.order.compareTo(b.order)),
      mealMode: MealMode.fromFirestore(data['mealMode'] as String?),
      restaurantUrl: (data['restaurantUrl'] as String? ?? '').trim(),
      restaurantLinkPreview:
          _previewFromFirestore(data['restaurantLinkPreview']),
      potluckItems: ((data['potluckItems'] as List<dynamic>?) ?? const [])
          .map(MealPotluckItem.fromDynamic)
          .where((item) => item.label.isNotEmpty)
          .toList(growable: false),
      componentsUserOrdered: data['componentsUserOrdered'] == true,
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
      'mealDateKey': mealDateKey.trim(),
      'mealDayPart': tripDayPartToFirestore(mealDayPart),
      'participantIds': participantIds,
      'chefParticipantId': chefParticipantId,
      'notes': notes.trim(),
      'components': components.map((c) => c.toMap()).toList(growable: false),
      'mealMode': mealMode.firestoreValue,
      'restaurantUrl': restaurantUrl.trim(),
      'potluckItems': potluckItems
          .map((item) => item.toMap())
          .where((item) => (item['label'] as String).isNotEmpty)
          .toList(growable: false),
      'componentsUserOrdered': componentsUserOrdered,
      'createdBy': createdBy.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Map for updating an existing meal in Firestore.
  Map<String, dynamic> toUpdateMap() {
    return {
      'mealDateKey': mealDateKey.trim(),
      'mealDayPart': tripDayPartToFirestore(mealDayPart),
      'participantIds': participantIds,
      'chefParticipantId': chefParticipantId,
      'notes': notes.trim(),
      'components': components.map((c) => c.toMap()).toList(growable: false),
      'mealMode': mealMode.firestoreValue,
      'restaurantUrl': restaurantUrl.trim(),
      'potluckItems': potluckItems
          .map((item) => item.toMap())
          .where((item) => (item['label'] as String).isNotEmpty)
          .toList(growable: false),
      'componentsUserOrdered': componentsUserOrdered,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  TripMeal copyWith({
    String? id,
    String? mealDateKey,
    TripDayPart? mealDayPart,
    List<String>? participantIds,
    Object? chefParticipantId = _noChefParticipantIdChange,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? notes,
    List<MealComponent>? components,
    MealMode? mealMode,
    String? restaurantUrl,
    Map<String, dynamic>? restaurantLinkPreview,
    List<MealPotluckItem>? potluckItems,
    bool? componentsUserOrdered,
  }) {
    return TripMeal(
      id: id ?? this.id,
      mealDateKey: mealDateKey ?? this.mealDateKey,
      mealDayPart: mealDayPart ?? this.mealDayPart,
      participantIds: participantIds ?? this.participantIds,
      chefParticipantId:
          identical(chefParticipantId, _noChefParticipantIdChange)
              ? this.chefParticipantId
              : chefParticipantId as String?,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
      components: components ?? this.components,
      mealMode: mealMode ?? this.mealMode,
      restaurantUrl: restaurantUrl ?? this.restaurantUrl,
      restaurantLinkPreview:
          restaurantLinkPreview ?? this.restaurantLinkPreview,
      potluckItems: potluckItems ?? this.potluckItems,
      componentsUserOrdered:
          componentsUserOrdered ?? this.componentsUserOrdered,
    );
  }

  @override
  String toString() => 'TripMeal(id=$id, date=$mealDateKey, '
      'part=$mealDayPart, participants=${participantIds.length}, chef=$chefParticipantId)';
}

const Object _noChefParticipantIdChange = Object();
const Object _noLockedByChange = Object();
