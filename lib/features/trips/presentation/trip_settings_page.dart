import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';

class TripSettingsPage extends ConsumerWidget {
  const TripSettingsPage({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final tripAsync = ref.watch(tripStreamProvider(tripId));

    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.tripSettingsTitle),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.tripNotFoundOrNoAccess,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
        final myRole = _roleLabelFor(
          l10n: l10n,
          uid: myUid,
          ownerId: trip.ownerId,
          adminMemberIds: trip.adminMemberIds,
        );
        final title = trip.title.trim().isEmpty ? l10n.tripLabelGeneric : trip.title.trim();

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.tripSettingsTitle),
            leading: IconButton(
              onPressed: () => context.go('/trips/$tripId/overview'),
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.tripBackToTrip,
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
                      Text(l10n.tripMyRole(myRole)),
                      const SizedBox(height: 4),
                      Text(
                        l10n.tripRoleHierarchyHint,
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
              _SettingsSectionCard(
                title: l10n.tripSectionTrip,
                icon: Icons.luggage_outlined,
                description: l10n.tripSectionTripDescription,
                onTap: () => context.push('/trips/$tripId/settings/trip'),
              ),
              _SettingsSectionCard(
                title: l10n.tripSectionExpenses,
                icon: Icons.payments_outlined,
                description: l10n.tripSectionExpensesDescription,
              ),
              _SettingsSectionCard(
                title: l10n.tripSectionActivities,
                icon: Icons.event_available_outlined,
                description: l10n.tripSectionActivitiesDescription,
              ),
              _SettingsSectionCard(
                title: l10n.tripSectionMeals,
                icon: Icons.restaurant_outlined,
                description: l10n.tripSectionMealsDescription,
              ),
              _SettingsSectionCard(
                title: l10n.tripSectionShopping,
                icon: Icons.shopping_cart_outlined,
                description: l10n.tripSectionShoppingDescription,
              ),
              _SettingsSectionCard(
                title: l10n.tripSectionParticipants,
                icon: Icons.group_outlined,
                description: l10n.tripSectionParticipantsDescription,
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
          title: Text(l10n.tripSettingsTitle),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.commonErrorWithDetails(error.toString()),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

String _roleLabelFor({
  required AppLocalizations l10n,
  required String? uid,
  required String ownerId,
  required List<String> adminMemberIds,
}) {
  final currentUid = uid?.trim() ?? '';
  if (currentUid.isEmpty) return l10n.roleParticipant;
  if (currentUid == ownerId.trim()) return l10n.roleOwner;
  if (adminMemberIds.contains(currentUid)) return l10n.roleAdmin;
  return l10n.roleParticipant;
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    required this.icon,
    required this.description,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
