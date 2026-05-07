import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';

final shoppingRepositoryProvider = Provider<ShoppingRepository>((ref) {
  return ShoppingRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Live shopping list for a trip, ordered by creation time.
final tripShoppingItemsStreamProvider =
    StreamProvider.autoDispose.family<List<ShoppingItem>, String>(
        (ref, tripId) {
  return ref
      .watch(shoppingRepositoryProvider)
      .watchShoppingItems(tripId);
});

class ShoppingRepository {
  ShoppingRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> _col(String tripId) =>
      firestore.collection('trips').doc(tripId).collection('shoppingItems');

  Future<Trip> _loadTrip(String tripId) async {
    final snap = await firestore.collection('trips').doc(tripId).get();
    if (!snap.exists) {
      throw StateError('Voyage introuvable');
    }
    return Trip.fromMap(snap.id, snap.data() ?? const <String, dynamic>{});
  }

  Stream<List<ShoppingItem>> watchShoppingItems(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(const <ShoppingItem>[]);
    }
    return _col(cleanId)
        .orderBy('order', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(ShoppingItem.fromDoc).toList());
  }

  Future<String> addItem({
    required String tripId,
    required String label,
    double quantityValue = 1.0,
    ShoppingUnit quantityUnit = ShoppingUnit.unit,
    required int order,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Utilisateur non connecte');

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) throw StateError('Voyage invalide');

    final doc = await _col(cleanTripId).add({
      'label': label.trim(),
      'checked': false,
      'quantityValue': quantityValue,
      'quantityUnit': quantityUnit.firestoreValue,
      'order': order,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user.uid,
    });
    return doc.id;
  }

  Future<void> updateItem({
    required String tripId,
    required String itemId,
    required String label,
    required bool checked,
    required double quantityValue,
    required ShoppingUnit quantityUnit,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Utilisateur non connecte');

    final cleanTripId = tripId.trim();
    final cleanItemId = itemId.trim();
    if (cleanTripId.isEmpty || cleanItemId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    await _col(cleanTripId).doc(cleanItemId).update({
      'label': label.trim(),
      'checked': checked,
      'quantityValue': quantityValue,
      'quantityUnit': quantityUnit.firestoreValue,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  Future<void> setChecked({
    required String tripId,
    required String itemId,
    required bool checked,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Utilisateur non connecte');

    final cleanTripId = tripId.trim();
    final cleanItemId = itemId.trim();
    if (cleanTripId.isEmpty || cleanItemId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    await _col(cleanTripId).doc(cleanItemId).update({
      'checked': checked,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  Future<void> setClaimedBy({
    required String tripId,
    required String itemId,
    String? claimedBy,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Utilisateur non connecte');

    final cleanTripId = tripId.trim();
    final cleanItemId = itemId.trim();
    if (cleanTripId.isEmpty || cleanItemId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    final cleanClaimedBy = claimedBy?.trim();
    await _col(cleanTripId).doc(cleanItemId).update({
      'claimedBy': (cleanClaimedBy == null || cleanClaimedBy.isEmpty)
          ? FieldValue.delete()
          : cleanClaimedBy,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  Future<void> deleteItem({
    required String tripId,
    required String itemId,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Utilisateur non connecte');

    final cleanTripId = tripId.trim();
    final cleanItemId = itemId.trim();
    if (cleanTripId.isEmpty || cleanItemId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    await _col(cleanTripId).doc(cleanItemId).delete();
  }

  /// Asks the backend to consolidate the trip shopping list with AI-driven
  /// merging. The callable is read-only: it does not mutate any data.
  Future<ConsolidatedShoppingResult> consolidateWithAi({
    required String tripId,
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) throw StateError('Voyage invalide');

    final callable = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    ).httpsCallable('consolidateTripShoppingWithAi');
    final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
      'tripId': cleanTripId,
    });
    return ConsolidatedShoppingResult.fromMap(
      Map<String, dynamic>.from(result.data),
    );
  }

  Future<int> deleteCheckedItems({
    required String tripId,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Utilisateur non connecte');

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) throw StateError('Voyage invalide');

    final trip = await _loadTrip(cleanTripId);
    final callerRole = resolveTripPermissionRole(
      trip: trip,
      userId: user.uid,
    );
    final canDeleteChecked = isTripRoleAllowed(
      currentRole: callerRole,
      minRole: trip.shoppingPermissions.deleteCheckedItemsMinRole,
    );
    if (!canDeleteChecked) {
      throw StateError('Droits insuffisants pour supprimer les éléments cochés');
    }

    final checkedSnapshot = await _col(cleanTripId)
        .where('checked', isEqualTo: true)
        .get();

    if (checkedSnapshot.docs.isEmpty) return 0;

    final batch = firestore.batch();
    for (final doc in checkedSnapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    return checkedSnapshot.docs.length;
  }
}

/// Origin of a consolidated row.
enum ConsolidatedShoppingSourceType { manual, recipe, mixed }

ConsolidatedShoppingSourceType _parseSourceType(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'manual':
      return ConsolidatedShoppingSourceType.manual;
    case 'recipe':
      return ConsolidatedShoppingSourceType.recipe;
    case 'mixed':
    default:
      return ConsolidatedShoppingSourceType.mixed;
  }
}

double _parseQuantity(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim()) ?? 0.0;
  return 0.0;
}

int _parseInt(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? 0;
  return 0;
}

/// Aggregated input counts as reported by the AI.
class ConsolidatedShoppingSummary {
  const ConsolidatedShoppingSummary({
    required this.manualOriginalLineCount,
    required this.recipeOriginalLineCount,
  });

  final int manualOriginalLineCount;
  final int recipeOriginalLineCount;

  factory ConsolidatedShoppingSummary.fromMap(Map<String, dynamic> map) {
    return ConsolidatedShoppingSummary(
      manualOriginalLineCount: _parseInt(map['manualOriginalLineCount']),
      recipeOriginalLineCount: _parseInt(map['recipeOriginalLineCount']),
    );
  }

  static const empty = ConsolidatedShoppingSummary(
    manualOriginalLineCount: 0,
    recipeOriginalLineCount: 0,
  );
}

/// Original input line that contributed to a `mixed` consolidated row.
class ConsolidatedShoppingSourceItem {
  const ConsolidatedShoppingSourceItem({
    required this.source,
    required this.originalLabel,
    required this.originalQuantityValue,
    required this.originalQuantityUnit,
  });

  /// 'manual' or 'recipe'.
  final String source;
  final String originalLabel;
  final double originalQuantityValue;
  final String originalQuantityUnit;

  factory ConsolidatedShoppingSourceItem.fromMap(Map<String, dynamic> map) {
    return ConsolidatedShoppingSourceItem(
      source: (map['source'] as String? ?? '').trim().toLowerCase(),
      originalLabel: (map['originalLabel'] as String? ?? '').trim(),
      originalQuantityValue: _parseQuantity(map['originalQuantityValue']),
      originalQuantityUnit:
          (map['originalQuantityUnit'] as String? ?? '').trim(),
    );
  }
}

/// Read-only consolidation row returned by the AI callable for display only.
class ConsolidatedShoppingItem {
  const ConsolidatedShoppingItem({
    required this.label,
    required this.quantityValue,
    required this.quantityUnit,
    required this.sourceType,
    required this.manualOriginalLineCount,
    required this.recipeOriginalLineCount,
    required this.sourceItems,
  });

  final String label;
  final double quantityValue;
  final String quantityUnit;
  final ConsolidatedShoppingSourceType sourceType;
  final int manualOriginalLineCount;
  final int recipeOriginalLineCount;

  /// Original lines that contributed to this consolidated row. Only populated
  /// when [sourceType] is `mixed`.
  final List<ConsolidatedShoppingSourceItem> sourceItems;

  factory ConsolidatedShoppingItem.fromMap(Map<String, dynamic> map) {
    final rawSources = map['sourceItems'];
    final sourceItems = rawSources is List
        ? rawSources
            .whereType<Map>()
            .map((row) => ConsolidatedShoppingSourceItem.fromMap(
                  Map<String, dynamic>.from(row),
                ))
            .toList(growable: false)
        : const <ConsolidatedShoppingSourceItem>[];
    return ConsolidatedShoppingItem(
      label:
          (map['itemLabel'] as String? ?? map['label'] as String? ?? '').trim(),
      quantityValue: _parseQuantity(map['quantityValue']),
      quantityUnit: (map['quantityUnit'] as String? ?? '').trim(),
      sourceType: _parseSourceType(map['sourceType'] as String?),
      manualOriginalLineCount: _parseInt(map['manualOriginalLineCount']),
      recipeOriginalLineCount: _parseInt(map['recipeOriginalLineCount']),
      sourceItems: sourceItems,
    );
  }
}

/// Combined payload returned by the consolidation callable.
class ConsolidatedShoppingResult {
  const ConsolidatedShoppingResult({
    required this.items,
    required this.summary,
  });

  final List<ConsolidatedShoppingItem> items;
  final ConsolidatedShoppingSummary summary;

  factory ConsolidatedShoppingResult.fromMap(Map<String, dynamic> map) {
    final rawItems = map['consolidatedItems'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((row) => ConsolidatedShoppingItem.fromMap(
                  Map<String, dynamic>.from(row),
                ))
            .toList(growable: false)
        : const <ConsolidatedShoppingItem>[];

    final rawSummary = map['summary'];
    final summary = rawSummary is Map
        ? ConsolidatedShoppingSummary.fromMap(
            Map<String, dynamic>.from(rawSummary),
          )
        : ConsolidatedShoppingSummary.empty;

    return ConsolidatedShoppingResult(items: items, summary: summary);
  }
}
