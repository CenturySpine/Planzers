import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:planzers/features/ingredients/data/ingredient_catalog_item.dart';
import 'package:planzers/features/ingredients/data/ingredient_catalog_repository.dart';

/// Add/remove allergen catalog ids with autocomplete (catalog type `allergen`).
class FoodAllergensListEditor extends ConsumerStatefulWidget {
  const FoodAllergensListEditor({
    super.key,
    required this.selectedCatalogIds,
    required this.onChanged,
  });

  final List<String> selectedCatalogIds;
  final ValueChanged<List<String>> onChanged;

  @override
  ConsumerState<FoodAllergensListEditor> createState() =>
      _FoodAllergensListEditorState();
}

class _FoodAllergensListEditorState
    extends ConsumerState<FoodAllergensListEditor> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _removeId(String id) {
    final next = List<String>.from(widget.selectedCatalogIds)
      ..removeWhere((e) => e == id);
    widget.onChanged(next);
  }

  void _addId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    if (widget.selectedCatalogIds.contains(trimmed)) return;
    widget.onChanged([...widget.selectedCatalogIds, trimmed]);
    _controller.clear();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(allergenCatalogItemsProvider);
    final catalogItems = catalogAsync.asData?.value;
    final idToLabel = <String, String>{
      if (catalogItems != null) for (final i in catalogItems) i.id: i.label,
    };

    final query = _controller.text.trim();
    final suggestionsAsync = ref.watch(allergenAutocompleteProvider(query));
    final showSuggestions = _focusNode.hasFocus && query.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Allergènes et intolérances',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (widget.selectedCatalogIds.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in widget.selectedCatalogIds)
                InputChip(
                  label: Text(idToLabel[id] ?? id),
                  onDeleted: () => _removeId(id),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Ajouter…',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (raw) {
            final match = _firstExactLabelMatch(
              catalogAsync.asData?.value,
              raw.trim(),
            );
            if (match != null) {
              _addId(match.id);
            }
          },
        ),
        if (showSuggestions)
          suggestionsAsync.when(
            data: (list) {
              final filtered = list.take(8).toList(growable: false);
              if (filtered.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    children: [
                      for (final item in filtered)
                        ListTile(
                          dense: true,
                          title: Text(item.label),
                          onTap: () => _addId(item.id),
                        ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
      ],
    );
  }

  IngredientCatalogItem? _firstExactLabelMatch(
    List<IngredientCatalogItem>? items,
    String raw,
  ) {
    if (items == null || raw.isEmpty) return null;
    final q = raw.trim().toLowerCase();
    for (final i in items) {
      if (i.label.trim().toLowerCase() == q) return i;
    }
    return null;
  }
}
