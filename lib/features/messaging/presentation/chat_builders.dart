import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Quick reactions shown above a long-pressed message (pre-migration layout).
const List<String> chatQuickReactionEmojis = ['👍', '❤️', '😂', '😮', '🙏'];

/// Emoji the current user applied on [message], if any.
String? currentUserReactionEmoji(Message message, String? myUid) {
  if (myUid == null || message.reactions == null) return null;
  for (final entry in message.reactions!.entries) {
    if (entry.value.contains(myUid)) return entry.key;
  }
  return null;
}

/// Pill bar with quick emojis and "+" for the full picker, overlaying the bubble.
class InlineMessageQuickReactionBar extends StatelessWidget {
  const InlineMessageQuickReactionBar({
    super.key,
    required this.onEmojiTap,
    required this.onMoreTap,
  });

  final Future<void> Function(String emoji) onEmojiTap;
  final Future<void> Function() onMoreTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in chatQuickReactionEmojis)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: () => unawaited(onEmojiTap(emoji)),
                  icon: Text(
                    emoji,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  tooltip: l10n.chatReactWithEmoji(emoji),
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              onPressed: () => unawaited(onMoreTap()),
              icon: const Icon(Icons.add),
              tooltip: l10n.chatMoreEmojis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps [child] with the quick-reaction bar above the message bubble.
Widget wrapMessageWithQuickReactionBar({
  required Widget child,
  required bool isSentByMe,
  required Future<void> Function(String emoji) onEmojiTap,
  required Future<void> Function() onMoreTap,
}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 34),
        child: child,
      ),
      Positioned(
        top: 0,
        left: isSentByMe ? null : 40,
        right: isSentByMe ? 0 : null,
        child: InlineMessageQuickReactionBar(
          onEmojiTap: onEmojiTap,
          onMoreTap: onMoreTap,
        ),
      ),
    ],
  );
}

/// Single combined reaction badge shown below a message bubble (pre-migration style).
class MessageReactionsBadge extends StatelessWidget {
  const MessageReactionsBadge({
    super.key,
    required this.reactions,
  });

  final Map<String, List<String>> reactions;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final emojis = _sortedReactionEmojis(reactions);
    final totalCount =
        reactions.values.fold<int>(0, (sum, uids) => sum + uids.length);
    final scheme = Theme.of(context).colorScheme;
    final emojisLabel = emojis.join(' ');
    final countLabel = totalCount > 1 ? ' $totalCount' : '';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '$emojisLabel$countLabel',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

/// Emojis sorted by popularity (same order as pre-migration chat).
List<String> _sortedReactionEmojis(Map<String, List<String>> reactions) {
  final entries = reactions.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  return entries.map((e) => e.key).toList();
}

/// Avatar widget for the chat list.
///
/// Reads photo URL and display name directly from Riverpod providers so that
/// it always reflects the latest Firestore data — bypasses the SDK UserCache
/// which can serve stale data on first render.
class ChatProfileBadge extends ConsumerWidget {
  final String userId;
  final String tripId;
  final double size;

  const ChatProfileBadge({
    super.key,
    required this.userId,
    required this.tripId,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoUrls = ref.watch(tripMemberPhotoUrlsProvider(tripId));
    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(tripId));
    final photoUrl = photoUrls[userId];
    return buildProfileBadge(
      context: context,
      displayLabel: memberLabels[userId] ?? '',
      photoUrl: (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
      size: size,
    );
  }
}

/// Username label for the first message in a received group.
///
/// Same rationale as [ChatProfileBadge]: reads from Riverpod directly.
class ChatUserLabel extends ConsumerWidget {
  final String userId;
  final String tripId;

  const ChatUserLabel({
    super.key,
    required this.userId,
    required this.tripId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(tripId));
    final label = memberLabels[userId] ?? '';
    if (label.isEmpty) return const SizedBox.shrink();
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
