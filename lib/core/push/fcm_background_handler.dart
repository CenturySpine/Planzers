import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:planerz/core/push/android_notification_channels.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No-op: system notification display is handled by FCM payload.
}

void configureFcmBackgroundHandling() {
  if (kIsWeb) {
    return;
  }
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  initAndroidNotificationChannels();
}
