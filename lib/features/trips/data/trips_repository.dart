import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/app_public_hosts.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/trips/data/invite_join_context.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_placeholder_member.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';

final tripsRepositoryProvider = Provider<TripsRepository>((ref) {
  final target = ref.watch(firebaseTargetProvider);
  final configuredBucket = switch (target) {
    FirebaseTarget.preview => 'planerz-preview.firebasestorage.app',
    FirebaseTarget.prod => 'planerz.firebasestorage.app',
  };
  final rawBucket = (Firebase.app().options.storageBucket ?? '').trim();
  final effectiveBucket = rawBucket.isEmpty ? configuredBucket : rawBucket;
  final bucketUri =
      effectiveBucket.startsWith('gs://') ? effectiveBucket : 'gs://$effectiveBucket';
  return TripsRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    storage: FirebaseStorage.instanceFor(bucket: bucketUri),
    mobileInviteBaseUri: mobileInviteBaseUriForTarget(target),
  );
});

final tripsStreamProvider = StreamProvider<List<Trip>>((ref) {
  return ref.watch(tripsRepositoryProvider).watchMyTrips();
});

/// Single trip document stream (for trip hub shell and deep links).
final tripStreamProvider =
    StreamProvider.autoDispose.family<Trip?, String>((ref, tripId) {
  return ref.watch(tripsRepositoryProvider).watchTrip(tripId);
});

class TripsRepository {
  TripsRepository({
    required this.firestore,
    required this.auth,
    required this.storage,
    required this.mobileInviteBaseUri,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseStorage storage;

  /// Used for invite links from iOS/Android/desktop native. Web uses
  /// [Uri.base.origin] so the deployed host (prod vs Vercel preview) matches.
  final Uri mobileInviteBaseUri;

  void _ensureTripGeneralPermissionForAction({
    required Trip trip,
    required String userId,
    required TripPermissionRole requiredRole,
  }) {
    final callerRole = resolveTripPermissionRole(
      trip: trip,
      userId: userId,
    );
    final isMember = trip.memberIds.contains(userId);
    if (!isMember ||
        !isTripRoleAllowed(currentRole: callerRole, minRole: requiredRole)) {
      throw StateError('Droits insuffisants pour cette action');
    }
  }

  String _generateInviteToken() {
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    final uid = auth.currentUser?.uid ?? 'anon';
    return sha256.convert('$uid-$now'.codeUnits).toString().substring(0, 32);
  }

  Stream<Trip?> watchTrip(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(null);
    }

    return firestore.collection('trips').doc(cleanId).snapshots().map((snap) {
      if (!snap.exists) {
        return null;
      }
      final data = snap.data();
      if (data == null) {
        return null;
      }
      return Trip.fromMap(snap.id, data);
    });
  }

  Stream<List<Trip>> watchMyTrips() {
    final user = auth.currentUser;
    if (user == null) {
      return Stream.value(const <Trip>[]);
    }

    return firestore
        .collection('trips')
        .where('memberIds', arrayContains: user.uid)
        .snapshots()
        .map((snapshot) {
      final trips =
          snapshot.docs.map((doc) => Trip.fromMap(doc.id, doc.data())).toList();
      trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return trips;
    });
  }

  Future<void> createTrip({
    required String title,
    required String destination,
    String address = '',
    String linkUrl = '',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final ownerEmail = user.email?.trim() ?? '';
    final ownerLabel = displayLabelFromEmail(ownerEmail);

    final data = <String, dynamic>{
      'title': title.trim(),
      'destination': destination.trim(),
      'address': address.trim(),
      'linkUrl': linkUrl.trim(),
      'ownerId': user.uid,
      'memberIds': <String>[user.uid],
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (ownerLabel.isNotEmpty) {
      data['memberPublicLabels'] = <String, dynamic>{user.uid: ownerLabel};
    }
    if (startDate != null) {
      data['startDate'] = Timestamp.fromDate(startDate);
    }
    if (endDate != null) {
      data['endDate'] = Timestamp.fromDate(endDate);
    }

    final doc = firestore.collection('trips').doc();
    final defaultGroupRef = doc.collection('expenseGroups').doc();
    final batch = firestore.batch();
    batch.set(doc, data);
    batch.set(defaultGroupRef, {
      'title': 'Commun',
      'visibleToMemberIds': <String>[user.uid],
      'isDefault': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user.uid,
    });
    await batch.commit();
  }

  Future<void> deleteTrip({
    required String tripId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final docRef = firestore.collection('trips').doc(tripId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      return;
    }

    final data = snapshot.data();
    final ownerId = (data?['ownerId'] as String?) ?? '';
    if (ownerId != user.uid) {
      throw StateError('Seul le proprietaire peut supprimer ce voyage');
    }

    final bannerPath = (data?['bannerImagePath'] as String?)?.trim() ?? '';
    if (bannerPath.isNotEmpty) {
      try {
        await storage.ref(bannerPath).delete();
      } catch (_) {}
    }

    await docRef.delete();
  }

  Future<void> updateTrip({
    required String tripId,
    required String title,
    required String destination,
    required String address,
    required String linkUrl,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final docRef = firestore.collection('trips').doc(tripId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data();
    final tripData = data ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, tripData);
    final callerRole = resolveTripPermissionRole(
      trip: trip,
      userId: user.uid,
    );
    final requiredRole = TripGeneralPermissions.fromFirestore(
      (tripData['permissions'] as Map<String, dynamic>?)?['tripGeneral'],
    ).editGeneralInfoMinRole;
    final isMember = trip.memberIds.contains(user.uid);
    if (!isMember ||
        !isTripRoleAllowed(currentRole: callerRole, minRole: requiredRole)) {
      throw StateError('Droits insuffisants pour modifier le voyage');
    }

    final update = <String, dynamic>{
      'title': title.trim(),
      'destination': destination.trim(),
      'address': address.trim(),
      'linkUrl': linkUrl.trim(),
      'startDate': startDate != null
          ? Timestamp.fromDate(startDate)
          : FieldValue.delete(),
      'endDate': endDate != null
          ? Timestamp.fromDate(endDate)
          : FieldValue.delete(),
    };

    await docRef.update(update);
  }

  /// Invite secret shared with guests (same value as the `token` query param
  /// in the invite link). Controlled by trip share permission.
  Future<String> getOrCreateInviteToken({
    required String tripId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final docRef = firestore.collection('trips').doc(tripId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.generalPermissions.shareAccessMinRole,
    );

    var inviteToken = (data['inviteToken'] as String?)?.trim() ?? '';
    if (inviteToken.isEmpty) {
      inviteToken = _generateInviteToken();
      await docRef.update({'inviteToken': inviteToken});
    }

    return inviteToken;
  }

  Future<String> getOrCreateInviteLink({
    required String tripId,
  }) async {
    final inviteToken = await getOrCreateInviteToken(tripId: tripId);

    final params = <String, String>{
      'tripId': tripId,
      'token': inviteToken,
    };

    if (kIsWeb) {
      return Uri.parse(Uri.base.origin)
          .replace(path: '/invite', queryParameters: params)
          .toString();
    }

    return mobileInviteBaseUri.replace(queryParameters: params).toString();
  }

  Future<InviteJoinContext> getInviteJoinContext({
    String? tripId,
    required String token,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw StateError('Invitation invalide');
    }

    final regionFunctions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = regionFunctions.httpsCallable('getInviteJoinContext');
    final payload = <String, dynamic>{'token': cleanToken};
    final cleanTripId = tripId?.trim() ?? '';
    if (cleanTripId.isNotEmpty) {
      payload['tripId'] = cleanTripId;
    }

    final result = await callable.call(payload);
    return _parseInviteJoinContext(result.data);
  }

  InviteJoinContext _parseInviteJoinContext(Object? raw) {
    if (raw is! Map) {
      throw StateError('Reponse serveur invalide');
    }
    final tripId = (raw['tripId'] as String?)?.trim() ?? '';
    if (tripId.isEmpty) {
      throw StateError('Reponse serveur invalide');
    }
    final tripTitle = (raw['tripTitle'] as String?)?.trim() ?? 'Voyage';
    final requires = raw['requiresPlaceholderChoice'] == true;
    final list = <InviteJoinPlaceholderOption>[];
    final phRaw = raw['placeholders'];
    if (phRaw is List) {
      for (final item in phRaw) {
        if (item is! Map) continue;
        final id = (item['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        final name = (item['displayName'] as String?)?.trim() ?? '';
        list.add(
          InviteJoinPlaceholderOption(
            id: id,
            displayName: name.isEmpty ? 'Voyageur' : name,
          ),
        );
      }
    }
    DateTime? parseIso(String? s) {
      final t = s?.trim() ?? '';
      if (t.isEmpty) return null;
      return DateTime.tryParse(t);
    }

    return InviteJoinContext(
      tripId: tripId,
      tripTitle: tripTitle,
      placeholders: list,
      requiresPlaceholderChoice: requires,
      tripStartDate: parseIso(raw['tripStartDate'] as String?),
      tripEndDate: parseIso(raw['tripEndDate'] as String?),
    );
  }

  Future<void> joinTripWithInvite({
    required String tripId,
    required String token,
    String? placeholderMemberId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw StateError('Lien d invitation invalide');
    }

    final regionFunctions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = regionFunctions.httpsCallable('joinTripWithInvite');
    final payload = <String, dynamic>{
      'tripId': tripId.trim(),
      'token': cleanToken,
    };
    final ph = placeholderMemberId?.trim();
    if (ph != null && ph.isNotEmpty) {
      payload['placeholderMemberId'] = ph;
    }
    await callable.call(payload);
  }

  /// Joins using only the invite token (same as opening the invite link).
  /// Returns the trip id for navigation.
  Future<String> joinTripWithInviteToken(
    String token, {
    String? placeholderMemberId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw StateError('Code d invitation invalide');
    }

    final regionFunctions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = regionFunctions.httpsCallable('joinTripWithInviteToken');
    final payload = <String, dynamic>{'token': cleanToken};
    final ph = placeholderMemberId?.trim();
    if (ph != null && ph.isNotEmpty) {
      payload['placeholderMemberId'] = ph;
    }
    final result = await callable.call(payload);
    final data = result.data;
    if (data is! Map) {
      throw StateError('Reponse serveur invalide');
    }
    final tripId = data['tripId'];
    if (tripId is! String || tripId.trim().isEmpty) {
      throw StateError('Reponse serveur invalide');
    }
    return tripId.trim();
  }

  /// Adds a placeholder traveler. Permission is controlled by
  /// `permissions.participants.createParticipant`.
  Future<void> addTripPlaceholderMember({
    required String tripId,
    required String displayName,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final name = displayName.trim();
    if (name.isEmpty) {
      throw StateError('Nom obligatoire');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.participantsPermissions.editPlaceholderParticipantMinRole,
    );

    final phId = generateTripPlaceholderMemberId();
    final groupsSnap =
        await tripRef.collection('expenseGroups').get();

    var batch = firestore.batch();
    var n = 0;
    batch.update(tripRef, {
      'memberIds': FieldValue.arrayUnion(<String>[phId]),
      'memberPublicLabels.$phId': name,
    });
    n++;

    for (final doc in groupsSnap.docs) {
      batch.update(doc.reference, {
        'visibleToMemberIds': FieldValue.arrayUnion(<String>[phId]),
      });
      n++;
      if (n >= 450) {
        await batch.commit();
        batch = firestore.batch();
        n = 0;
      }
    }
    if (n > 0) {
      await batch.commit();
    }
  }

  Future<void> updateTripPlaceholderMemberName({
    required String tripId,
    required String placeholderId,
    required String displayName,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanPh = placeholderId.trim();
    if (cleanTripId.isEmpty || cleanPh.isEmpty) {
      throw StateError('Parametres invalides');
    }
    if (!isTripPlaceholderMemberId(cleanPh)) {
      throw StateError('Membre invalide');
    }

    final name = displayName.trim();
    if (name.isEmpty) {
      throw StateError('Nom obligatoire');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.participantsPermissions.createParticipantMinRole,
    );

    final memberIds = ((data['memberIds'] as List<dynamic>?) ?? const [])
        .map((e) => e.toString())
        .toList();
    if (!memberIds.contains(cleanPh)) {
      throw StateError('Voyageur prevu introuvable');
    }

    await tripRef.update(<String, dynamic>{'memberPublicLabels.$cleanPh': name});
  }

  Future<void> removeTripPlaceholderMember({
    required String tripId,
    required String placeholderId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanPh = placeholderId.trim();
    if (cleanTripId.isEmpty || cleanPh.isEmpty) {
      throw StateError('Parametres invalides');
    }
    if (!isTripPlaceholderMemberId(cleanPh)) {
      throw StateError('Membre invalide');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }
    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole:
          trip.participantsPermissions.deletePlaceholderParticipantMinRole,
    );

    final regionFunctions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable =
        regionFunctions.httpsCallable('removeTripPlaceholderMember');
    await callable.call(<String, dynamic>{
      'tripId': cleanTripId,
      'placeholderId': cleanPh,
    });
  }

  /// Ensures this user's [memberPublicLabels] entry exists on the trip (email
  /// local part via Admin SDK). Safe to call after join; no-op if Cloud
  /// Function is unavailable.
  Future<void> registerMyTripMemberLabel({required String tripId}) async {
    final user = auth.currentUser;
    if (user == null) {
      return;
    }
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return;
    }

    final regionFunctions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable =
        regionFunctions.httpsCallable('registerMyTripMemberLabel');
    await callable.call(<String, dynamic>{'tripId': cleanId});
  }

  Future<void> removeMemberFromTrip({
    required String tripId,
    required String memberId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanMemberId = memberId.trim();
    if (cleanMemberId.isEmpty) {
      throw StateError('Membre invalide');
    }
    if (cleanMemberId == user.uid) {
      throw StateError('Le proprietaire ne peut pas se supprimer lui-meme');
    }
    if (isTripPlaceholderMemberId(cleanMemberId)) {
      throw StateError(
        'Retire un voyageur prévu depuis la liste des participants '
        '(icône sur l’aperçu du voyage).',
      );
    }

    final docRef = firestore.collection('trips').doc(tripId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.participantsPermissions.deleteRegisteredParticipantMinRole,
    );

    await docRef.update({
      'memberIds': FieldValue.arrayRemove(<String>[cleanMemberId]),
      'memberPublicLabels.$cleanMemberId': FieldValue.delete(),
      'adminMemberIds': FieldValue.arrayRemove(<String>[cleanMemberId]),
    });
  }

  /// Toggles co-admin for a real member (creator stays admin). Permission is
  /// controlled by `permissions.participants.toggleAdminRole`.
  Future<void> cycleTripMemberAdminRole({
    required String tripId,
    required String memberId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMemberId = memberId.trim();
    if (cleanTripId.isEmpty || cleanMemberId.isEmpty) {
      throw StateError('Parametres invalides');
    }
    if (isTripPlaceholderMemberId(cleanMemberId)) {
      throw StateError('Membre invalide');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }
    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.participantsPermissions.toggleAdminRoleMinRole,
    );

    final regionFunctions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable =
        regionFunctions.httpsCallable('cycleTripMemberAdminRole');
    await callable.call(<String, dynamic>{
      'tripId': cleanTripId,
      'memberId': cleanMemberId,
    });
  }

  /// Leaves a trip as the current user (non-owner only). Server removes the
  /// user from trip [memberIds] and strips them from all shared expenses
  /// (participantIds / paidBy) in one transaction.
  Future<void> leaveTripAsMember({required String tripId}) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final regionFunctions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = regionFunctions.httpsCallable('leaveTrip');
    await callable.call(<String, dynamic>{'tripId': cleanTripId});
  }

  Future<void> upsertTripBannerImage({
    required String tripId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }
    if (bytes.isEmpty) {
      throw StateError('Image invalide');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }
    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.generalPermissions.manageBannerMinRole,
    );

    final previousPath = (data['bannerImagePath'] as String?)?.trim() ?? '';
    final safeExt = fileExt.trim().toLowerCase().replaceAll('.', '');
    final ext = safeExt.isEmpty ? 'jpg' : safeExt;
    final objectPath =
        'trips/$cleanTripId/banner_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      _ => 'image/jpeg',
    };
    final objectRef = storage.ref(objectPath);
    await objectRef.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    final url = await objectRef.getDownloadURL();

    await tripRef.update(<String, dynamic>{
      'bannerImageUrl': url,
      'bannerImagePath': objectPath,
      'bannerUpdatedAt': FieldValue.serverTimestamp(),
    });

    if (previousPath.isNotEmpty && previousPath != objectPath) {
      try {
        await storage.ref(previousPath).delete();
      } catch (_) {}
    }
  }

  Future<void> removeTripBannerImage({required String tripId}) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }
    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.generalPermissions.manageBannerMinRole,
    );

    final path = (data['bannerImagePath'] as String?)?.trim() ?? '';
    if (path.isNotEmpty) {
      try {
        await storage.ref(path).delete();
      } catch (_) {}
    }

    await tripRef.update(<String, dynamic>{
      'bannerImageUrl': FieldValue.delete(),
      'bannerImagePath': FieldValue.delete(),
      'bannerUpdatedAt': FieldValue.delete(),
    });
  }

  Future<void> updateTripGeneralPermission({
    required String tripId,
    required TripGeneralPermissionAction action,
    required TripPermissionRole minRole,
  }) async {
    if (action == TripGeneralPermissionAction.deleteTrip) {
      throw StateError(
        'La permission de suppression du voyage est verrouillee au role proprietaire',
      );
    }

    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.generalPermissions.manageTripSettingsMinRole,
    );

    final fieldName = switch (action) {
      TripGeneralPermissionAction.editGeneralInfo => 'editGeneralInfo',
      TripGeneralPermissionAction.manageBanner => 'manageBanner',
      TripGeneralPermissionAction.shareAccess => 'shareAccess',
      TripGeneralPermissionAction.manageTripSettings => 'manageTripSettings',
      TripGeneralPermissionAction.deleteTrip => 'deleteTrip',
    };

    await tripRef.update(<String, dynamic>{
      'permissions.tripGeneral.$fieldName': minRole.toFirestore(),
    });
  }

  Future<void> resetTripGeneralPermissionsToDefaults({
    required String tripId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.generalPermissions.manageTripSettingsMinRole,
    );

    await tripRef.update(<String, dynamic>{
      'permissions.tripGeneral': TripGeneralPermissions.defaults.toFirestore(),
    });
  }

  Future<void> updateTripParticipantsPermission({
    required String tripId,
    required TripParticipantsPermissionAction action,
    required TripPermissionRole minRole,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.generalPermissions.manageTripSettingsMinRole,
    );

    final fieldName = switch (action) {
      TripParticipantsPermissionAction.createParticipant => 'createParticipant',
      TripParticipantsPermissionAction.editPlaceholderParticipant =>
        'editPlaceholderParticipant',
      TripParticipantsPermissionAction.deletePlaceholderParticipant =>
        'deletePlaceholderParticipant',
      TripParticipantsPermissionAction.deleteRegisteredParticipant =>
        'deleteRegisteredParticipant',
      TripParticipantsPermissionAction.toggleAdminRole => 'toggleAdminRole',
    };

    await tripRef.update(<String, dynamic>{
      'permissions.participants.$fieldName': minRole.toFirestore(),
    });
  }

  Future<void> resetTripParticipantsPermissionsToDefaults({
    required String tripId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.generalPermissions.manageTripSettingsMinRole,
    );

    await tripRef.update(<String, dynamic>{
      'permissions.participants': TripParticipantsPermissions.defaults.toFirestore(),
    });
  }

  Future<void> updateTripExpensesPermission({
    required String tripId,
    required TripExpensesPermissionAction action,
    required TripPermissionRole minRole,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.generalPermissions.manageTripSettingsMinRole,
    );

    final fieldName = switch (action) {
      TripExpensesPermissionAction.createExpensePost => 'createExpensePost',
      TripExpensesPermissionAction.editExpensePost => 'editExpensePost',
      TripExpensesPermissionAction.deleteExpensePost => 'deleteExpensePost',
      TripExpensesPermissionAction.createExpense => 'createExpense',
      TripExpensesPermissionAction.editExpense => 'editExpense',
      TripExpensesPermissionAction.deleteExpense => 'deleteExpense',
    };

    await tripRef.update(<String, dynamic>{
      'permissions.expenses.$fieldName': minRole.toFirestore(),
    });
  }

  Future<void> resetTripExpensesPermissionsToDefaults({
    required String tripId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final snapshot = await tripRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(snapshot.id, data);
    _ensureTripGeneralPermissionForAction(
      trip: trip,
      userId: user.uid,
      requiredRole: trip.generalPermissions.manageTripSettingsMinRole,
    );

    await tripRef.update(<String, dynamic>{
      'permissions.expenses': TripExpensesPermissions.defaults.toFirestore(),
    });
  }
}
