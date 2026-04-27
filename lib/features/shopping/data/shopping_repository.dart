import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
