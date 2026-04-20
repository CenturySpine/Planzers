import 'dart:async';

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
  bool _saving = false;
  List<String>? _pendingIds;

  @override
  void initState() {
    super.initState();
    _ids = List<String>.from(widget.initialCatalogIds);
  }

  Future<void> _saveNow(List<String> ids) async {
    if (_saving) return;
    setState(() => _saving = true);
    var target = ids;
    try {
      while (true) {
        await ref
            .read(accountRepositoryProvider)
            .updateFoodAllergenCatalogIds(target);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Allergènes enregistrés'),
              duration: Duration(milliseconds: 1100),
            ),
          );

        final next = _pendingIds;
        if (next == null) {
          break;
        }
        _pendingIds = null;
        target = next;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Erreur enregistrement allergènes: $e')),
        );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _onChanged(List<String> next) {
    setState(() => _ids = next);
    if (_saving) {
      _pendingIds = next;
      return;
    }
    unawaited(_saveNow(next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Allergènes alimentaires')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FoodAllergensListEditor(
              selectedCatalogIds: _ids,
              onChanged: _onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
