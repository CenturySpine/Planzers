import 'package:flutter/material.dart';
import 'package:planerz/app/router.dart';

IconData iconForNotificationChannel(String? channel) => switch (channel) {
      'messages' => Icons.chat_bubble,
      'activities' => Icons.event_note,
      'announcements' => Icons.campaign,
      _ => Icons.notifications,
    };

class ForegroundNotificationBanner extends StatelessWidget {
  const ForegroundNotificationBanner({
    required this.title,
    required this.body,
    required this.channel,
    required this.targetPath,
    required this.onDismiss,
    super.key,
  });

  final String title;
  final String body;
  final String? channel;
  final String? targetPath;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasTarget = targetPath != null && targetPath!.isNotEmpty;

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: cs.inverseSurface,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          onDismiss();
          if (hasTarget) appRouter.go(targetPath!);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                iconForNotificationChannel(channel),
                color: cs.onInverseSurface,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: TextStyle(
                          color: cs.onInverseSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (body.isNotEmpty)
                      Text(
                        body,
                        style: TextStyle(
                          color: cs.onInverseSurface.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (hasTarget) ...[
                const SizedBox(width: 8),
                Text(
                  'Voir',
                  style: TextStyle(
                    color: cs.onInverseSurface.withValues(alpha: 0.75),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
