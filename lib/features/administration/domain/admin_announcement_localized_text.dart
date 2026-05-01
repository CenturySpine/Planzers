import 'dart:ui';

String resolveAdminAnnouncementText(String rawText, Locale locale) {
  final parsedSections = _parseLocalizedSections(rawText);
  if (parsedSections.isEmpty) {
    return rawText;
  }

  final normalizedExactLocale = _normalizeLocaleToken(
    locale.countryCode == null || locale.countryCode!.trim().isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-${locale.countryCode}',
  );
  final normalizedLanguageOnlyLocale = _normalizeLocaleToken(
    locale.languageCode,
  );

  for (final parsedSection in parsedSections) {
    if (parsedSection.normalizedLocale == normalizedExactLocale) {
      return parsedSection.text;
    }
  }
  for (final parsedSection in parsedSections) {
    if (parsedSection.normalizedLocale == normalizedLanguageOnlyLocale) {
      return parsedSection.text;
    }
  }
  return parsedSections.first.text;
}

List<_ParsedLocalizedSection> _parseLocalizedSections(String rawText) {
  final lines = rawText.split('\n');
  final parsedSections = <_ParsedLocalizedSection>[];
  final knownLocales = <String>{};
  var currentNormalizedLocale = '';
  var currentLines = <String>[];
  var hasDetectedSection = false;

  void flushCurrentSection() {
    if (currentNormalizedLocale.isEmpty) {
      currentLines = <String>[];
      return;
    }
    if (knownLocales.contains(currentNormalizedLocale)) {
      currentLines = <String>[];
      return;
    }
    knownLocales.add(currentNormalizedLocale);
    parsedSections.add(
      _ParsedLocalizedSection(
        normalizedLocale: currentNormalizedLocale,
        text: currentLines.join('\n').trim(),
      ),
    );
    currentLines = <String>[];
  }

  for (final line in lines) {
    final normalizedHeaderLocale = _tryParseHeaderLocale(line);
    if (normalizedHeaderLocale != null) {
      hasDetectedSection = true;
      flushCurrentSection();
      currentNormalizedLocale = normalizedHeaderLocale;
      continue;
    }
    if (currentNormalizedLocale.isNotEmpty) {
      currentLines.add(line);
    }
  }

  flushCurrentSection();
  if (!hasDetectedSection) {
    return const <_ParsedLocalizedSection>[];
  }
  return parsedSections;
}

String? _tryParseHeaderLocale(String line) {
  final match = RegExp(
    r'^\s*\[([A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})?)\]\s*$',
  ).firstMatch(line);
  if (match == null) {
    return null;
  }
  return _normalizeLocaleToken(match.group(1) ?? '');
}

String _normalizeLocaleToken(String rawLocaleToken) {
  final normalizedSeparators = rawLocaleToken.trim().replaceAll('_', '-');
  final rawParts = normalizedSeparators
      .split('-')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (rawParts.isEmpty) {
    return '';
  }
  final normalizedLanguage = rawParts.first.toLowerCase();
  if (rawParts.length == 1) {
    return normalizedLanguage;
  }
  final normalizedCountry = rawParts[1].toLowerCase();
  return '$normalizedLanguage-$normalizedCountry';
}

class _ParsedLocalizedSection {
  const _ParsedLocalizedSection({
    required this.normalizedLocale,
    required this.text,
  });

  final String normalizedLocale;
  final String text;
}
