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
    final messaging = FirebaseMessaging.instance;

    if (!kIsWeb) {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final token = kIsWeb
        ? await messaging.getToken(vapidKey: _kFcmWebVapidKey)
        : await messaging.getToken();

    if (token == null || token.isEmpty) {
      return;
    }

    await _persistToken(user.uid, token);

    _tokenRefreshSub ??=
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        unawaited(_persistToken(u.uid, newToken));
      }
    });

    _attachForegroundLogOnce();
  } catch (e, st) {
    debugPrint('FCM registration skipped: $e\n$st');
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
