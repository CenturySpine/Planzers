import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/features/packing/data/packing_item.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';

final packingRepositoryProvider = Provider<PackingRepository>((ref) {
  return PackingRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// The current user's participant-slot id for a trip, or null when they are
/// not (yet) a traveler on it. The packing list is keyed by this slot id so
/// an organiser can push a list into a slot before its user has claimed it.
final myPackingParticipantIdProvider =
    Provider.autoDispose.family<String?, String>((ref, tripId) {
  return ref.watch(myTripMemberStreamProvider(tripId)).asData?.value?.id;
});

/// Activation state of the "À emporter" module for the current traveler.
final myPackingListConfigStreamProvider =
    StreamProvider.autoDispose.family<PackingListConfig, String>((ref, tripId) {
  final participantId = ref.watch(myPackingParticipantIdProvider(tripId));
  if (participantId == null) {
    return Stream.value(const PackingListConfig());
  }
  return ref
      .watch(packingRepositoryProvider)
      .watchConfig(tripId: tripId, participantId: participantId);
});

/// The current traveler's packing items, already sorted alphabetically
/// (case- and accent-insensitive), organiser and personal items mixed.
final myPackingItemsStreamProvider =
    StreamProvider.autoDispose.family<List<PackingItem>, String>((ref, tripId) {
  final participantId = ref.watch(myPackingParticipantIdProvider(tripId));
  if (participantId == null) {
    return Stream.value(const <PackingItem>[]);
  }
  return ref
      .watch(packingRepositoryProvider)
      .watchItems(tripId: tripId, participantId: participantId);
});

/// Outcome of pushing an organiser list to the other travelers.
class PackingListPushResult {
  const PackingListPushResult({
    required this.participantCount,
    required this.itemCount,
  });

  final int participantCount;
  final int itemCount;
}

class PackingRepository {
  PackingRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  DocumentReference<Map<String, dynamic>> _listRef(
    String tripId,
    String participantId,
  ) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('packingLists')
        .doc(participantId.trim());
  }

  CollectionReference<Map<String, dynamic>> _itemsRef(
    String tripId,
    String participantId,
  ) {
    return _listRef(tripId, participantId).collection('items');
  }

  Stream<PackingListConfig> watchConfig({
    required String tripId,
    required String participantId,
  }) {
    if (tripId.trim().isEmpty || participantId.trim().isEmpty) {
      return Stream.value(const PackingListConfig());
    }
    return _listRef(tripId, participantId)
        .snapshots()
        .map(PackingListConfig.fromSnapshot);
  }

  Stream<List<PackingItem>> watchItems({
    required String tripId,
    required String participantId,
  }) {
    if (tripId.trim().isEmpty || participantId.trim().isEmpty) {
      return Stream.value(const <PackingItem>[]);
    }
    return _itemsRef(tripId, participantId).snapshots().map((snap) {
      final items = snap.docs.map(PackingItem.fromDoc).toList();
      items.sort((a, b) {
        final byLabel =
            packingItemSortKey(a.label).compareTo(packingItemSortKey(b.label));
        return byLabel != 0 ? byLabel : a.id.compareTo(b.id);
      });
      return items;
    });
  }

  Future<void> setEnabled({
    required String tripId,
    required String participantId,
    required bool enabled,
  }) async {
    if (participantId.trim().isEmpty) {
      throw StateError('Voyageur invalide');
    }
    await _listRef(tripId, participantId).set(<String, dynamic>{
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> addItem({
    required String tripId,
    required String participantId,
    required String label,
  }) async {
    final cleanLabel = label.trim();
    if (cleanLabel.isEmpty) return;
    await _itemsRef(tripId, participantId).add(<String, dynamic>{
      'label': cleanLabel,
      'checked': false,
      'scope': PackingItemScope.self.value,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setChecked({
    required String tripId,
    required String participantId,
    required String itemId,
    required bool checked,
  }) async {
    await _itemsRef(tripId, participantId).doc(itemId).update(<String, dynamic>{
      'checked': checked,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Renames a personal item. Organiser items are read-only and must not be
  /// passed here.
  Future<void> updateLabel({
    required String tripId,
    required String participantId,
    required String itemId,
    required String label,
  }) async {
    final cleanLabel = label.trim();
    if (cleanLabel.isEmpty) return;
    await _itemsRef(tripId, participantId).doc(itemId).update(<String, dynamic>{
      'label': cleanLabel,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteItem({
    required String tripId,
    required String participantId,
    required String itemId,
  }) async {
    await _itemsRef(tripId, participantId).doc(itemId).delete();
  }

  /// Pushes the caller's own list to every other (non-child) traveler slot of
  /// the trip. Handled server-side because a traveler can only write their own
  /// slot. See the `pushPackingList` Cloud Function.
  Future<PackingListPushResult> pushListToParticipants({
    required String tripId,
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) throw StateError('Voyage invalide');

    final callable = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    ).httpsCallable('pushPackingList');
    final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
      'tripId': cleanTripId,
    });
    final data = Map<String, dynamic>.from(result.data);
    return PackingListPushResult(
      participantCount: (data['participantCount'] as num?)?.toInt() ?? 0,
      itemCount: (data['itemCount'] as num?)?.toInt() ?? 0,
    );
  }
}
