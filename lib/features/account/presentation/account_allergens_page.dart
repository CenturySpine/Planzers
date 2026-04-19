import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:planzers/features/account/data/account_repository.dart';
import 'package:planzers/features/ingredients/presentation/food_allergens_list_editor.dart';

/// Full-screen allergen editor (avoids dialog resizing when suggestions open).
class AccountAllergensPage extends ConsumerStatefulWidget {
  const AccountAllergensPage({super.key, required this.initialCatalogIds});

  final List<String> initialCatalogIds;

  @override
  ConsumerState<AccountAllergensPage> createState() =>
      _AccountAllergensPageState();
}

class _AccountAllergensPageState extends ConsumerState<AccountAllergensPage> {
  late List<String> _ids;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ids = List<String>.from(widget.initialCatalogIds);
  }

  Future<void> _leave() async {
    if (_saving) return;
    if (_dirty) {
      setState(() => _saving = true);
      try {
        await ref.read(accountRepositoryProvider).updateFoodAllergenCatalogIds(
              _ids,
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Allergènes enregistrés')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
        setState(() => _saving = false);
        return;
      }
      if (mounted) {
        setState(() => _saving = false);
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _saving ? null : _leave,
            tooltip: 'Retour',
          ),
          title: const Text('Allergènes alimentaires'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FoodAllergensListEditor(
                selectedCatalogIds: _ids,
                onChanged: (next) {
                  setState(() {
                    _ids = next;
                    _dirty = true;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
