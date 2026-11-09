import 'package:flutter/material.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Lists who reacted to a message. Returns true when the current user asked
/// to remove their own reaction.
Future<bool> showChatReactionsSheet({
  required BuildContext context,
  required Map<String, String> reactionsByUser,
  required Map<String, String> memberLabels,
  required Map<String, String> memberPhotoUrls,
  required String fallbackAuthorLabel,
  required String? currentUserId,
}) async {
  final userIds = reactionsByUser.keys.toList()
    ..sort((a, b) {
      // Current user first, then by name.
      if (a == currentUserId) return -1;
      if (b == currentUserId) return 1;
      return (memberLabels[a] ?? '')
          .toLowerCase()
          .compareTo((memberLabels[b] ?? '').toLowerCase());
    });

  final removeMine = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;
      final textTheme = Theme.of(sheetContext).textTheme;
      return SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: userIds.length,
          itemBuilder: (context, index) {
            final userId = userIds[index];
            final isMe = userId == currentUserId;
            final rawLabel = memberLabels[userId]?.trim() ?? '';
            final label = rawLabel.isEmpty ? fallbackAuthorLabel : rawLabel;
            final photoUrl = memberPhotoUrls[userId] ?? '';
            return ListTile(
              leading: buildProfileBadge(
                context: context,
                displayLabel: label,
                photoUrl: photoUrl,
                size: 36,
              ),
              title: Text(isMe ? l10n.commonMe : label),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reactionsByUser[userId] ?? '',
                    style: textTheme.headlineSmall,
                  ),
                  if (isMe)
                    IconButton(
                      icon: const Icon(PhosphorIconsRegular.x),
                      tooltip: l10n.commonDelete,
                      onPressed: () => Navigator.pop(sheetContext, true),
                    ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
  return removeMine ?? false;
}
