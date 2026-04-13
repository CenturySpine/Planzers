import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/rooms/data/trip_room.dart';

final roomsRepositoryProvider = Provider<RoomsRepository>((ref) {
  return RoomsRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

final tripRoomsStreamProvider =
    StreamProvider.autoDispose.family<List<TripRoom>, String>((ref, tripId) {
  return ref.watch(roomsRepositoryProvider).watchTripRooms(tripId);
});

class RoomsRepository {
  RoomsRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> _roomsCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('rooms');
  }

  Stream<List<TripRoom>> watchTripRooms(String tripId) {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      return Stream.value(const <TripRoom>[]);
    }

    return _roomsCol(cleanTripId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(TripRoom.fromDoc).toList());
  }

  Future<void> addRoom({
    required String tripId,
    required String name,
    required List<TripRoomBed> beds,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw StateError('Nom de chambre obligatoire');
    }
    if (beds.isEmpty) {
      throw StateError('Ajoute au moins un lit');
    }

    _validateBedsAssignments(beds);

    await _roomsCol(cleanTripId).add({
      'name': cleanName,
      'beds': beds.map((b) => b.toMap()).toList(),
      'assignedMemberIds': _roomAssignedFromBeds(beds),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user.uid,
    });
  }

  Future<void> updateRoom({
    required String tripId,
    required String roomId,
    required String name,
    required List<TripRoomBed> beds,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }
    final cleanTripId = tripId.trim();
    final cleanRoomId = roomId.trim();
    if (cleanTripId.isEmpty || cleanRoomId.isEmpty) {
      throw StateError('Parametres invalides');
    }
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw StateError('Nom de chambre obligatoire');
    }
    if (beds.isEmpty) {
      throw StateError('Ajoute au moins un lit');
    }
    _validateBedsAssignments(beds);

    await _roomsCol(cleanTripId).doc(cleanRoomId).update({
      'name': cleanName,
      'beds': beds.map((b) => b.toMap()).toList(),
      'assignedMemberIds': _roomAssignedFromBeds(beds),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  Future<void> deleteRoom({
    required String tripId,
    required String roomId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }
    final cleanTripId = tripId.trim();
    final cleanRoomId = roomId.trim();
    if (cleanTripId.isEmpty || cleanRoomId.isEmpty) {
      throw StateError('Parametres invalides');
    }
    await _roomsCol(cleanTripId).doc(cleanRoomId).delete();
  }

  void _validateBedsAssignments(List<TripRoomBed> beds) {
    final usedMembers = <String>{};
    for (final bed in beds) {
      final assigned = bed.assignedMemberIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (assigned.length > bed.capacity) {
        throw StateError('La capacité d un lit est dépassée');
      }
      for (final memberId in assigned) {
        if (!usedMembers.add(memberId)) {
          throw StateError('Un voyageur ne peut être affecté qu à un lit');
        }
      }
    }
  }

  List<String> _roomAssignedFromBeds(List<TripRoomBed> beds) {
    final out = <String>{};
    for (final bed in beds) {
      out.addAll(
        bed.assignedMemberIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty),
      );
    }
    return out.toList();
  }
}
