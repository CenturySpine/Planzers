import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/data/trip_placeholder_member.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';

class TripPlaceholdersPage extends ConsumerStatefulWidget {
  const TripPlaceholdersPage({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripPlaceholdersPage> createState() =>
      _TripPlaceholdersPageState();
}

class _TripPlaceholdersPageState extends ConsumerState<TripPlaceholdersPage> {
  static String _messageForError(Object e) {
    if (e is FirebaseFunctionsException) {
      final m = e.message;
      if (m != null && m.trim().isNotEmpty) {
        return m.trim();
      }
    }
    return e.toString();
  }

  Future<void> _openAddDialog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter un voyageur prévu'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    // Read text before dispose; defer dispose until after the route removes the
    // TextField (disposing while the dialog is still animating breaks framework
    // assertions on InheritedWidget dependents).
    final name = ok == true ? controller.text.trim() : '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (ok != true || !mounted) return;
    if (name.isEmpty) return;
    try {
      await ref.read(tripsRepositoryProvider).addTripPlaceholderMember(
            tripId: widget.tripId,
            displayName: name,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voyageur prévu ajouté')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(e))),
      );
    }
  }

  Future<void> _openEditDialog({
    required String placeholderId,
    required String currentName,
  }) async {
    final controller = TextEditingController(text: currentName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le nom'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    final name = ok == true ? controller.text.trim() : '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (ok != true || !mounted) return;
    if (name.isEmpty) return;
    try {
      await ref.read(tripsRepositoryProvider).updateTripPlaceholderMemberName(
            tripId: widget.tripId,
            placeholderId: placeholderId,
            displayName: name,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom mis à jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(e))),
      );
    }
  }

  Future<void> _confirmRemove({
    required String placeholderId,
    required String label,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer ce voyageur prévu ?'),
        content: Text('« $label » sera retiré de la liste des voyageurs prévus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(tripsRepositoryProvider).removeTripPlaceholderMember(
            tripId: widget.tripId,
            placeholderId: placeholderId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voyageur prévu retiré')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(e))),
      );
    }
  }

  List<_PlaceholderRow> _rowsForTrip(Trip trip) {
    final labels = trip.memberPublicLabels;
    return trip.memberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .where(isTripPlaceholderMemberId)
        .map(
          (id) => _PlaceholderRow(
            id: id,
            label: (labels[id]?.trim().isNotEmpty ?? false)
                ? labels[id]!.trim()
                : 'Voyageur',
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final asyncTrip = ref.watch(tripStreamProvider(widget.tripId));

    return asyncTrip.when(
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Voyageurs prévus')),
            body: const Center(child: Text('Voyage introuvable')),
          );
        }
        final rows = _rowsForTrip(trip);
        return Scaffold(
          appBar: AppBar(title: const Text('Voyageurs prévus')),
          body: rows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aucun voyageur prévu.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return Card(
                      child: ListTile(
                        title: Text(row.label),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Modifier',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _openEditDialog(
                                placeholderId: row.id,
                                currentName: row.label,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Retirer',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _confirmRemove(
                                placeholderId: row.id,
                                label: row.label,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: _openAddDialog,
            tooltip: 'Ajouter',
            child: const Icon(Icons.add),
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Voyageurs prévus')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Voyageurs prévus')),
        body: Center(child: Text('$e')),
      ),
    );
  }
}

class _PlaceholderRow {
  const _PlaceholderRow({required this.id, required this.label});

  final String id;
  final String label;
}
