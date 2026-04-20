import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';

class TripSettingsPage extends ConsumerWidget {
  const TripSettingsPage({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripStreamProvider(tripId));

    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Paramètres du voyage'),
            ),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Voyage introuvable ou acces refuse.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
        final myRole = _roleLabelFor(
          uid: myUid,
          ownerId: trip.ownerId,
          adminMemberIds: trip.adminMemberIds,
        );
        final title = trip.title.trim().isEmpty ? 'Voyage' : trip.title.trim();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Paramètres du voyage'),
            leading: IconButton(
              onPressed: () => context.go('/trips/$tripId/overview'),
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Retour au voyage',
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('Mon rôle: $myRole'),
                      const SizedBox(height: 4),
                      Text(
                        'Hiérarchie des privilèges: créateur > admin > participant',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const _SettingsSectionCard(
                title: 'Voyage',
                icon: Icons.luggage_outlined,
                description:
                    'Règles liées aux informations générales du voyage.',
              ),
              const _SettingsSectionCard(
                title: 'Dépenses',
                icon: Icons.payments_outlined,
                description: 'Gestion des droits sur les dépenses du voyage.',
              ),
              const _SettingsSectionCard(
                title: 'Activités',
                icon: Icons.event_available_outlined,
                description: 'Gestion des droits sur les activités proposées.',
              ),
              const _SettingsSectionCard(
                title: 'Repas',
                icon: Icons.restaurant_outlined,
                description: 'Gestion des droits sur les repas et menus.',
              ),
              const _SettingsSectionCard(
                title: 'Courses',
                icon: Icons.shopping_cart_outlined,
                description: 'Gestion des droits sur les listes de courses.',
              ),
              const _SettingsSectionCard(
                title: 'Participants',
                icon: Icons.group_outlined,
                description: 'Gestion des droits liés aux membres du voyage.',
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Paramètres du voyage'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Erreur: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

String _roleLabelFor({
  required String? uid,
  required String ownerId,
  required List<String> adminMemberIds,
}) {
  final currentUid = uid?.trim() ?? '';
  if (currentUid.isEmpty) return 'Participant';
  if (currentUid == ownerId.trim()) return 'Créateur';
  if (adminMemberIds.contains(currentUid)) return 'Admin';
  return 'Participant';
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    required this.icon,
    required this.description,
  });

  final String title;
  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
