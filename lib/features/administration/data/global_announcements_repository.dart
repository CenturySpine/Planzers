import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/administration/domain/admin_announcement.dart';

final globalAnnouncementsRepositoryProvider =
    Provider<GlobalAnnouncementsRepository>((ref) {
  return GlobalAnnouncementsRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

final globalAnnouncementsListProvider =
    StreamProvider.autoDispose<List<AdminAnnouncement>>((ref) {
  return ref.watch(globalAnnouncementsRepositoryProvider).watchAnnouncements();
});

final globalAdminAnnouncementsUnreadIndicatorProvider =
    StreamProvider.autoDispose<bool>((ref) {
  return ref
      .watch(globalAnnouncementsRepositoryProvider)
      .watchHasUnreadIndicator();
});

final globalVisibleAnnouncementsForCurrentUserProvider =
    StreamProvider.autoDispose<List<AdminAnnouncement>>((ref) {
  return ref
      .watch(globalAnnouncementsRepositoryProvider)
      .watchVisibleAnnouncementsForCurrentUser();
});

final globalHasDismissedAdminAnnouncementsProvider =
    StreamProvider.autoDispose<bool>((ref) {
  return ref
      .watch(globalAnnouncementsRepositoryProvider)
      .watchHasDismissedAdminAnnouncements();
});

class GlobalAnnouncementsRepository {
  GlobalAnnouncementsRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  static const int maxTextLength = 8000;

  CollectionReference<Map<String, dynamic>> get _announcementsCollection =>
      firestore.collection('adminAnnouncements');

  DocumentReference<Map<String, dynamic>> _userReadStateDocument(String uid) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('globalNotificationReads')
        .doc('adminAnnouncements');
  }

  CollectionReference<Map<String, dynamic>> _dismissedAnnouncementsCollection(
    String uid,
  ) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('dismissedAdminAnnouncements');
  }

  String _requireCurrentUid() {
    final currentUid = auth.currentUser?.uid.trim() ?? '';
    if (currentUid.isEmpty) {
      throw StateError('Utilisateur non connecte');
    }
    return currentUid;
  }

  Stream<List<AdminAnnouncement>> watchAnnouncements() {
    return _announcementsCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((querySnapshot) {
      return querySnapshot.docs.map(AdminAnnouncement.fromDoc).toList();
    });
  }

  Stream<bool> watchHasDismissedAdminAnnouncements() {
    final currentUid = auth.currentUser?.uid.trim() ?? '';
    if (currentUid.isEmpty) {
      return Stream.value(false);
    }
    return _dismissedAnnouncementsCollection(currentUid).snapshots().map(
          (querySnapshot) => querySnapshot.docs.isNotEmpty,
        );
  }

  Stream<List<AdminAnnouncement>> watchVisibleAnnouncementsForCurrentUser() {
    final currentUid = auth.currentUser?.uid.trim() ?? '';
    if (currentUid.isEmpty) {
      return Stream.value(const <AdminAnnouncement>[]);
    }

    final streamController = StreamController<List<AdminAnnouncement>>();
    List<AdminAnnouncement> latestAnnouncements = const <AdminAnnouncement>[];
    Set<String> latestDismissedIds = const <String>{};
    StreamSubscription<List<AdminAnnouncement>>? announcementsSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
        dismissedAnnouncementsSubscription;

    void emitVisibleAnnouncements() {
      if (streamController.isClosed) {
        return;
      }
      final visibleAnnouncements = latestAnnouncements
          .where(
            (announcement) => !latestDismissedIds.contains(announcement.id),
          )
          .toList(growable: false);
      streamController.add(visibleAnnouncements);
    }

    streamController.onListen = () {
      announcementsSubscription = watchAnnouncements().listen((announcements) {
        latestAnnouncements = announcements;
        emitVisibleAnnouncements();
      });
      dismissedAnnouncementsSubscription =
          _dismissedAnnouncementsCollection(currentUid).snapshots().listen(
        (dismissedSnapshot) {
          latestDismissedIds =
              dismissedSnapshot.docs.map((document) => document.id).toSet();
          emitVisibleAnnouncements();
        },
      );
    };
    streamController.onCancel = () async {
      await announcementsSubscription?.cancel();
      await dismissedAnnouncementsSubscription?.cancel();
    };
    return streamController.stream;
  }

  Stream<bool> watchHasUnreadIndicator() {
    final currentUid = auth.currentUser?.uid.trim() ?? '';
    if (currentUid.isEmpty) {
      return Stream.value(false);
    }

    final streamController = StreamController<bool>();
    QuerySnapshot<Map<String, dynamic>>? latestAnnouncementsSnapshot;
    DocumentSnapshot<Map<String, dynamic>>? latestReadStateSnapshot;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
        announcementsSubscription;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
        readStateSubscription;

    void emitUnreadStateIfReady() {
      final announcementsSnapshot = latestAnnouncementsSnapshot;
      final readStateSnapshot = latestReadStateSnapshot;
      if (announcementsSnapshot == null || readStateSnapshot == null) {
        return;
      }
      final readData = readStateSnapshot.data() ?? const <String, dynamic>{};
      final lastReadAtRaw = readData['lastReadAt'];
      final lastReadAt = switch (lastReadAtRaw) {
        Timestamp timestamp => timestamp.toDate(),
        _ => null,
      };
      final hasUnread = announcementsSnapshot.docs.any((announcementDocument) {
        final createdAtRaw = announcementDocument.data()['createdAt'];
        final createdAt = switch (createdAtRaw) {
          Timestamp timestamp => timestamp.toDate(),
          _ => null,
        };
        if (createdAt == null) {
          return false;
        }
        if (lastReadAt == null) {
          return true;
        }
        return createdAt.isAfter(lastReadAt);
      });
      streamController.add(hasUnread);
    }

    streamController.onListen = () {
      announcementsSubscription = _announcementsCollection
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((announcementSnapshot) {
        latestAnnouncementsSnapshot = announcementSnapshot;
        emitUnreadStateIfReady();
      });
      readStateSubscription =
          _userReadStateDocument(currentUid).snapshots().listen((readSnapshot) {
        latestReadStateSnapshot = readSnapshot;
        emitUnreadStateIfReady();
      });
    };
    streamController.onCancel = () async {
      await announcementsSubscription?.cancel();
      await readStateSubscription?.cancel();
    };
    return streamController.stream;
  }

  Future<void> sendAnnouncement(
    String text, {
    bool userDismissAllowed = true,
  }) async {
    final currentUid = _requireCurrentUid();
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      throw StateError('Message vide');
    }
    if (trimmedText.length > maxTextLength) {
      throw StateError('Message trop long');
    }
    await _announcementsCollection.add(<String, dynamic>{
      'text': trimmedText,
      'authorId': currentUid,
      'createdAt': FieldValue.serverTimestamp(),
      'userDismissAllowed': userDismissAllowed,
    });
  }

  Future<void> updateAnnouncement(
    String id,
    String text, {
    required bool userDismissAllowed,
  }) async {
    _requireCurrentUid();
    final cleanedAnnouncementId = id.trim();
    final trimmedText = text.trim();
    if (cleanedAnnouncementId.isEmpty) {
      throw StateError('Annonce invalide');
    }
    if (trimmedText.isEmpty) {
      throw StateError('Message vide');
    }
    if (trimmedText.length > maxTextLength) {
      throw StateError('Message trop long');
    }
    await _announcementsCollection.doc(cleanedAnnouncementId).update(
      <String, dynamic>{
        'text': trimmedText,
        'updatedAt': FieldValue.serverTimestamp(),
        'userDismissAllowed': userDismissAllowed,
      },
    );
  }

  Future<void> deleteAnnouncement(String id) async {
    _requireCurrentUid();
    final cleanedAnnouncementId = id.trim();
    if (cleanedAnnouncementId.isEmpty) {
      throw StateError('Annonce invalide');
    }
    await _announcementsCollection.doc(cleanedAnnouncementId).delete();
  }

  Future<void> markAsReadNow() async {
    final currentUid = _requireCurrentUid();
    await _userReadStateDocument(currentUid).set(<String, dynamic>{
      'lastReadAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> dismissAnnouncement(String id) async {
    final currentUid = _requireCurrentUid();
    final cleanedAnnouncementId = id.trim();
    if (cleanedAnnouncementId.isEmpty) {
      throw StateError('Annonce invalide');
    }
    await _dismissedAnnouncementsCollection(currentUid)
        .doc(cleanedAnnouncementId)
        .set(<String, dynamic>{
      'dismissedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes every doc in [dismissedAdminAnnouncements] for the current user.
  Future<void> restoreAllDismissedAdminAnnouncements() async {
    final currentUid = _requireCurrentUid();
    final dismissedCollection =
        _dismissedAnnouncementsCollection(currentUid);
    while (true) {
      final snapshot = await dismissedCollection.limit(500).get();
      if (snapshot.docs.isEmpty) {
        return;
      }
      final batch = firestore.batch();
      for (final documentSnapshot in snapshot.docs) {
        batch.delete(documentSnapshot.reference);
      }
      await batch.commit();
    }
  }
}
