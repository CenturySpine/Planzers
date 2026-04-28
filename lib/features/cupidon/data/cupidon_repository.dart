import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';

final cupidonRepositoryProvider = Provider<CupidonRepository>((ref) {
  return CupidonRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

final tripCupidonEnabledMemberIdsProvider =
    StreamProvider.autoDispose.family<Set<String>, String>((ref, tripId) {
  return ref
      .watch(cupidonRepositoryProvider)
      .watchCupidonEnabledMemberIds(tripId);
});

final myTripCupidonEnabledProvider =
    StreamProvider.autoDispose.family<bool, String>((ref, tripId) {
  return ref.watch(cupidonRepositoryProvider).watchMyTripCupidonEnabled(tripId);
});

final myCupidonLikedTargetIdsProvider =
    StreamProvider.autoDispose.family<Set<String>, String>((ref, tripId) {
  return ref.watch(cupidonRepositoryProvider).watchMyLikedTargetIds(tripId);
});

final myCupidonMatchesProvider =
    StreamProvider.autoDispose<List<CupidonMatchEntry>>((ref) {
  return ref.watch(cupidonRepositoryProvider).watchMyMatches();
});

class CupidonMatchEntry {
  const CupidonMatchEntry({
    required this.matchId,
    required this.tripId,
    required this.tripTitle,
    required this.otherMemberId,
    required this.otherMemberLabel,
    required this.otherMemberPhotoUrl,
    required this.createdAt,
  });

  final String matchId;
  final String tripId;
  final String tripTitle;
  final String otherMemberId;
  final String otherMemberLabel;
  final String otherMemberPhotoUrl;
  final DateTime createdAt;

  factory CupidonMatchEntry.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final rawCreatedAt = data['createdAt'];
    final createdAt = switch (rawCreatedAt) {
      Timestamp ts => ts.toDate(),
      _ => DateTime.fromMillisecondsSinceEpoch(0),
    };
    return CupidonMatchEntry(
      matchId: id,
      tripId: (data['tripId'] as String?)?.trim() ?? '',
      tripTitle: (data['tripTitle'] as String?)?.trim().isNotEmpty == true
          ? (data['tripTitle'] as String).trim()
          : 'Voyage',
      otherMemberId: (data['otherMemberId'] as String?)?.trim() ?? '',
      otherMemberLabel:
          (data['otherMemberLabel'] as String?)?.trim().isNotEmpty == true
              ? (data['otherMemberLabel'] as String).trim()
              : 'Utilisateur',
      otherMemberPhotoUrl:
          (data['otherMemberPhotoUrl'] as String?)?.trim().isNotEmpty == true
              ? (data['otherMemberPhotoUrl'] as String).trim()
              : '',
      createdAt: createdAt,
    );
  }
}

class CupidonRepository {
  CupidonRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  Stream<Set<String>> watchCupidonEnabledMemberIds(String tripId) {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) return Stream.value(const <String>{});
    return firestore
        .collection('trips')
        .doc(cleanTripId)
        .collection('members')
        .where('cupidonEnabled', isEqualTo: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => doc.id.trim())
              .where((id) => id.isNotEmpty)
              .toSet(),
        );
  }

  Stream<bool> watchMyTripCupidonEnabled(String tripId) {
    final uid = auth.currentUser?.uid.trim() ?? '';
    final cleanTripId = tripId.trim();
    if (uid.isEmpty || cleanTripId.isEmpty) {
      return Stream.value(false);
    }
    return firestore
        .collection('trips')
        .doc(cleanTripId)
        .collection('members')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.data()?['cupidonEnabled'] == true);
  }

  Stream<Set<String>> watchMyLikedTargetIds(String tripId) {
    final uid = auth.currentUser?.uid.trim() ?? '';
    final cleanTripId = tripId.trim();
    if (uid.isEmpty || cleanTripId.isEmpty) {
      return Stream.value(const <String>{});
    }
    return firestore
        .collection('trips')
        .doc(cleanTripId)
        .collection('cupidonLikes')
        .where('likerId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final ids = <String>{};
      for (final doc in snap.docs) {
        final targetId = (doc.data()['targetId'] as String?)?.trim() ?? '';
        if (targetId.isNotEmpty) ids.add(targetId);
      }
      return ids;
    });
  }

  Future<void> setMyTripCupidonEnabled({
    required String tripId,
    required bool enabled,
  }) async {
    final uid = auth.currentUser?.uid.trim() ?? '';
    final cleanTrip = tripId.trim();
    if (uid.isEmpty) throw StateError('Utilisateur non connecte');
    if (cleanTrip.isEmpty) throw StateError('Voyage invalide');
    final callable = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    )
        .httpsCallable('setTripCupidonEnabled');
    await callable.call(<String, dynamic>{
      'tripId': cleanTrip,
      'enabled': enabled,
    });
  }

  Future<void> setLike({
    required String tripId,
    required String targetMemberId,
    required bool isLiked,
  }) async {
    final uid = auth.currentUser?.uid.trim() ?? '';
    final cleanTrip = tripId.trim();
    final cleanTarget = targetMemberId.trim();
    if (uid.isEmpty) throw StateError('Utilisateur non connecte');
    if (cleanTrip.isEmpty || cleanTarget.isEmpty) {
      throw StateError('Parametres invalides');
    }
    final callable = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    )
        .httpsCallable('toggleTripCupidonLike');
    await callable.call(<String, dynamic>{
      'tripId': cleanTrip,
      'targetMemberId': cleanTarget,
      'isLiked': isLiked,
    });
  }

  Stream<List<CupidonMatchEntry>> watchMyMatches() {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      return Stream.value(const <CupidonMatchEntry>[]);
    }
    return firestore
        .collection('users')
        .doc(uid)
        .collection('cupidonMatches')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
      final items = snap.docs
          .map((doc) => CupidonMatchEntry.fromFirestore(doc.id, doc.data()))
          .toList(growable: false);
      return items;
    });
  }

  Future<void> deleteMyMatch(String matchId) async {
    final uid = auth.currentUser?.uid.trim() ?? '';
    final cleanMatchId = matchId.trim();
    if (uid.isEmpty) throw StateError('Utilisateur non connecte');
    if (cleanMatchId.isEmpty) throw StateError('Match invalide');
    final callable = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    )
        .httpsCallable('deleteCupidonMatch');
    await callable.call(<String, dynamic>{'matchId': cleanMatchId});
  }
}
