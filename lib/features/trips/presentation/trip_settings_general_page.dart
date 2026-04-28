import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripSettingsGeneralPage extends ConsumerWidget {
  const TripSettingsGeneralPage({
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
              title: Text(l10n.tripSettingsGeneralSectionTitle),
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
              title: Text(l10n.tripSettingsGeneralSectionTitle),
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
            title: Text(l10n.tripSettingsGeneralSectionTitle),
            leading: IconButton(
              onPressed: () => context.go('/trips/$tripId/settings'),
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.tripBackToTrip,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: Text(l10n.tripSettingsGeneralComingSoonTitle),
                  subtitle: Text(l10n.tripSettingsGeneralComingSoonDescription),
                ),
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
          title: Text(l10n.tripSettingsGeneralSectionTitle),
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
