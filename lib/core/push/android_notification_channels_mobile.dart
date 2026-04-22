import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:planerz/core/notifications/notification_channel.dart';

Future<void> initAndroidNotificationChannels() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final androidPlugin = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin == null) return;
  for (final channel in TripNotificationChannel.values) {
    await androidPlugin.createNotificationChannel(
      AndroidNotificationChannel(
        channel.androidChannelId,
        channel.androidChannelName,
        importance: Importance.high,
      ),
    );
  }
}
