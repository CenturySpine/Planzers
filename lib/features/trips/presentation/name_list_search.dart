import 'package:flutter/material.dart';
import 'package:planerz/l10n/app_localizations.dart';

String nameListSearchEmptyMessage(BuildContext context) {
  return AppLocalizations.of(context)!.nameSearchEmpty;
}

/// Same normalization as the invite “pick your name” flow: trim + lowercase.
String normalizeNameSearchInput(String raw) => raw.trim().toLowerCase();

/// Normalizes names/emails to improve fuzzy matching in UI suggestions.
String normalizeForUiStringSimilarity(String raw) {
  const accentToAscii = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
  };
  final lower = raw.trim().toLowerCase();
  final atIndex = lower.indexOf('@');
  final withoutEmailDomain =
      atIndex > 0 ? lower.substring(0, atIndex) : lower;
  final withoutAccents = StringBuffer();
  for (final rune in withoutEmailDomain.runes) {
    final char = String.fromCharCode(rune);
    withoutAccents.write(accentToAscii[char] ?? char);
  }
  return withoutAccents.toString().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Returns a value in [0, 1] where 1 is an exact match.
double normalizedJaroWinklerSimilarity(String leftRaw, String rightRaw) {
  final left = normalizeForUiStringSimilarity(leftRaw);
  final right = normalizeForUiStringSimilarity(rightRaw);
  if (left.isEmpty || right.isEmpty) return 0;
  if (left == right) return 1;

  final leftLength = left.length;
  final rightLength = right.length;
  final matchDistance = ((leftLength > rightLength ? leftLength : rightLength) ~/
          2) -
      1;
  final safeMatchDistance = matchDistance < 0 ? 0 : matchDistance;

  final leftMatched = List<bool>.filled(leftLength, false);
  final rightMatched = List<bool>.filled(rightLength, false);
  var matches = 0;

  for (var leftIndex = 0; leftIndex < leftLength; leftIndex++) {
    final start = leftIndex - safeMatchDistance > 0
        ? leftIndex - safeMatchDistance
        : 0;
    final end = leftIndex + safeMatchDistance + 1 < rightLength
        ? leftIndex + safeMatchDistance + 1
        : rightLength;
    for (var rightIndex = start; rightIndex < end; rightIndex++) {
      if (rightMatched[rightIndex]) continue;
      if (left.codeUnitAt(leftIndex) != right.codeUnitAt(rightIndex)) continue;
      leftMatched[leftIndex] = true;
      rightMatched[rightIndex] = true;
      matches++;
      break;
    }
  }

  if (matches == 0) return 0;

  var transpositions = 0;
  var rightCursor = 0;
  for (var leftIndex = 0; leftIndex < leftLength; leftIndex++) {
    if (!leftMatched[leftIndex]) continue;
    while (rightCursor < rightLength && !rightMatched[rightCursor]) {
      rightCursor++;
    }
    if (rightCursor < rightLength &&
        left.codeUnitAt(leftIndex) != right.codeUnitAt(rightCursor)) {
      transpositions++;
    }
    rightCursor++;
  }

  final matchesAsDouble = matches.toDouble();
  final jaro = ((matchesAsDouble / leftLength) +
          (matchesAsDouble / rightLength) +
          ((matchesAsDouble - (transpositions / 2.0)) / matchesAsDouble)) /
      3.0;

  var prefixLength = 0;
  final maxPrefixLength = leftLength < rightLength ? leftLength : rightLength;
  for (var index = 0; index < maxPrefixLength && index < 4; index++) {
    if (left.codeUnitAt(index) != right.codeUnitAt(index)) break;
    prefixLength++;
  }

  const prefixScale = 0.1;
  return jaro + (prefixLength * prefixScale * (1 - jaro));
}

/// Returns best candidate index + score when score is >= [minimumScore].
({int index, double score})? findBestUiStringSimilarityMatch({
  required String source,
  required List<String> candidates,
  double minimumScore = 0.5,
}) {
  if (source.trim().isEmpty || candidates.isEmpty) return null;
  var bestIndex = -1;
  var bestScore = 0.0;
  for (var index = 0; index < candidates.length; index++) {
    final score = normalizedJaroWinklerSimilarity(source, candidates[index]);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = index;
    }
  }
  if (bestIndex < 0 || bestScore < minimumScore) return null;
  return (index: bestIndex, score: bestScore);
}

/// Case-insensitive substring match on [displayName]. Empty [rawQuery] matches all.
bool displayNameMatchesNameSearch(String displayName, String rawQuery) {
  final q = normalizeNameSearchInput(rawQuery);
  if (q.isEmpty) return true;
  return displayName.toLowerCase().contains(q);
}

/// Sort labels for stable alphabetical order (case-insensitive).
int compareDisplayNamesForSort(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

/// Search field shared by invite placeholder picker and trip participants list.
class NameListSearchTextField extends StatelessWidget {
  const NameListSearchTextField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: l10n.nameSearchLabel,
        hintText: l10n.nameSearchHint,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                tooltip: l10n.nameSearchClear,
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
      ),
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
    );
  }
}
