import 'dart:async';
import 'dart:math' as math;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:planerz/core/presentation/message_selection_action_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Shows a bottom sheet with quick reactions and message actions.
Future<void> showMessageOptions(
  BuildContext context,
  Message message, {
  required bool isMine,
  required String? myUid,
  required Future<void> Function(String messageId, String emoji) onSetReaction,
  required Future<void> Function(String messageId) onRemoveReaction,
  required Future<void> Function(String messageId, String text) onEdit,
  required Future<void> Function(String messageId) onDelete,
}) async {
  if (message is! TextMessage) return;
  final l10n = AppLocalizations.of(context)!;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetCtx) => _MessageOptionsSheet(
      outerContext: context,
      message: message,
      isMine: isMine,
      myUid: myUid,
      l10n: l10n,
      onSetReaction: onSetReaction,
      onRemoveReaction: onRemoveReaction,
      onEdit: onEdit,
      onDelete: onDelete,
    ),
  );
}

class _MessageOptionsSheet extends StatelessWidget {
  static const List<String> _quickEmojis = ['👍', '❤️', '😂', '😮', '🙏'];

  const _MessageOptionsSheet({
    required this.outerContext,
    required this.message,
    required this.isMine,
    required this.myUid,
    required this.l10n,
    required this.onSetReaction,
    required this.onRemoveReaction,
    required this.onEdit,
    required this.onDelete,
  });

  final BuildContext outerContext;
  final TextMessage message;
  final bool isMine;
  final String? myUid;
  final AppLocalizations l10n;
  final Future<void> Function(String, String) onSetReaction;
  final Future<void> Function(String) onRemoveReaction;
  final Future<void> Function(String, String) onEdit;
  final Future<void> Function(String) onDelete;

  String? _currentUserReaction() {
    if (myUid == null || message.reactions == null) return null;
    for (final entry in message.reactions!.entries) {
      if (entry.value.contains(myUid)) return entry.key;
    }
    return null;
  }

  Future<void> _handleReaction(BuildContext sheetCtx, String emoji) async {
    Navigator.pop(sheetCtx);
    try {
      if (_currentUserReaction() == emoji) {
        await onRemoveReaction(message.id);
      } else {
        await onSetReaction(message.id, emoji);
      }
    } catch (e) {
      if (!outerContext.mounted) return;
      ScaffoldMessenger.of(outerContext).showSnackBar(
        SnackBar(content: Text(l10n.chatReactionImpossible(e.toString()))),
      );
    }
  }

  Future<void> _pickEmoji(BuildContext sheetCtx) async {
    Navigator.pop(sheetCtx);
    final selected = await showModalBottomSheet<String>(
      context: outerContext,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (innerCtx) => SizedBox(
        height: math.min(MediaQuery.sizeOf(innerCtx).height * 0.55, 420),
        child: EmojiPicker(
          onEmojiSelected: (_, emoji) => Navigator.pop(innerCtx, emoji.emoji),
          config: const Config(checkPlatformCompatibility: true),
        ),
      ),
    );
    if (selected == null || !outerContext.mounted) return;
    try {
      if (_currentUserReaction() == selected) {
        await onRemoveReaction(message.id);
      } else {
        await onSetReaction(message.id, selected);
      }
    } catch (e) {
      if (!outerContext.mounted) return;
      ScaffoldMessenger.of(outerContext).showSnackBar(
        SnackBar(content: Text(l10n.chatReactionImpossible(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext sheetCtx) {
    final colorScheme = Theme.of(sheetCtx).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final emoji in _quickEmojis)
                  IconButton(
                    icon: Text(
                      emoji,
                      style: Theme.of(sheetCtx).textTheme.titleLarge,
                    ),
                    tooltip: l10n.chatReactWithEmoji(emoji),
                    onPressed: () => unawaited(_handleReaction(sheetCtx, emoji)),
                  ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: l10n.chatMoreEmojis,
                  onPressed: () => unawaited(_pickEmoji(sheetCtx)),
                ),
              ],
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.chatCopy),
              onTap: () {
                Navigator.pop(sheetCtx);
                Clipboard.setData(ClipboardData(text: message.text));
                if (outerContext.mounted) {
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    SnackBar(content: Text(l10n.chatCopied)),
                  );
                }
              },
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.chatEditMessageTitle),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final newText = await showDialog<String>(
                    context: outerContext,
                    builder: (ctx) => EditTextDialog(
                      initialText: message.text,
                      title: l10n.chatEditMessageTitle,
                      maxLength: TripMessagesRepository.maxTextLength,
                    ),
                  );
                  if (newText == null || !outerContext.mounted) return;
                  try {
                    await onEdit(message.id, newText);
                  } catch (e) {
                    if (!outerContext.mounted) return;
                    ScaffoldMessenger.of(outerContext).showSnackBar(
                      SnackBar(
                        content: Text(l10n.chatEditImpossible(e.toString())),
                      ),
                    );
                  }
                },
              ),
            if (isMine)
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title: Text(
                  l10n.commonDelete,
                  style: TextStyle(color: colorScheme.error),
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final confirm = await showDialog<bool>(
                    context: outerContext,
                    builder: (ctx) => AlertDialog(
                      content: Text(l10n.chatDeleteMessageConfirm),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l10n.commonCancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l10n.commonDelete),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true || !outerContext.mounted) return;
                  try {
                    await onDelete(message.id);
                  } catch (e) {
                    if (!outerContext.mounted) return;
                    ScaffoldMessenger.of(outerContext).showSnackBar(
                      SnackBar(
                        content: Text(l10n.chatDeleteImpossible(e.toString())),
                      ),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
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
