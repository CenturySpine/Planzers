import 'package:flutter/material.dart';
import 'package:planerz/app/router.dart';

/// Root [ScaffoldMessengerState] key owned by [MaterialApp], used exclusively
/// for foreground push notification SnackBars. Kept separate from the inner
/// [ScaffoldMessenger] that handles feedback messages so the two queues never
/// interfere.
final GlobalKey<ScaffoldMessengerState> notificationMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'notificationMessenger');

IconData _iconForChannel(String? channel) => switch (channel) {
      'messages' => Icons.chat_bubble,
      'activities' => Icons.event_note,
      _ => Icons.notifications,
    };

void showForegroundNotificationSnackBar({
  required String title,
  required String body,
  required String? targetPath,
  required String? channel,
}) {
  final messenger = notificationMessengerKey.currentState;
  if (messenger == null) return;

  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(_iconForChannel(channel), color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (body.isNotEmpty)
                  Text(
                    body,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      action: targetPath != null && targetPath.isNotEmpty
          ? SnackBarAction(
              label: 'Voir',
              textColor: Colors.white70,
              onPressed: () => appRouter.go(targetPath),
            )
          : null,
    ),
  );
}
