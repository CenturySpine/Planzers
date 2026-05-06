import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Compact visual representation of a `linkPreview` map stored on a Firestore
/// document. Used everywhere a saved link is shown to the user.
///
/// Layout: thumbnail + clickable title (or URL) with the URL as subtext.
/// The whole row is tappable and opens the link via [launchUrl]. Callers can
/// supply an optional [trailing] widget (e.g. a "directions" icon button) for
/// contextual side-actions; that widget receives its own taps independently
/// from the main link area.
class LinkPreviewCompact extends StatelessWidget {
  const LinkPreviewCompact({
    super.key,
    required this.url,
    required this.preview,
    this.trailing,
    this.showCard = true,
  });

  final String url;
  final Map<String, dynamic> preview;
  final Widget? trailing;
  final bool showCard;

  Future<void> _openLink(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final parsed = Uri.tryParse(url.trim());
    if (parsed == null || !parsed.isAbsolute) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkInvalid)),
      );
      return;
    }

    final didLaunch = await launchUrl(
      parsed,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );

    if (!didLaunch && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkOpenImpossible)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final previewTitle = ((preview['title'] as String?) ?? '').trim();
    final primaryText = previewTitle.isNotEmpty ? previewTitle : url;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _openLink(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  LinkPreviewThumbnail(preview: preview, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          primaryText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: cs.tertiary,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (previewTitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );

    if (!showCard) return row;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: row,
      ),
    );
  }
}

/// Compact preview image for list rows (activity list, etc.).
class LinkPreviewThumbnail extends StatelessWidget {
  const LinkPreviewThumbnail({
    super.key,
    required this.preview,
    this.size = 56,
  });

  final Map<String, dynamic> preview;
  final double size;

  @override
  Widget build(BuildContext context) {
    final status = (preview['status'] as String?) ?? '';
    final imageUrl = (preview['imageUrl'] as String?) ?? '';

    if (status == 'loading') {
      return SizedBox(
        width: size,
        height: size,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (imageUrl.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.link,
          size: size * 0.45,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        webHtmlElementStrategy: kIsWeb
            ? WebHtmlElementStrategy.prefer
            : WebHtmlElementStrategy.never,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(
            Icons.broken_image_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
