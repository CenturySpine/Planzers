import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Web push requires a VAPID key from the Firebase console (Project settings →
/// Cloud Messaging). Pass at build time, e.g.
/// `--dart-define=FIREBASE_VAPID_KEY=...`
const String _kFcmWebVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

StreamSubscription<String>? _tokenRefreshSub;
bool _foregroundListenerAttached = false;

String _platformLabel() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}

String _tokenDocId(String token) {
  final digest = sha256.convert(token.codeUnits);
  return digest.toString().substring(0, 32);
}

Future<void> _persistToken(String uid, String token) async {
  final cleanUid = uid.trim();
  final cleanToken = token.trim();
  if (cleanUid.isEmpty || cleanToken.isEmpty) {
    return;
  }

  final docId = _tokenDocId(cleanToken);
  await FirebaseFirestore.instance
      .collection('users')
      .doc(cleanUid)
      .collection('fcmTokens')
      .doc(docId)
      .set(
        {
          'token': cleanToken,
          'updatedAt': FieldValue.serverTimestamp(),
          'platform': _platformLabel(),
        },
        SetOptions(merge: true),
      );
}

Future<String?> _getFcmToken({
  required FirebaseMessaging messaging,
  required bool fromUserAction,
}) async {
  if (kIsWeb) {
    if (_kFcmWebVapidKey.isEmpty) {
      return null;
    }
    if (fromUserAction) {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return null;
      }
    }
    return messaging.getToken(vapidKey: _kFcmWebVapidKey);
  }

  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  return messaging.getToken();
}

Future<void> _registerFcmToken(User user, {required bool fromUserAction}) async {
  final messaging = FirebaseMessaging.instance;
  final token = await _getFcmToken(
    messaging: messaging,
    fromUserAction: fromUserAction,
  );

  if (token == null || token.isEmpty) {
    return;
  }

  await _persistToken(user.uid, token);

  _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      unawaited(_persistToken(u.uid, newToken));
    }
  });

  _attachForegroundLogOnce();
}

/// Registers the device for FCM and stores the token under
/// `users/{uid}/fcmTokens/{hash}` for Cloud Functions to target pushes.
///
/// No-op on web when [FIREBASE_VAPID_KEY] is unset. Safe to call on every auth
/// transition.
Future<void> syncFcmTokenAfterSignIn(User user) async {
  if (kIsWeb && _kFcmWebVapidKey.isEmpty) {
    return;
  }

  try {
    await _registerFcmToken(user, fromUserAction: false);
  } catch (e, st) {
    debugPrint('FCM registration skipped: $e\n$st');
  }
}

/// Explicit user-triggered push activation flow (required for iOS PWA).
Future<bool> enablePushNotificationsFromUserAction(User user) async {
  if (kIsWeb && _kFcmWebVapidKey.isEmpty) {
    return false;
  }
  try {
    await _registerFcmToken(user, fromUserAction: true);
    return true;
  } catch (e, st) {
    debugPrint('FCM user activation failed: $e\n$st');
    return false;
  }
}

/// Removes this device's FCM token from Firestore and cancels the refresh
/// subscription. Call before signing out so stale tokens don't accumulate.
Future<void> deleteFcmTokenOnSignOut(String uid) async {
  final cleanUid = uid.trim();
  if (cleanUid.isEmpty) return;

  unawaited(_tokenRefreshSub?.cancel());
  _tokenRefreshSub = null;
  _foregroundListenerAttached = false;

  try {
    final messaging = FirebaseMessaging.instance;
    final token = await messaging.getToken(
      vapidKey: kIsWeb && _kFcmWebVapidKey.isNotEmpty ? _kFcmWebVapidKey : null,
    );
    if (token == null || token.isEmpty) return;

    final docId = _tokenDocId(token);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(cleanUid)
        .collection('fcmTokens')
        .doc(docId)
        .delete();
  } catch (e) {
    debugPrint('FCM token cleanup on sign-out: $e');
  }
}

void _attachForegroundLogOnce() {
  if (_foregroundListenerAttached || kIsWeb) {
    return;
  }
  _foregroundListenerAttached = true;
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final n = message.notification;
    debugPrint(
      'FCM (foreground): title=${n?.title} body=${n?.body} data=${message.data}',
    );
  });
}
