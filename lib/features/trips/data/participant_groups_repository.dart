import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/trips/data/participant_group.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';

final participantGroupsRepositoryProvider =
    Provider<ParticipantGroupsRepository>((ref) {
  return ParticipantGroupsRepository(firestore: FirebaseFirestore.instance);
});

/// Stream of [ParticipantGroup] documents for a trip.
final tripParticipantGroupsStreamProvider =
    StreamProvider.autoDispose.family<List<ParticipantGroup>, String>((ref, tripId) {
  return ref
      .watch(participantGroupsRepositoryProvider)
      .streamGroups(tripId);
});

/// Display labels for participant groups, keyed by group ID.
final tripParticipantGroupLabelsProvider =
    Provider.autoDispose.family<Map<String, String>, String>((ref, tripId) {
  final groups =
      ref.watch(tripParticipantGroupsStreamProvider(tripId)).asData?.value ?? [];
  return {for (final g in groups) g.id: g.label.isNotEmpty ? g.label : g.id};
});

/// Merged labels for all expense billing units (TripMembers + ParticipantGroups).
///
/// Lookup priority: participant first, then group — matching [resolveUnit] in the backend.
/// Use this provider for any expense/balance/suggestion label resolution.
final tripExpenseUnitLabelsProvider =
    Provider.autoDispose.family<Map<String, String>, String>((ref, tripId) {
  final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(tripId));
  final groupLabels = ref.watch(tripParticipantGroupLabelsProvider(tripId));
  return {...groupLabels, ...memberLabels};
});

/// The billing unit ID for the current user in a given trip.
///
/// Returns the group ID if the user's member belongs to a group; otherwise
/// returns the member's own ID.
final viewerBillingUnitIdProvider =
    Provider.autoDispose.family<String?, String>((ref, tripId) {
  final myMember =
      ref.watch(myTripMemberStreamProvider(tripId)).asData?.value;
  if (myMember == null) return null;
  final groups =
      ref.watch(tripParticipantGroupsStreamProvider(tripId)).asData?.value ?? [];
  for (final g in groups) {
    if (g.memberIds.contains(myMember.id)) return g.id;
  }
  return myMember.id;
});

class ParticipantGroupsRepository {
  ParticipantGroupsRepository({required this.firestore});

  final FirebaseFirestore firestore;

  CollectionReference<Map<String, dynamic>> _groupsRef(String tripId) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('participantGroups');
  }

  Stream<List<ParticipantGroup>> streamGroups(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) return const Stream.empty();
    return _groupsRef(cleanId).snapshots().map(
          (snap) => snap.docs
              .map((doc) => ParticipantGroup.fromDoc(doc))
              .toList(),
        );
  }

  Future<void> createGroup({
    required String tripId,
    required String label,
    required List<String> memberIds,
    required double parts,
  }) async {
    final group = ParticipantGroup(
      id: '',
      label: label.trim(),
      memberIds: memberIds,
      parts: parts,
    );
    await _groupsRef(tripId.trim()).add(group.toCreateMap());
  }

  Future<void> updateGroup({
    required String tripId,
    required String groupId,
    required String label,
    required List<String> memberIds,
    required double parts,
  }) async {
    final group = ParticipantGroup(
      id: groupId,
      label: label.trim(),
      memberIds: memberIds,
      parts: parts,
    );
    await _groupsRef(tripId.trim()).doc(groupId.trim()).update(group.toUpdateMap());
  }

  Future<void> deleteGroup({
    required String tripId,
    required String groupId,
  }) async {
    await _groupsRef(tripId.trim()).doc(groupId.trim()).delete();
  }

  /// Returns true if [groupId] appears in any expense of the trip
  /// (paidBy, participantIds, or participantShares keys).
  Future<bool> isGroupReferencedInExpenses({
    required String tripId,
    required String groupId,
  }) async {
    final cleanGroupId = groupId.trim();
    final expensesSnap = await firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('expenses')
        .get();
    for (final doc in expensesSnap.docs) {
      final data = doc.data();
      final paidBy = (data['paidBy'] as String?)?.trim() ?? '';
      if (paidBy == cleanGroupId) return true;
      final participantIds = ((data['participantIds'] as List<dynamic>?) ?? [])
          .map((e) => e.toString().trim())
          .toList();
      if (participantIds.contains(cleanGroupId)) return true;
      final shares = data['participantShares'];
      if (shares is Map && shares.containsKey(cleanGroupId)) return true;
    }
    return false;
  }
}
