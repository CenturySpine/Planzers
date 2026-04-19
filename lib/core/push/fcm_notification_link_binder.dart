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
  StreamSubscription<RemoteMessage>? _foregroundSub;
  RemoteMessage? _pendingTripMessageNavigation;
  String? _pendingTargetPath;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      return;
    }

    _openedAppSub =
        FirebaseMessaging.onMessageOpenedApp.listen(_enqueueTripNavigation);
    _foregroundSub = FirebaseMessaging.onMessage.listen(
      _onForegroundMessage,
    );

    _authSub =
        FirebaseAuth.instance.authStateChanges().listen((_) => _tryFlush());

    unawaited(_consumeInitialMessage());
  }

  @override
  void dispose() {
    _openedAppSub?.cancel();
    _foregroundSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final type = _typeFromData(message.data);
    if (type != 'cupidon_match') {
      return;
    }
    final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
    if (navContext == null) {
      return;
    }
    final tripTitle = _payloadValue(message.data, 'tripTitle') ?? 'Voyage';
    final otherLabel = _payloadValue(message.data, 'otherLabel') ?? 'Quelqu’un';
    final otherPhotoUrl = _payloadValue(message.data, 'otherPhotoUrl') ?? '';
    await showDialog<void>(
      context: navContext,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.favorite, color: Colors.pink),
            SizedBox(width: 8),
            Text('Tu as un match'),
          ],
        ),
        content: Row(
          children: [
            CircleAvatar(
              backgroundImage:
                  otherPhotoUrl.isEmpty ? null : NetworkImage(otherPhotoUrl),
              child: otherPhotoUrl.isEmpty
                  ? Text(otherLabel.isEmpty ? '?' : otherLabel[0].toUpperCase())
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('$otherLabel\n$tripTitle'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              appRouter.go('/account/cupidon');
            },
            child: const Text('Voir mes matchs'),
          ),
        ],
      ),
    );
  }

  Future<void> _consumeInitialMessage() async {
    final msg = await FirebaseMessaging.instance.getInitialMessage();
    if (!mounted) return;
    _enqueueTripNavigation(msg);
  }

  void _enqueueTripNavigation(RemoteMessage? message) {
    if (message == null) return;
    final targetPath = _targetPathFromData(message.data);
    if (targetPath != null) {
      _pendingTargetPath = targetPath;
      _tryFlush();
      return;
    }
    final tripId = _tripIdFromData(message.data);
    if (tripId == null) return;
    if (_typeFromData(message.data) != 'trip_message') return;
    _pendingTripMessageNavigation = message;
    _tryFlush();
  }

  void _tryFlush() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final targetPath = _pendingTargetPath;
    if (targetPath != null && targetPath.isNotEmpty) {
      _pendingTargetPath = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        appRouter.go(targetPath);
      });
      return;
    }
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

  static String? _targetPathFromData(Map<String, dynamic> data) {
    final raw = data['targetPath'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty || !s.startsWith('/')) return null;
    return s;
  }

  static String? _payloadValue(Map<String, dynamic> data, String key) {
    final raw = data['payload_$key'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
