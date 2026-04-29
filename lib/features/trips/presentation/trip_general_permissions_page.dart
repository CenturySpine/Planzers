import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/widgets/trip_permission_table_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripGeneralPermissionsPage extends ConsumerStatefulWidget {
  const TripGeneralPermissionsPage({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  ConsumerState<TripGeneralPermissionsPage> createState() =>
      _TripGeneralPermissionsPageState();
}

class _TripGeneralPermissionsPageState
    extends ConsumerState<TripGeneralPermissionsPage> {
  final Set<TripGeneralPermissionAction> _savingActions = <TripGeneralPermissionAction>{};
  bool _isResettingDefaults = false;

  Future<void> _updatePermission({
    required TripGeneralPermissionAction action,
    required TripPermissionRole minRole,
  }) async {
    if (_savingActions.contains(action)) return;
    setState(() => _savingActions.add(action));
    try {
      await ref.read(tripsRepositoryProvider).updateTripGeneralPermission(
            tripId: widget.tripId,
            action: action,
            minRole: minRole,
          );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _savingActions.remove(action));
      }
    }
  }

  Future<void> _resetDefaults() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isResettingDefaults || _savingActions.isNotEmpty) return;
    setState(() => _isResettingDefaults = true);
    try {
      await ref.read(tripsRepositoryProvider).resetTripGeneralPermissionsToDefaults(
            tripId: widget.tripId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripPermissionsResetDone)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
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
            appBar: AppBar(
              title: Text(l10n.tripSectionTrip),
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
              title: Text(l10n.tripSectionTrip),
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
            title: Text(l10n.tripSectionTrip),
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
                        l10n.tripGeneralPermissionsTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.tripGeneralPermissionsDescription,
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
                        title: l10n.tripPermissionEditGeneralInfo,
                        minRole: trip.generalPermissions.editGeneralInfoMinRole,
                        icon: Icons.edit_outlined,
                        busy: _savingActions.contains(
                          TripGeneralPermissionAction.editGeneralInfo,
                        ),
                        onChanged: (role) => _updatePermission(
                          action: TripGeneralPermissionAction.editGeneralInfo,
                          minRole: role,
                        ),
                        enabled: !_isResettingDefaults,
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionManageBanner,
                        minRole: trip.generalPermissions.manageBannerMinRole,
                        icon: Icons.photo_camera_outlined,
                        busy: _savingActions.contains(
                          TripGeneralPermissionAction.manageBanner,
                        ),
                        onChanged: (role) => _updatePermission(
                          action: TripGeneralPermissionAction.manageBanner,
                          minRole: role,
                        ),
                        enabled: !_isResettingDefaults,
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionPublishAnnouncements,
                        minRole: trip.generalPermissions.publishAnnouncementsMinRole,
                        icon: Icons.campaign_outlined,
                        busy: _savingActions.contains(
                          TripGeneralPermissionAction.publishAnnouncements,
                        ),
                        onChanged: (role) => _updatePermission(
                          action: TripGeneralPermissionAction.publishAnnouncements,
                          minRole: role,
                        ),
                        enabled: !_isResettingDefaults,
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionShareAccess,
                        minRole: trip.generalPermissions.shareAccessMinRole,
                        icon: Icons.share_outlined,
                        busy: _savingActions.contains(
                          TripGeneralPermissionAction.shareAccess,
                        ),
                        onChanged: (role) => _updatePermission(
                          action: TripGeneralPermissionAction.shareAccess,
                          minRole: role,
                        ),
                        enabled: !_isResettingDefaults,
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionManageTripSettings,
                        minRole: trip.generalPermissions.manageTripSettingsMinRole,
                        icon: Icons.settings_outlined,
                        busy: _savingActions.contains(
                          TripGeneralPermissionAction.manageTripSettings,
                        ),
                        onChanged: (role) => _updatePermission(
                          action: TripGeneralPermissionAction.manageTripSettings,
                          minRole: role,
                        ),
                        enabled: !_isResettingDefaults,
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionDeleteTrip,
                        minRole: TripPermissionRole.owner,
                        icon: Icons.delete,
                        iconColor: Theme.of(context).colorScheme.error,
                        busy: _savingActions.contains(
                          TripGeneralPermissionAction.deleteTrip,
                        ),
                        onChanged: (role) => _updatePermission(
                          action: TripGeneralPermissionAction.deleteTrip,
                          minRole: role,
                        ),
                        enabled: false,
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  const Spacer(),
                  TextButton.icon(
                    onPressed: (_isResettingDefaults || _savingActions.isNotEmpty)
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
        appBar: AppBar(
          title: Text(l10n.tripSectionTrip),
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

