import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/widgets/trip_permission_table_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripCarpoolPermissionsPage extends ConsumerStatefulWidget {
  const TripCarpoolPermissionsPage({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  ConsumerState<TripCarpoolPermissionsPage> createState() =>
      _TripCarpoolPermissionsPageState();
}

class _TripCarpoolPermissionsPageState
    extends ConsumerState<TripCarpoolPermissionsPage> {
  bool _isSavingProposePermission = false;
  bool _isSavingEditPermission = false;
  bool _isSavingMeetupPermission = false;
  bool _isResettingDefaults = false;

  Future<void> _updatePermission({
    required TripCarpoolPermissionAction action,
    required TripPermissionRole minRole,
  }) async {
    if (_isResettingDefaults) return;
    setState(() {
      if (action == TripCarpoolPermissionAction.proposeCarpool) {
        _isSavingProposePermission = true;
      } else if (action == TripCarpoolPermissionAction.editCarpools) {
        _isSavingEditPermission = true;
      } else {
        _isSavingMeetupPermission = true;
      }
    });
    try {
      await ref.read(tripsRepositoryProvider).updateTripCarpoolPermission(
            tripId: widget.tripId,
            action: action,
            minRole: minRole,
          );
    } catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (action == TripCarpoolPermissionAction.proposeCarpool) {
            _isSavingProposePermission = false;
          } else if (action == TripCarpoolPermissionAction.editCarpools) {
            _isSavingEditPermission = false;
          } else {
            _isSavingMeetupPermission = false;
          }
        });
      }
    }
  }

  Future<void> _resetDefaults() async {
    if (_isResettingDefaults ||
        _isSavingProposePermission ||
        _isSavingEditPermission ||
        _isSavingMeetupPermission) {
      return;
    }
    setState(() => _isResettingDefaults = true);
    try {
      await ref
          .read(tripsRepositoryProvider)
          .resetTripCarpoolPermissionsToDefaults(tripId: widget.tripId);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripPermissionsResetDone)),
      );
    } catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isResettingDefaults = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));
    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.tripOverviewTileCarpool)),
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
            appBar: AppBar(title: Text(l10n.tripOverviewTileCarpool)),
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
            title: Text(l10n.tripOverviewTileCarpool),
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
                        l10n.tripOverviewTileCarpool,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.tripCarpoolCreateAction,
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
                        title: l10n.tripCarpoolCreateAction,
                        minRole: trip.carpoolPermissions.proposeCarpoolMinRole,
                        icon: Icons.add_circle_outline,
                        busy: _isSavingProposePermission,
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripCarpoolPermissionAction.proposeCarpool,
                          minRole: role,
                        ),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripCarpoolEditTitle,
                        minRole: trip.carpoolPermissions.editCarpoolsMinRole,
                        icon: Icons.edit_outlined,
                        busy: _isSavingEditPermission,
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripCarpoolPermissionAction.editCarpools,
                          minRole: role,
                        ),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripCarpoolGlobalMeetupTitle,
                        minRole: trip
                            .carpoolPermissions.updateShoppingMeetupPointMinRole,
                        icon: Icons.place_outlined,
                        busy: _isSavingMeetupPermission,
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action:
                              TripCarpoolPermissionAction.updateShoppingMeetupPoint,
                          minRole: role,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  const Spacer(),
                  TextButton.icon(
                    onPressed: (_isResettingDefaults ||
                            _isSavingProposePermission ||
                            _isSavingEditPermission ||
                            _isSavingMeetupPermission)
                        ? null
                        : _resetDefaults,
                    icon: _isResettingDefaults
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(l10n.tripPermissionsResetDefaultsAction),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(l10n.tripOverviewTileCarpool)),
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
