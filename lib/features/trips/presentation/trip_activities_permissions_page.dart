import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/widgets/trip_permission_table_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripActivitiesPermissionsPage extends ConsumerStatefulWidget {
  const TripActivitiesPermissionsPage({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  ConsumerState<TripActivitiesPermissionsPage> createState() =>
      _TripActivitiesPermissionsPageState();
}

class _TripActivitiesPermissionsPageState
    extends ConsumerState<TripActivitiesPermissionsPage> {
  TripPermissionRole _suggestActivityMinRole = TripPermissionRole.participant;
  TripPermissionRole _planActivityMinRole = TripPermissionRole.admin;
  TripPermissionRole _editActivityMinRole = TripPermissionRole.participant;
  TripPermissionRole _deleteActivityMinRole = TripPermissionRole.participant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));

    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.tripSectionActivities),
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
        final currentRole = resolveTripPermissionRole(
          trip: trip,
          userId: myUid,
        );
        final canAccessTripSettings = isTripRoleAllowed(
          currentRole: currentRole,
          minRole: trip.generalPermissions.manageTripSettingsMinRole,
        );

        if (!canAccessTripSettings) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.tripSectionActivities),
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
            title: Text(l10n.tripSectionActivities),
            leading: IconButton(
              onPressed: () => context.go('/trips/${widget.tripId}/settings'),
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.commonClose,
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
                      Text(
                        l10n.tripPermissionsActivitiesTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.tripPermissionsActivitiesDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      TripPermissionsColumnsHeader(
                        actionLabel: l10n.tripPermissionsColumnAction,
                        minRoleLabel: l10n.tripPermissionsColumnMinRole,
                      ),
                      const SizedBox(height: 4),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionActivitiesSuggest,
                        minRole: _suggestActivityMinRole,
                        icon: Icons.lightbulb_outline,
                        busy: false,
                        enabled: true,
                        onChanged: (role) => setState(() => _suggestActivityMinRole = role),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionActivitiesPlan,
                        minRole: _planActivityMinRole,
                        icon: Icons.event_available_outlined,
                        busy: false,
                        enabled: true,
                        onChanged: (role) => setState(() => _planActivityMinRole = role),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionActivitiesEdit,
                        minRole: _editActivityMinRole,
                        icon: Icons.edit_outlined,
                        busy: false,
                        enabled: true,
                        onChanged: (role) => setState(() => _editActivityMinRole = role),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionActivitiesDelete,
                        minRole: _deleteActivityMinRole,
                        icon: Icons.delete_outline,
                        busy: false,
                        enabled: true,
                        onChanged: (role) => setState(() => _deleteActivityMinRole = role),
                      ),
                    ],
                  ),
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
          title: Text(l10n.tripSectionActivities),
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
