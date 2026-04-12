import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:planzers/app/router.dart';

/// Opens the trip messaging tab when the user taps a trip chat push notification.
///
/// Handles cold start ([getInitialMessage]) and background ([onMessageOpenedApp]).
/// Waits for a signed-in user before navigating.
class FcmNotificationLinkBinder extends StatefulWidget {
  const FcmNotificationLinkBinder({required this.child, super.key});

  final Widget child;

  @override
  State<FcmNotificationLinkBinder> createState() =>
      _FcmNotificationLinkBinderState();
}

class _FcmNotificationLinkBinderState extends State<FcmNotificationLinkBinder> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  RemoteMessage? _pendingTripMessageNavigation;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      return;
    }

    _openedAppSub =
        FirebaseMessaging.onMessageOpenedApp.listen(_enqueueTripNavigation);

    _authSub =
        FirebaseAuth.instance.authStateChanges().listen((_) => _tryFlush());

    unawaited(_consumeInitialMessage());
  }

  @override
  void dispose() {
    _openedAppSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _consumeInitialMessage() async {
    final msg = await FirebaseMessaging.instance.getInitialMessage();
    if (!mounted) return;
    _enqueueTripNavigation(msg);
  }

  void _enqueueTripNavigation(RemoteMessage? message) {
    if (message == null) return;
    final tripId = _tripIdFromData(message.data);
    if (tripId == null) return;
    if (_typeFromData(message.data) != 'trip_message') return;
    _pendingTripMessageNavigation = message;
    _tryFlush();
  }

  void _tryFlush() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_pendingTripMessageNavigation == null) return;

    final tripId = _tripIdFromData(_pendingTripMessageNavigation!.data);
    _pendingTripMessageNavigation = null;
    if (tripId == null || tripId.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      appRouter.go('/trips/$tripId/messages');
    });
  }

  static String? _tripIdFromData(Map<String, dynamic> data) {
    final raw = data['tripId'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String? _typeFromData(Map<String, dynamic> data) {
    final raw = data['type'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
