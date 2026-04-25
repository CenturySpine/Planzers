import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/notifications/notification_channel.dart';

final notificationCenterRepositoryProvider =
    Provider<NotificationCenterRepository>((ref) {
  return NotificationCenterRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

final tripChannelLastReadAtProvider = StreamProvider.autoDispose
    .family<DateTime?, ({String tripId, TripNotificationChannel channel})>(
        (ref, args) {
  return ref.watch(notificationCenterRepositoryProvider).watchLastReadAt(
        args.tripId,
        args.channel,
      );
});

final tripNotificationCountersProvider =
    StreamProvider.autoDispose.family<TripNotificationCounters?, String>(
        (ref, tripId) {
  return ref
      .watch(notificationCenterRepositoryProvider)
      .watchTripCounters(tripId);
});

final tripChannelUnreadCountProvider = StreamProvider.autoDispose
    .family<int, ({String tripId, TripNotificationChannel channel})>((ref, args) {
  return ref.watch(notificationCenterRepositoryProvider).watchUnreadCount(
        tripId: args.tripId,
        channel: args.channel,
      );
});

final globalUnreadCountProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.watch(notificationCenterRepositoryProvider).watchGlobalUnreadCount();
});

final myTripUnreadTotalsProvider =
    StreamProvider.autoDispose<Map<String, int>>((ref) {
  return ref
      .watch(notificationCenterRepositoryProvider)
      .watchMyTripUnreadTotals();
});

/// Total unread Cupidon matches across all trips. Used for the heart badge on
/// the profile nav item.
final cupidonGlobalUnreadCountProvider = StreamProvider.autoDispose<int>((ref) {
  return ref
      .watch(notificationCenterRepositoryProvider)
      .watchCupidonGlobalUnreadCount();
});

class TripNotificationCounters {
  TripNotificationCounters({
    required this.channels,
    required this.total,
  });

  final Map<TripNotificationChannel, int> channels;
  final int total;

  int unreadFor(TripNotificationChannel channel) => channels[channel] ?? 0;

  /// Unread shown on trip list and trip shell (messages + activities only).
  /// Cupidon is profile-only; [total] may still include legacy cupidon values.
  int get tripShellUnreadTotal =>
      unreadFor(TripNotificationChannel.messages) +
      unreadFor(TripNotificationChannel.activities) +
      unreadFor(TripNotificationChannel.announcements);

  bool hasChannel(TripNotificationChannel channel) => channels.containsKey(channel);

  static TripNotificationCounters fromFirestore(Map<String, dynamic> data) {
    final rawChannels = data['channels'];
    final channels = <TripNotificationChannel, int>{};
    if (rawChannels is Map) {
      for (final entry in rawChannels.entries) {
        final channel = TripNotificationChannel.fromFirestoreKey(
          entry.key.toString(),
        );
        if (channel == null) continue;
        final value = entry.value;
        channels[channel] = switch (value) {
          int i => i,
          num n => n.toInt(),
          _ => 0,
        };
      }
    }
    final rawTotal = data['total'];
    final total = switch (rawTotal) {
      int i => i,
      num n => n.toInt(),
      _ => channels.values.fold<int>(0, (acc, v) => acc + v),
    };
    return TripNotificationCounters(channels: channels, total: total);
  }
}

class NotificationCenterRepository {
  NotificationCenterRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  DocumentReference<Map<String, dynamic>> _myReadStateDoc(String tripId) {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('Utilisateur non connecte');
    }
    return firestore
        .collection('trips')
        .doc(tripId)
        .collection('notificationReads')
        .doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _myTripCountersDoc(String tripId) {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('Utilisateur non connecte');
    }
    return firestore
        .collection('users')
        .doc(uid)
        .collection('tripNotificationCounters')
        .doc(tripId);
  }

  DocumentReference<Map<String, dynamic>> _myTripPresenceDoc(String tripId) {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('Utilisateur non connecte');
    }
    return firestore
        .collection('users')
        .doc(uid)
        .collection('tripNotificationPresence')
        .doc(tripId);
  }

  Stream<DateTime?> watchLastReadAt(String tripId, TripNotificationChannel channel) {
    final cleanTripId = tripId.trim();
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (cleanTripId.isEmpty || uid.isEmpty) {
      return Stream.value(null);
    }
    return _myReadStateDoc(cleanTripId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      final channels = data['channels'];
      final raw = channels is Map<String, dynamic>
          ? channels[channel.firestoreKey]
          : null;
      return switch (raw) {
        Timestamp ts => ts.toDate(),
        _ => null,
      };
    });
  }

  Future<void> markReadUpTo({
    required String tripId,
    required TripNotificationChannel channel,
    required DateTime timestamp,
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }
    await _myReadStateDoc(cleanTripId).set({
      'channels': {
        channel.firestoreKey: Timestamp.fromDate(timestamp.toUtc()),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setOpenChannel({
    required String tripId,
    required TripNotificationChannel channel,
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }
    await _myTripPresenceDoc(cleanTripId).set({
      'openChannel': channel.firestoreKey,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearOpenChannel({
    required String tripId,
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      return;
    }
    await _myTripPresenceDoc(cleanTripId).delete();
  }

  Stream<TripNotificationCounters?> watchTripCounters(String tripId) {
    final cleanTripId = tripId.trim();
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (cleanTripId.isEmpty || uid.isEmpty) {
      return Stream.value(null);
    }
    return _myTripCountersDoc(cleanTripId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return TripNotificationCounters.fromFirestore(data);
    });
  }

  Stream<int> watchUnreadCount({
    required String tripId,
    required TripNotificationChannel channel,
  }) {
    return watchTripCounters(tripId).map((counters) {
      if (counters == null) return 0;
      return counters.unreadFor(channel);
    });
  }

  Stream<int> watchGlobalUnreadCount() {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      return Stream.value(0);
    }
    return firestore
        .collection('users')
        .doc(uid)
        .collection('tripNotificationCounters')
        .snapshots()
        .map((snap) {
      var total = 0;
      for (final doc in snap.docs) {
        final counters = TripNotificationCounters.fromFirestore(doc.data());
        total += counters.tripShellUnreadTotal;
      }
      return total;
    });
  }

  /// Streams the total number of unread Cupidon matches across all trips.
  Stream<int> watchCupidonGlobalUnreadCount() {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      return Stream.value(0);
    }
    return firestore
        .collection('users')
        .doc(uid)
        .collection('tripNotificationCounters')
        .snapshots()
        .map((snap) {
      var total = 0;
      for (final doc in snap.docs) {
        final counters = TripNotificationCounters.fromFirestore(doc.data());
        total += counters.unreadFor(TripNotificationChannel.cupidon);
      }
      return total;
    });
  }

  Stream<Map<String, int>> watchMyTripUnreadTotals() {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      return Stream.value(const <String, int>{});
    }
    return firestore
        .collection('users')
        .doc(uid)
        .collection('tripNotificationCounters')
        .snapshots()
        .map((snap) {
      final unreadByTrip = <String, int>{};
      for (final doc in snap.docs) {
        unreadByTrip[doc.id] = TripNotificationCounters.fromFirestore(
          doc.data(),
        ).tripShellUnreadTotal;
      }
      return unreadByTrip;
    });
  }

  /// Realigns Cupidon channel + totals from real `cupidonMatches` (server-side).
  /// Needed because Firestore rules do not allow client writes on counters.
  Future<void> reconcileMyCupidonCountersFromServer() async {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('reconcileMyCupidonNotificationCounters');
    await callable.call();
  }

  /// Resets all Cupidon unread counters to zero across every trip. Call when
  /// the user views the Cupidon screen.
  Future<void> clearAllCupidonUnread() async {
    final uid = auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('tripNotificationCounters')
        .get();

    var batch = firestore.batch();
    var ops = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final counters = TripNotificationCounters.fromFirestore(data);
      if (counters.unreadFor(TripNotificationChannel.cupidon) == 0) continue;

      final newTotal = counters.tripShellUnreadTotal;
      batch.update(doc.reference, {
        'channels.${TripNotificationChannel.cupidon.firestoreKey}': 0,
        'total': newTotal < 0 ? 0 : newTotal,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = firestore.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
  }

  Future<int> computeUnreadCount({
    required String tripId,
    required TripNotificationChannel channel,
    required DateTime readAfter,
    String? excludeActorId,
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final channelCollection = switch (channel) {
      TripNotificationChannel.messages => 'messages',
      TripNotificationChannel.activities => 'activities',
      TripNotificationChannel.announcements => 'announcements',
      TripNotificationChannel.cupidon =>
        throw UnsupportedError('computeUnreadCount not applicable to cupidon'),
    };
    final actorField = switch (channel) {
      TripNotificationChannel.messages => 'authorId',
      TripNotificationChannel.activities => 'createdBy',
      TripNotificationChannel.announcements => 'authorId',
      TripNotificationChannel.cupidon =>
        throw UnsupportedError('computeUnreadCount not applicable to cupidon'),
    };

    final baseQuery = firestore
        .collection('trips')
        .doc(cleanTripId)
        .collection(channelCollection)
        .where('createdAt', isGreaterThan: Timestamp.fromDate(readAfter.toUtc()));
    final totalSnap = await baseQuery.count().get();
    var total = totalSnap.count ?? 0;

    final cleanExcludedActorId = excludeActorId?.trim() ?? '';
    if (cleanExcludedActorId.isNotEmpty) {
      final ownSnap = await firestore
          .collection('trips')
          .doc(cleanTripId)
          .collection(channelCollection)
          .where(actorField, isEqualTo: cleanExcludedActorId)
          .where(
            'createdAt',
            isGreaterThan: Timestamp.fromDate(readAfter.toUtc()),
          )
          .count()
          .get();
      total -= ownSnap.count ?? 0;
      if (total < 0) {
        total = 0;
      }
    }
    return total;
  }
}
