import 'dart:async';

import 'package:flutter/material.dart';
import 'package:planerz/app/router.dart';

OverlayEntry? _activeEntry;
Timer? _dismissTimer;

IconData _iconForChannel(String? channel) => switch (channel) {
      'messages' => Icons.chat_bubble,
      'activities' => Icons.event_note,
      _ => Icons.notifications,
    };

/// Shows a top-of-screen banner.
///
/// Pass [overlay] from the calling widget's [BuildContext] via
/// [Overlay.of(context)] to guarantee availability on all platforms.
void showForegroundNotification({
  required OverlayState overlay,
  required String title,
  required String body,
  required String? targetPath,
  required String? channel,
}) {
  _dismissTimer?.cancel();
  _activeEntry?.remove();
  _activeEntry = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      final top = MediaQuery.of(context).padding.top;
      return Positioned(
        top: top + 8,
        left: 16,
        right: 16,
        child: _NotificationBanner(
          title: title,
          body: body,
          icon: _iconForChannel(channel),
          targetPath: targetPath,
          onDismiss: () {
            entry.remove();
            if (_activeEntry == entry) _activeEntry = null;
            _dismissTimer?.cancel();
          },
        ),
      );
    },
  );

  _activeEntry = entry;
  overlay.insert(entry);

  _dismissTimer = Timer(const Duration(seconds: 3), () {
    if (_activeEntry == entry) {
      entry.remove();
      _activeEntry = null;
    }
  });
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    required this.title,
    required this.body,
    required this.icon,
    required this.targetPath,
    required this.onDismiss,
  });

  final String title;
  final String body;
  final IconData icon;
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
              Icon(icon, color: cs.onInverseSurface, size: 20),
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
