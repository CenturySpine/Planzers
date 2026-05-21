import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/features/trips/data/invite_join_context.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
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
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseStorage storage;
  final Set<String> _permissionsBackfillInFlight = <String>{};

  Map<String, dynamic> _defaultPermissionsFirestoreMap() {
    return <String, dynamic>{
      'tripGeneral': TripGeneralPermissions.defaults.toFirestore(),
      'participants': TripParticipantsPermissions.defaults.toFirestore(),
      'expenses': TripExpensesPermissions.defaults.toFirestore(),
      'activities': TripActivitiesPermissions.defaults.toFirestore(),
      'meals': TripMealsPermissions.defaults.toFirestore(),
      'shopping': TripShoppingPermissions.defaults.toFirestore(),
      'carpool': TripCarpoolPermissions.defaults.toFirestore(),
    };
  }

  bool _hasPermissionsBlock(Map<String, dynamic> data) {
    final raw = data['permissions'];
    if (raw is! Map) return false;
    return raw.containsKey('tripGeneral') &&
        raw.containsKey('participants') &&
        raw.containsKey('expenses') &&
        raw.containsKey('activities') &&
        raw.containsKey('meals') &&
        raw.containsKey('shopping') &&
        raw.containsKey('carpool');
  }

  void _ensurePermissionsBlockOnFirstLoad({
    required String tripId,
    required Map<String, dynamic> data,
  }) {
    if (_hasPermissionsBlock(data)) {
      return;
    }
    if (_permissionsBackfillInFlight.contains(tripId)) {
      return;
    }
    _permissionsBackfillInFlight.add(tripId);
    unawaited(() async {
      try {
        final regionFunctions = FirebaseFunctions.instanceFor(
          region: kFirebaseFunctionsRegion,
        );
        final callable =
            regionFunctions.httpsCallable('backfillLegacyTripPermissions');
        await callable.call(<String, dynamic>{
          'tripId': tripId,
        });
      } catch (_) {
        // Best-effort migration from legacy trips; keep read flow resilient.
      } finally {
        _permissionsBackfillInFlight.remove(tripId);
      }
    }());
  }

  void _ensureTripGeneralPermissionForAction({
    required Trip trip,
    required String userId,
    required TripPermissionRole requiredRole,
  }) {
    final callerRole = resolveTripPermissionRole(
      trip: trip,
      userId: userId,
    );
    final isMember = trip.memberUserIds.contains(userId);
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
      _ensurePermissionsBlockOnFirstLoad(tripId: snap.id, data: data);
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
        .where('memberUserIds', arrayContains: user.uid)
        .snapshots()
        .map((snapshot) {
      final trips = snapshot.docs.map((doc) {
        final data = doc.data();
        _ensurePermissionsBlockOnFirstLoad(tripId: doc.id, data: data);
        return Trip.fromMap(doc.id, data);
      }).toList();
      trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return trips;
    });
  }

  Future<void> createTrip({
    required String title,
    required String destination,
    required String creatorName,
    String address = '',
    String linkUrl = '',
    DateTime? startDate,
    DateTime? endDate,
    TripDayPart? tripStartDayPart,
    TripDayPart? tripEndDayPart,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final data = <String, dynamic>{
      'title': title.trim(),
      'destination': destination.trim(),
      'address': address.trim(),
      'linkUrl': linkUrl.trim(),
      'cupidonModeEnabled': true,
      'ownerId': user.uid,
      'memberUserIds': <String>[user.uid],
      'permissions': _defaultPermissionsFirestoreMap(),
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (startDate != null) {
      final d = DateTime(startDate.year, startDate.month, startDate.day);
      data['startDate'] = Timestamp.fromDate(d);
      data['tripStartDayPart'] = tripDayPartToFirestore(
        tripStartDayPart ?? TripDayPart.evening,
      );
    }
    if (endDate != null) {
      final d = DateTime(endDate.year, endDate.month, endDate.day);
      data['endDate'] = Timestamp.fromDate(d);
      data['tripEndDayPart'] = tripDayPartToFirestore(
        tripEndDayPart ?? TripDayPart.morning,
      );
    }

    final doc = firestore.collection('trips').doc();
    await doc.set(data);

    // Create the creator's participant document first to get its stable ID.
    // Firestore rules for expense groups read the parent trip document (already created above).
    final defaultStay = TripMemberStay.defaultForInviteContext(
      tripStartDate: startDate,
      tripEndDate: endDate,
    );
    final participantRef = await doc.collection('participants').add({
      'participantName': creatorName.trim(),
      'userId': user.uid,
      ...defaultStay.toFirestoreMap(),
      'cupidonEnabled': false,
      'phoneVisibility': 'nobody',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final defaultGroupRef = doc.collection('expenseGroups').doc();
    await defaultGroupRef.set({
      'title': 'Commun',
      'visibleToMemberIds': <String>[participantRef.id],
      'isDefault': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user.uid,
    });
  }

  Future<void> deleteTrip({
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
    final regionFunctions = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    );
    final callable = regionFunctions.httpsCallable('deleteTripCascade');
    await callable.call(<String, dynamic>{'tripId': cleanTripId});
  }

  Future<void> updateTrip({
    required String tripId,
    required String title,
    required String destination,
    required String address,
    required String linkUrl,
    DateTime? startDate,
    DateTime? endDate,
    TripDayPart? tripStartDayPart,
    TripDayPart? tripEndDayPart,
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
    final isMember = trip.memberUserIds.contains(user.uid);
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
          ? Timestamp.fromDate(
              DateTime(startDate.year, startDate.month, startDate.day),
            )
          : FieldValue.delete(),
      'endDate': endDate != null
          ? Timestamp.fromDate(
              DateTime(endDate.year, endDate.month, endDate.day),
            )
          : FieldValue.delete(),
    };

    if (startDate == null) {
      update['tripStartDayPart'] = FieldValue.delete();
    } else {
      update['tripStartDayPart'] = tripDayPartToFirestore(
        tripStartDayPart ?? TripDayPart.evening,
      );
    }
    if (endDate == null) {
      update['tripEndDayPart'] = FieldValue.delete();
    } else {
      update['tripEndDayPart'] = tripDayPartToFirestore(
        tripEndDayPart ?? TripDayPart.morning,
      );
    }

    await docRef.update(update);
  }

  Future<void> updateTripGeneralSettings({
    required String tripId,
    required String photosStorageUrl,
    required bool cupidonModeEnabled,
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
    if (!trip.memberHasAdminRole(user.uid)) {
      throw StateError('Droits insuffisants pour modifier ces reglages');
    }

    await tripRef.update(<String, dynamic>{
      'photosStorageUrl': photosStorageUrl.trim(),
      'cupidonModeEnabled': cupidonModeEnabled,
    });
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

    final regionFunctions = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    );
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
    final requires = raw['requiresParticipantChoice'] == true;
    final list = <InviteJoinParticipantOption>[];
    final participantsRaw = raw['participants'];
    if (participantsRaw is List) {
      for (final item in participantsRaw) {
        if (item is! Map) continue;
        final id = (item['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        final name = (item['displayName'] as String?)?.trim() ?? '';
        list.add(
          InviteJoinParticipantOption(
            id: id,
            displayName: name.isEmpty ? 'Voyageur' : name,
          ),
        );
      }
    }
    DateTime? parseIso(String? s) {
      final t = s?.trim() ?? '';
      if (t.isEmpty) return null;
      final parsed = DateTime.tryParse(t);
      if (parsed == null) return null;
      // Normalize to local calendar day to avoid off-by-one in date pickers.
      return parsed.toLocal();
    }

    return InviteJoinContext(
      tripId: tripId,
      tripTitle: tripTitle,
      participants: list,
      requiresParticipantChoice: requires,
      cupidonModeEnabled: raw['cupidonModeEnabled'] != false,
      tripStartDate: parseIso(raw['tripStartDate'] as String?),
      tripEndDate: parseIso(raw['tripEndDate'] as String?),
    );
  }

  Future<void> joinTripWithInvite({
    required String tripId,
    required String token,
    String? participantId,
    String? participantName,
    bool bypassParticipantChoice = false,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw StateError('Lien d invitation invalide');
    }

    final regionFunctions = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    );
    final callable = regionFunctions.httpsCallable('joinTripWithInvite');
    final payload = <String, dynamic>{
      'tripId': tripId.trim(),
      'token': cleanToken,
    };
    final pid = participantId?.trim();
    if (pid != null && pid.isNotEmpty) {
      payload['participantId'] = pid;
    }
    if (bypassParticipantChoice) {
      payload['bypassParticipantChoice'] = true;
      final name = participantName?.trim() ?? '';
      if (name.isNotEmpty) {
        payload['participantName'] = name;
      }
    }
    await callable.call(payload);
  }

  /// Adds a participant slot. Permission controlled by
  /// `permissions.participants.createParticipant`.
  Future<void> addTripParticipant({
    required String tripId,
    required String participantName,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final name = participantName.trim();
    if (name.isEmpty) {
      throw StateError('Nom obligatoire');
    }

    final regionFunctions = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    );
    final callable = regionFunctions.httpsCallable('addTripParticipant');
    await callable.call(<String, dynamic>{
      'tripId': cleanTripId,
      'participantName': name,
    });
  }

  Future<void> updateTripParticipantName({
    required String tripId,
    required String participantId,
    required String participantName,
    required bool useProfileName,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanPid = participantId.trim();
    if (cleanTripId.isEmpty || cleanPid.isEmpty) {
      throw StateError('Parametres invalides');
    }

    final name = participantName.trim();
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

    final participantRef = firestore
        .collection('trips')
        .doc(cleanTripId)
        .collection('participants')
        .doc(cleanPid);
    final participantSnap = await participantRef.get();
    final participantUserId =
        (participantSnap.data() ?? const <String, dynamic>{})['userId']
            as String?;
    final isOwnParticipant = participantUserId?.trim() == user.uid;

    if (!isOwnParticipant) {
      _ensureTripGeneralPermissionForAction(
        trip: trip,
        userId: user.uid,
        requiredRole: trip.participantsPermissions.manageParticipantsMinRole,
      );
    }

    await participantRef.update(<String, dynamic>{
      'participantName': name,
      'useProfileName': useProfileName,
    });
  }

  Future<void> removeTripParticipant({
    required String tripId,
    required String participantId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanPid = participantId.trim();
    if (cleanTripId.isEmpty || cleanPid.isEmpty) {
      throw StateError('Parametres invalides');
    }

    final regionFunctions = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    );
    final callable = regionFunctions.httpsCallable('removeTripParticipant');
    await callable.call(<String, dynamic>{
      'tripId': cleanTripId,
      'participantId': cleanPid,
    });
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

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final regionFunctions = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    );
    final callable =
        regionFunctions.httpsCallable('removeTripRegisteredMember');
    await callable.call(<String, dynamic>{
      'tripId': cleanTripId,
      'memberId': cleanMemberId,
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

    final regionFunctions = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    );
    final callable =
        regionFunctions.httpsCallable('cycleTripMemberAdminRole');
    await callable.call(<String, dynamic>{
      'tripId': cleanTripId,
      'memberId': cleanMemberId,
    });
  }

  /// Leaves a trip as the current user (non-owner only). Server removes the
  /// user from trip [memberUserIds] and strips them from all shared expenses
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

    final regionFunctions = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    );
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
      TripGeneralPermissionAction.publishAnnouncements => 'publishAnnouncements',
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
      TripParticipantsPermissionAction.manageParticipants => 'manageParticipants',
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

  Future<void> updateTripActivitiesPermission({
    required String tripId,
    required TripActivitiesPermissionAction action,
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
      TripActivitiesPermissionAction.suggestActivity => 'suggestActivity',
      TripActivitiesPermissionAction.planActivity => 'planActivity',
      TripActivitiesPermissionAction.editActivity => 'editActivity',
      TripActivitiesPermissionAction.deleteActivity => 'deleteActivity',
    };

    await tripRef.update(<String, dynamic>{
      'permissions.activities.$fieldName': minRole.toFirestore(),
    });
  }

  Future<void> resetTripActivitiesPermissionsToDefaults({
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
      'permissions.activities': TripActivitiesPermissions.defaults.toFirestore(),
    });
  }

  Future<void> updateTripShoppingPermission({
    required String tripId,
    required TripShoppingPermissionAction action,
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
      TripShoppingPermissionAction.deleteCheckedItems => 'deleteCheckedItems',
    };

    await tripRef.update(<String, dynamic>{
      'permissions.shopping.$fieldName': minRole.toFirestore(),
    });
  }

  Future<void> updateTripMealsPermission({
    required String tripId,
    required TripMealsPermissionAction action,
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
      TripMealsPermissionAction.createMeal => 'createMeal',
      TripMealsPermissionAction.deleteMeal => 'deleteMeal',
      TripMealsPermissionAction.editMeal => 'editMeal',
      TripMealsPermissionAction.addContribution => 'addContribution',
      TripMealsPermissionAction.manageRecipe => 'manageRecipe',
      TripMealsPermissionAction.suggestRestaurant => 'suggestRestaurant',
    };

    await tripRef.update(<String, dynamic>{
      'permissions.meals.$fieldName': minRole.toFirestore(),
    });
  }

  Future<void> resetTripMealsPermissionsToDefaults({
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
      'permissions.meals': TripMealsPermissions.defaults.toFirestore(),
    });
  }

  Future<void> resetTripShoppingPermissionsToDefaults({
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
      'permissions.shopping': TripShoppingPermissions.defaults.toFirestore(),
    });
  }

  Future<void> updateTripCarpoolPermission({
    required String tripId,
    required TripCarpoolPermissionAction action,
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
      TripCarpoolPermissionAction.proposeCarpool => 'proposeCarpool',
      TripCarpoolPermissionAction.editCarpools => 'editCarpools',
      TripCarpoolPermissionAction.updateShoppingMeetupPoint =>
        'updateShoppingMeetupPoint',
    };

    await tripRef.update(<String, dynamic>{
      'permissions.carpool.$fieldName': minRole.toFirestore(),
    });
  }

  Future<void> resetTripCarpoolPermissionsToDefaults({
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
      'permissions.carpool': TripCarpoolPermissions.defaults.toFirestore(),
    });
  }
}
