import 'package:flutter/material.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// One-line summary of a quoted message: its text, or a photo mention.
class _QuotePreview extends StatelessWidget {
  const _QuotePreview({
    required this.text,
    required this.isImage,
    required this.style,
  });

  final String text;
  final bool isImage;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final label = text.isNotEmpty
        ? text
        : (isImage ? AppLocalizations.of(context)!.chatQuotedImage : '');
    final preview = Text(
      label,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!isImage) return preview;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(PhosphorIconsRegular.camera, size: 14, color: style?.color),
        const SizedBox(width: 4),
        Flexible(child: preview),
      ],
    );
  }
}

/// Quoted message shown at the top of a reply bubble. Tapping it triggers
/// [onTap] (scroll to the original message).
class QuotedMessageSnippet extends StatelessWidget {
  const QuotedMessageSnippet({
    super.key,
    required this.authorLabel,
    required this.text,
    this.isImage = false,
    this.onTap,
  });

  final String authorLabel;
  final String text;
  final bool isImage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.07),
            border: Border(
              left: BorderSide(color: colorScheme.primary, width: 3),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 5, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (authorLabel.isNotEmpty)
                Text(
                  authorLabel,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              _QuotePreview(
                text: text,
                isImage: isImage,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner displayed above the composer input while the user replies to or
/// edits a message. Shows a title, a preview of the message and a cancel
/// button.
class ComposerContextBanner extends StatelessWidget {
  const ComposerContextBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.onCancel,
    this.isImage = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final bool isImage;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 10),
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
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                _QuotePreview(
                  text: text,
                  isImage: isImage,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsRegular.x),
            tooltip: l10n.commonCancel,
            onPressed: onCancel,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
