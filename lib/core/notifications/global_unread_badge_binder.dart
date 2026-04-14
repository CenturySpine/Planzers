import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:planzers/core/notifications/app_icon_badge.dart';
import 'package:planzers/core/notifications/notification_center_repository.dart';

class GlobalUnreadBadgeBinder extends StatefulWidget {
  const GlobalUnreadBadgeBinder({required this.child, super.key});

  final Widget child;

  @override
  State<GlobalUnreadBadgeBinder> createState() => _GlobalUnreadBadgeBinderState();
}

class _GlobalUnreadBadgeBinderState extends State<GlobalUnreadBadgeBinder> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _counterSub;
  int? _lastAppliedCount;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
    _onAuthChanged(FirebaseAuth.instance.currentUser);
  }

  @override
  void dispose() {
    _counterSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _onAuthChanged(User? user) async {
    await _counterSub?.cancel();
    _counterSub = null;

    if (user == null) {
      _lastAppliedCount = 0;
      await applyAppIconBadgeCount(0);
      return;
    }

    _counterSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tripNotificationCounters')
        .snapshots()
        .listen((snap) {
      var total = 0;
      for (final doc in snap.docs) {
        total += TripNotificationCounters.fromFirestore(doc.data()).total;
      }
      if (_lastAppliedCount == total) {
        return;
      }
      _lastAppliedCount = total;
      unawaited(applyAppIconBadgeCount(total));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
