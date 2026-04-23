import 'package:flutter/material.dart';

/// Message when a non-empty search yields no rows (invite + participants).
const String kNameListSearchEmptyMessage = 'Aucun nom ne correspond.';

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
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: 'Rechercher',
        hintText: 'Filtrer par nom',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Effacer',
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
