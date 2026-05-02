import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkifiedText extends StatefulWidget {
  const LinkifiedText({
    super.key,
    required this.text,
    this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  static final RegExp _urlRegex = RegExp(
    r'(https?://[^\s]+)|(www\.[^\s]+)',
    caseSensitive: false,
  );

  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _textSpans = const [];
  String? _spansForText;
  TextStyle? _spansForBaseStyle;
  Color? _spansForLinkColor;

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _ensureTextSpans(BuildContext context) {
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final linkColor = Theme.of(context).colorScheme.primary;
    if (_spansForText == widget.text &&
        _spansForBaseStyle == baseStyle &&
        _spansForLinkColor == linkColor) {
      return;
    }
    _disposeRecognizers();
    _spansForText = widget.text;
    _spansForBaseStyle = baseStyle;
    _spansForLinkColor = linkColor;
    _textSpans = _buildTextSpans(
      context: context,
      text: widget.text,
      baseStyle: baseStyle,
      linkColor: linkColor,
    );
  }

  List<InlineSpan> _buildTextSpans({
    required BuildContext context,
    required String text,
    required TextStyle baseStyle,
    required Color linkColor,
  }) {
    final linkStyle = baseStyle.copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );

    final children = <InlineSpan>[];
    var start = 0;
    for (final match in _urlRegex.allMatches(text)) {
      if (match.start > start) {
        children.add(
          TextSpan(text: text.substring(start, match.start), style: baseStyle),
        );
      }

      final rawUrl = match.group(0)!;
      final trimmedUrl = _trimUrlWrappingPunctuation(rawUrl);
      final href = trimmedUrl.toLowerCase().startsWith('www.')
          ? 'https://$trimmedUrl'
          : trimmedUrl;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => unawaited(_openUrl(context, href));
      _recognizers.add(recognizer);
      children.add(
        TextSpan(text: rawUrl, style: linkStyle, recognizer: recognizer),
      );
      start = match.end;
    }

    if (start < text.length) {
      children.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    if (children.isEmpty) {
      children.add(TextSpan(text: text, style: baseStyle));
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    _ensureTextSpans(context);
    return Text.rich(TextSpan(style: widget.style, children: _textSpans));
  }
}

String _trimUrlWrappingPunctuation(String rawUrl) {
  var sanitizedUrl = rawUrl;
  while (sanitizedUrl.isNotEmpty) {
    final lastCharacter = sanitizedUrl[sanitizedUrl.length - 1];
    if ('.,;:!?)]}\'"'.contains(lastCharacter)) {
      sanitizedUrl = sanitizedUrl.substring(0, sanitizedUrl.length - 1);
      continue;
    }
    break;
  }
  return sanitizedUrl;
}

Future<void> _openUrl(BuildContext context, String url) async {
  final parsedUrl = Uri.tryParse(url.trim());
  if (parsedUrl == null || !parsedUrl.hasScheme || parsedUrl.host.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.linkInvalid)),
      );
    }
    return;
  }

  final didLaunch = await launchUrl(
    parsedUrl,
    mode: LaunchMode.platformDefault,
    webOnlyWindowName: '_blank',
  );
  if (!didLaunch && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.linkOpenImpossible)),
    );
  }
}
