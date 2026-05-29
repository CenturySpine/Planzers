import 'package:planerz/core/presentation/linkified_text.dart';

/// Detects plain http(s)/www URLs not already in markdown `[text](url)` form.
final RegExp _plainUrlRegex = RegExp(
  r'(?<!\()(https?://[^\s<>\[\]]+|www\.[^\s<>\[\]]+)',
  caseSensitive: false,
);

/// Wraps bare URLs as markdown links so [GptMarkdown] renders them tappable.
String embedPlainUrlsAsMarkdown(String text) {
  if (text.isEmpty) return text;
  return text.replaceAllMapped(_plainUrlRegex, (match) {
    final raw = trimUrlWrappingPunctuation(match.group(0)!);
    if (raw.isEmpty) return match.group(0)!;
    final href = raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw;
    return '[$raw]($href)';
  });
}
