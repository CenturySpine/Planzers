import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Quoted message snippet shown inside the reply-er's bubble (as topWidget of
/// FlyerChatTextMessage). Tapping it triggers [onTap] (scroll to original).
class QuotedMessageSnippet extends ConsumerWidget {
  const QuotedMessageSnippet({
    super.key,
    required this.authorId,
    required this.text,
    required this.tripId,
    this.onTap,
  });

  final String authorId;
  final String text;
  final String tripId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(tripId));
    final authorLabel = memberLabels[authorId] ?? '';
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 3),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (authorLabel.isNotEmpty)
              Text(
                authorLabel,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Text(
              text,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.75),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner displayed above the composer input when the user is composing a
/// reply. Shows the author name, a preview of the quoted text, and a cancel
/// button.
class ReplyComposerBanner extends ConsumerWidget {
  const ReplyComposerBanner({
    super.key,
    required this.authorId,
    required this.text,
    required this.tripId,
    required this.onCancel,
  });

  final String authorId;
  final String text;
  final String tripId;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(tripId));
    final authorLabel = memberLabels[authorId] ?? '';
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      color: colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (authorLabel.isNotEmpty)
                  Text(
                    authorLabel,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  text,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.commonCancel,
            onPressed: onCancel,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
