import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripSettingsPermissionsPage extends ConsumerWidget {
  const TripSettingsPermissionsPage({
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
              title: Text(l10n.tripSettingsPermissionsSectionTitle),
              leading: IconButton(
                onPressed: () => context.go('/trips/$tripId/settings'),
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.tripBackToTrip,
              ),
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

        final currentUserId = FirebaseAuth.instance.currentUser?.uid.trim();
        final currentRole =
            resolveTripPermissionRole(trip: trip, userId: currentUserId);
        final canAccessTripSettings = isTripRoleAllowed(
          currentRole: currentRole,
          minRole: trip.generalPermissions.manageTripSettingsMinRole,
        );
        if (!canAccessTripSettings) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.tripSettingsPermissionsSectionTitle),
              leading: IconButton(
                onPressed: () => context.go('/trips/$tripId/settings'),
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.tripBackToTrip,
              ),
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

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.tripSettingsPermissionsSectionTitle),
            leading: IconButton(
              onPressed: () => context.go('/trips/$tripId/settings'),
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.tripBackToTrip,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SettingsSectionCard(
                title: l10n.tripSectionTrip,
                icon: Icons.luggage_outlined,
                description: l10n.tripSectionTripDescription,
                onTap: () =>
                    context.push('/trips/$tripId/settings/permissions/trip'),
              ),
              _SettingsSectionCard(
                title: l10n.tripSectionParticipants,
                icon: Icons.group_outlined,
                description: l10n.tripSectionParticipantsDescription,
                onTap: () => context
                    .push('/trips/$tripId/settings/permissions/participants'),
              ),
              _SettingsSectionCard(
                title: l10n.tripSectionExpenses,
                icon: Icons.payments_outlined,
                description: l10n.tripSectionExpensesDescription,
                onTap: () => context
                    .push('/trips/$tripId/settings/permissions/expenses'),
              ),
              _SettingsSectionCard(
                title: l10n.tripSectionActivities,
                icon: Icons.event_available_outlined,
                description: l10n.tripSectionActivitiesDescription,
                onTap: () => context
                    .push('/trips/$tripId/settings/permissions/activities'),
              ),
              _SettingsSectionCard(
                title: l10n.tripSectionMeals,
                icon: Icons.restaurant_outlined,
                description: l10n.tripSectionMealsDescription,
                onTap: () =>
                    context.push('/trips/$tripId/settings/permissions/meals'),
              ),
              _SettingsSectionCard(
                title: l10n.tripOverviewTileCarpool,
                icon: Icons.directions_car_outlined,
                description: l10n.tripCarpoolCreateAction,
                onTap: () => context
                    .push('/trips/$tripId/settings/permissions/carpool'),
              ),
              _SettingsSectionCard(
                title: l10n.tripSectionShopping,
                icon: Icons.shopping_cart_outlined,
                description: l10n.tripSectionShoppingDescription,
                onTap: () => context
                    .push('/trips/$tripId/settings/permissions/shopping'),
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
          title: Text(l10n.tripSettingsPermissionsSectionTitle),
          leading: IconButton(
            onPressed: () => context.go('/trips/$tripId/settings'),
            icon: const Icon(Icons.arrow_back),
            tooltip: l10n.tripBackToTrip,
          ),
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
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
