import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/games/data/trip_board_game.dart';

final tripGamesRepositoryProvider = Provider<TripGamesRepository>((ref) {
  return TripGamesRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

final tripBoardGamesStreamProvider = StreamProvider.autoDispose
    .family<List<TripBoardGame>, String>((ref, tripId) {
  return ref.watch(tripGamesRepositoryProvider).watchTripBoardGames(tripId);
});

class TripGamesRepository {
  TripGamesRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> _boardGamesCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('boardGames');
  }

  Stream<List<TripBoardGame>> watchTripBoardGames(String tripId) {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      return Stream.value(const <TripBoardGame>[]);
    }
    return _boardGamesCol(cleanTripId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(TripBoardGame.fromDoc).toList());
  }

  Future<void> addBoardGame({
    required String tripId,
    required String name,
    required String linkUrl,
  }) async {
    final currentUser = auth.currentUser;
    if (currentUser == null) throw StateError('Utilisateur non connecte');

    final cleanTripId = tripId.trim();
    final cleanName = name.trim();
    final cleanLinkUrl = linkUrl.trim();
    if (cleanTripId.isEmpty) throw StateError('Voyage invalide');
    if (cleanName.isEmpty) throw StateError('Nom obligatoire');

    await _boardGamesCol(cleanTripId).add({
      'name': cleanName,
      'linkUrl': cleanLinkUrl,
      'linkPreview':
          cleanLinkUrl.isEmpty ? <String, dynamic>{} : {'status': 'loading'},
      'createdBy': currentUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateBoardGame({
    required String tripId,
    required String gameId,
    required String name,
    required String linkUrl,
    required bool resetPreview,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanGameId = gameId.trim();
    final cleanName = name.trim();
    final cleanLinkUrl = linkUrl.trim();
    if (cleanTripId.isEmpty || cleanGameId.isEmpty) {
      throw StateError('Jeu invalide');
    }
    if (cleanName.isEmpty) throw StateError('Nom obligatoire');

    final data = <String, dynamic>{
      'name': cleanName,
      'linkUrl': cleanLinkUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (resetPreview) {
      data['linkPreview'] = cleanLinkUrl.isEmpty
          ? <String, dynamic>{}
          : <String, dynamic>{'status': 'loading'};
    }

    await _boardGamesCol(cleanTripId).doc(cleanGameId).update(data);
  }

  Future<void> deleteBoardGame({
    required String tripId,
    required String gameId,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanGameId = gameId.trim();
    if (cleanTripId.isEmpty || cleanGameId.isEmpty) {
      throw StateError('Jeu invalide');
    }
    await _boardGamesCol(cleanTripId).doc(cleanGameId).delete();
  }
}
