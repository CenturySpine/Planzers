import 'package:flutter/material.dart';
import 'package:planerz/l10n/app_localizations.dart';

String nameListSearchEmptyMessage(BuildContext context) {
  return AppLocalizations.of(context)!.nameSearchEmpty;
}

/// Same normalization as the invite “pick your name” flow: trim + lowercase.
String normalizeNameSearchInput(String raw) => raw.trim().toLowerCase();

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
