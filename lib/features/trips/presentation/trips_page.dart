import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/features/account/presentation/account_menu_button.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';

class TripsPage extends ConsumerWidget {
  const TripsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(tripsStreamProvider);
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes voyages'),
        actions: [
          const AccountMenuButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateTripDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau voyage'),
      ),
      body: tripsAsync.when(
        data: (trips) {
          if (trips.isEmpty) {
            return const Center(
              child: Text(
                'Aucun voyage pour le moment.\nCree ton premier voyage.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.separated(
            itemCount: trips.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final trip = trips[index];
              final canDelete = (myUid != null && trip.ownerId == myUid);
              return ListTile(
                onTap: () => context.push('/trips/${trip.id}', extra: trip),
                title: Text(trip.title),
                subtitle: Text(trip.destination),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${trip.memberIds.length} membre(s)'),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right),
                    if (canDelete) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Supprimer',
                        onPressed: () => _confirmAndDeleteTrip(
                          context,
                          ref,
                          tripId: trip.id,
                          tripTitle: trip.title,
                        ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Erreur Firestore: $error'),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateTripDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final titleController = TextEditingController();
    final destinationController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Creer un voyage'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Titre'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: destinationController,
                    decoration: const InputDecoration(labelText: 'Destination'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    final destination = destinationController.text.trim();

                    if (title.isEmpty || destination.isEmpty) {
                      setDialogState(() {
                        error = 'Titre et destination obligatoires';
                      });
                      return;
                    }

                    try {
                      await ref.read(tripsRepositoryProvider).createTrip(
                            title: title,
                            destination: destination,
                          );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    } catch (e) {
                      setDialogState(() {
                        error = e.toString();
                      });
                    }
                  },
                  child: const Text('Creer'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    destinationController.dispose();
  }

  Future<void> _confirmAndDeleteTrip(
    BuildContext context,
    WidgetRef ref, {
    required String tripId,
    required String tripTitle,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer ce voyage ?'),
          content: Text(
            'Cette action est definitive.\n\nVoyage: $tripTitle',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ref.read(tripsRepositoryProvider).deleteTrip(tripId: tripId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voyage supprime')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur suppression: $e')),
      );
    }
  }
}
