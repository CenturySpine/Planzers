import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';
import 'package:planerz/features/shopping/data/shopping_list_locks.dart';
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

/// Live lock flags for manual vs consolidated shopping tabs.
final tripShoppingListLocksStreamProvider =
    StreamProvider.autoDispose.family<TripShoppingListLocks, String>(
  (ref, tripId) {
    return ref.watch(shoppingRepositoryProvider).watchShoppingListLocks(tripId);
  },
);

/// Persisted consolidated list rows + category metadata (`consolidatedShoppingItems/meta`).
final tripConsolidatedShoppingListStreamProvider = StreamProvider.autoDispose
    .family<ConsolidatedListFirestorePayload, String>(
  (ref, tripId) {
    return ref.watch(shoppingRepositoryProvider).watchConsolidatedShoppingList(tripId);
  },
);

/// Reserved document id for category/summary metadata inside [kConsolidatedShoppingItemsCollection].
const String kConsolidatedShoppingMetaDocId = 'meta';

/// Subcollection under each trip for the saved consolidated shopping list.
const String kConsolidatedShoppingItemsCollection = 'consolidatedShoppingItems';

/// Thrown when a consolidated row is toggled or claimed but has no matching
/// Firestore document (list not saved yet, or row removed).
class ConsolidatedShoppingRowNotPersistedException implements Exception {
  const ConsolidatedShoppingRowNotPersistedException();

  @override
  String toString() => 'ConsolidatedShoppingRowNotPersistedException';
}

bool _isEphemeralConsolidatedShoppingItemId(String itemId) {
  final id = itemId.trim();
  if (id.isEmpty) return false;
  if (id.startsWith('consolidated_manual_')) return true;
  return RegExp(r'^consolidated_\d+$').hasMatch(id);
}

class ShoppingRepository {
  ShoppingRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> _col(String tripId) =>
      firestore.collection('trips').doc(tripId).collection('shoppingItems');

  CollectionReference<Map<String, dynamic>> _consolidatedCol(String tripId) =>
      firestore
          .collection('trips')
          .doc(tripId)
          .collection(kConsolidatedShoppingItemsCollection);

  DocumentReference<Map<String, dynamic>> _locksDoc(String tripId) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('shopping_list_locks')
        .doc(kTripShoppingListLocksDocId);
  }

  Stream<TripShoppingListLocks> watchShoppingListLocks(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(TripShoppingListLocks.defaults);
    }
    return _locksDoc(cleanId).snapshots().map((snap) {
      if (!snap.exists) return TripShoppingListLocks.defaults;
      return TripShoppingListLocks.fromMap(snap.data() ?? const {});
    });
  }

  Future<void> setShoppingListLockFlags({
    required String tripId,
    bool? manualListLocked,
    bool? consolidatedListLocked,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Utilisateur non connecte');

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) throw StateError('Voyage invalide');
    if (manualListLocked == null && consolidatedListLocked == null) return;

    await _locksDoc(cleanTripId).set(
      <String, dynamic>{
        if (manualListLocked != null) 'manualListLocked': manualListLocked,
        if (consolidatedListLocked != null)
          'consolidatedListLocked': consolidatedListLocked,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      },
      SetOptions(merge: true),
    );
  }

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

  Stream<ConsolidatedListFirestorePayload> watchConsolidatedShoppingList(
    String tripId,
  ) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(ConsolidatedListFirestorePayload.empty);
    }
    return _consolidatedCol(cleanId)
        .snapshots()
        .map(_mapConsolidatedShoppingSnapshot);
  }

  /// Replaces the entire `consolidatedShoppingItems` subcollection (metadata + rows).
  Future<void> replaceConsolidatedShoppingList({
    required String tripId,
    required List<ConsolidatedShoppingCategory> categories,
    required ConsolidatedShoppingSummary summary,
    required List<ConsolidatedFirestoreRow> rows,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Utilisateur non connecte');

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) throw StateError('Voyage invalide');

    final col = _consolidatedCol(cleanTripId);
    await _deleteAllDocumentsInCollection(col);

    if (rows.isEmpty) {
      return;
    }

    final sorted = [...rows]..sort((a, b) => a.item.order.compareTo(b.item.order));

    var batch = firestore.batch();
    var opCount = 0;

    Future<void> commitBatch() async {
      await batch.commit();
      batch = firestore.batch();
      opCount = 0;
    }

    batch.set(
      col.doc(kConsolidatedShoppingMetaDocId),
      <String, dynamic>{
        'categories': categories
            .map((c) => <String, dynamic>{
                  'id': c.id,
                  'fr': c.fr,
                  'en': c.en,
                })
            .toList(growable: false),
        'summary': summary.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      },
    );
    opCount++;

    for (final row in sorted) {
      final docRef = col.doc();
      final categoryId = row.categoryId.trim().isEmpty ? 'divers' : row.categoryId.trim();
      final claimed = row.item.claimedBy?.trim() ?? '';
      batch.set(
        docRef,
        <String, dynamic>{
          'label': row.item.label.trim(),
          'checked': row.item.checked,
          'quantityValue': row.item.quantityValue,
          'quantityUnit': row.item.quantityUnit.firestoreValue,
          'order': row.item.order,
          'categoryId': categoryId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
          if (claimed.isNotEmpty) 'claimedBy': claimed,
        },
      );
      opCount++;
      if (opCount >= 450) {
        await commitBatch();
      }
    }
    if (opCount > 0) {
      await commitBatch();
    }
  }

  Future<void> deleteConsolidatedShoppingList(String tripId) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) throw StateError('Voyage invalide');
    await _deleteAllDocumentsInCollection(_consolidatedCol(cleanTripId));
  }

  Future<void> _deleteAllDocumentsInCollection(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    const pageSize = 500;
    while (true) {
      final snap = await col.limit(pageSize).get();
      if (snap.docs.isEmpty) {
        return;
      }
      var batch = firestore.batch();
      var n = 0;
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        n++;
        if (n == 500) {
          await batch.commit();
          batch = firestore.batch();
          n = 0;
        }
      }
      if (n > 0) {
        await batch.commit();
      }
    }
  }

  ConsolidatedListFirestorePayload _mapConsolidatedShoppingSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    Map<String, dynamic>? metaData;
    final itemDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in snap.docs) {
      if (d.id == kConsolidatedShoppingMetaDocId) {
        metaData = d.data();
      } else {
        itemDocs.add(d);
      }
    }

    if (itemDocs.isEmpty) {
      return ConsolidatedListFirestorePayload.empty;
    }

    itemDocs.sort((a, b) {
      final orderA = _parseOrderField(a.data()['order']);
      final orderB = _parseOrderField(b.data()['order']);
      return orderA.compareTo(orderB);
    });

    final categories = _parseCategoriesFromMeta(metaData);
    final summary = _parseSummaryFromMeta(metaData);

    final rows = <ConsolidatedFirestoreRow>[
      for (final doc in itemDocs)
        ConsolidatedFirestoreRow(
          categoryId: _parseCategoryIdField(doc.data()['categoryId']),
          item: ShoppingItem.fromDoc(doc),
        ),
    ];

    return ConsolidatedListFirestorePayload(
      categories: categories,
      summary: summary,
      rows: rows,
    );
  }

  List<ConsolidatedShoppingCategory> _parseCategoriesFromMeta(
    Map<String, dynamic>? metaData,
  ) {
    if (metaData == null) return const [];
    final raw = metaData['categories'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => ConsolidatedShoppingCategory.fromMap(
              Map<String, dynamic>.from(m),
            ))
        .where((c) => c.id.isNotEmpty)
        .toList(growable: false);
  }

  ConsolidatedShoppingSummary _parseSummaryFromMeta(Map<String, dynamic>? metaData) {
    if (metaData == null) return ConsolidatedShoppingSummary.empty;
    final raw = metaData['summary'];
    if (raw is! Map) return ConsolidatedShoppingSummary.empty;
    return ConsolidatedShoppingSummary.fromMap(
      Map<String, dynamic>.from(raw),
    );
  }

  int _parseOrderField(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }

  String _parseCategoryIdField(Object? raw) {
    final s = (raw is String ? raw : raw?.toString() ?? '').trim();
    return s.isEmpty ? 'divers' : s;
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

  /// Updates [checked] on a saved consolidated row (`consolidatedShoppingItems/{itemId}`).
  ///
  /// Fails with [ConsolidatedShoppingRowNotPersistedException] when the id is a local-only
  /// placeholder or the document does not exist.
  Future<void> setConsolidatedItemChecked({
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
    if (cleanItemId == kConsolidatedShoppingMetaDocId) {
      throw StateError('Parametres invalides');
    }
    if (_isEphemeralConsolidatedShoppingItemId(cleanItemId)) {
      throw const ConsolidatedShoppingRowNotPersistedException();
    }

    final docRef = _consolidatedCol(cleanTripId).doc(cleanItemId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw const ConsolidatedShoppingRowNotPersistedException();
    }

    await docRef.update({
      'checked': checked,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  /// Updates [claimedBy] on a saved consolidated row (`consolidatedShoppingItems/{itemId}`).
  ///
  /// Fails with [ConsolidatedShoppingRowNotPersistedException] when the id is a local-only
  /// placeholder or the document does not exist.
  Future<void> setConsolidatedItemClaimedBy({
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
    if (cleanItemId == kConsolidatedShoppingMetaDocId) {
      throw StateError('Parametres invalides');
    }
    if (_isEphemeralConsolidatedShoppingItemId(cleanItemId)) {
      throw const ConsolidatedShoppingRowNotPersistedException();
    }

    final docRef = _consolidatedCol(cleanTripId).doc(cleanItemId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw const ConsolidatedShoppingRowNotPersistedException();
    }

    final cleanClaimedBy = claimedBy?.trim();
    await docRef.update({
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
    String mode = 'full',
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) throw StateError('Voyage invalide');

    final callable = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    ).httpsCallable('consolidateTripShoppingWithAi');
    final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
      'tripId': cleanTripId,
      'mode': mode,
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

  Map<String, dynamic> toMap() => <String, dynamic>{
        'manualOriginalLineCount': manualOriginalLineCount,
        'recipeOriginalLineCount': recipeOriginalLineCount,
      };

  static const empty = ConsolidatedShoppingSummary(
    manualOriginalLineCount: 0,
    recipeOriginalLineCount: 0,
  );
}

/// One persisted row in `trips/{tripId}/consolidatedShoppingItems/{docId}` (excluding [kConsolidatedShoppingMetaDocId]).
class ConsolidatedFirestoreRow {
  const ConsolidatedFirestoreRow({
    required this.categoryId,
    required this.item,
  });

  final String categoryId;
  final ShoppingItem item;
}

/// Snapshot of the consolidated list as stored in Firestore.
class ConsolidatedListFirestorePayload {
  const ConsolidatedListFirestorePayload({
    required this.categories,
    required this.summary,
    required this.rows,
  });

  final List<ConsolidatedShoppingCategory> categories;
  final ConsolidatedShoppingSummary summary;
  final List<ConsolidatedFirestoreRow> rows;

  static const ConsolidatedListFirestorePayload empty =
      ConsolidatedListFirestorePayload(
    categories: [],
    summary: ConsolidatedShoppingSummary.empty,
    rows: [],
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
    required this.categoryId,
    required this.manualOriginalLineCount,
    required this.recipeOriginalLineCount,
    required this.sourceItems,
  });

  final String label;
  final double quantityValue;
  final String quantityUnit;
  final ConsolidatedShoppingSourceType sourceType;

  /// Category identifier from the grocery category reference list.
  /// Falls back to `'divers'` when absent or empty.
  final String categoryId;
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
    final rawCategoryId = (map['categoryId'] as String? ?? '').trim();
    return ConsolidatedShoppingItem(
      label:
          (map['itemLabel'] as String? ?? map['label'] as String? ?? '').trim(),
      quantityValue: _parseQuantity(map['quantityValue']),
      quantityUnit: (map['quantityUnit'] as String? ?? '').trim(),
      sourceType: _parseSourceType(map['sourceType'] as String?),
      categoryId: rawCategoryId.isEmpty ? 'divers' : rawCategoryId,
      manualOriginalLineCount: _parseInt(map['manualOriginalLineCount']),
      recipeOriginalLineCount: _parseInt(map['recipeOriginalLineCount']),
      sourceItems: sourceItems,
    );
  }
}

/// A grocery category as returned by the consolidation callable.
class ConsolidatedShoppingCategory {
  const ConsolidatedShoppingCategory({
    required this.id,
    required this.fr,
    required this.en,
  });

  final String id;
  final String fr;
  final String en;

  String label(String languageCode) => languageCode == 'fr' ? fr : en;

  factory ConsolidatedShoppingCategory.fromMap(Map<String, dynamic> map) {
    return ConsolidatedShoppingCategory(
      id: (map['id'] as String? ?? '').trim(),
      fr: (map['fr'] as String? ?? '').trim(),
      en: (map['en'] as String? ?? '').trim(),
    );
  }
}

/// Combined payload returned by the consolidation callable.
class ConsolidatedShoppingResult {
  const ConsolidatedShoppingResult({
    required this.items,
    required this.summary,
    required this.categories,
  });

  final List<ConsolidatedShoppingItem> items;
  final ConsolidatedShoppingSummary summary;
  final List<ConsolidatedShoppingCategory> categories;

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

    final rawCategories = map['categories'];
    final categories = rawCategories is List
        ? rawCategories
            .whereType<Map>()
            .map((c) => ConsolidatedShoppingCategory.fromMap(
                  Map<String, dynamic>.from(c),
                ))
            .where((c) => c.id.isNotEmpty)
            .toList(growable: false)
        : const <ConsolidatedShoppingCategory>[];

    return ConsolidatedShoppingResult(
      items: items,
      summary: summary,
      categories: categories,
    );
  }
}
