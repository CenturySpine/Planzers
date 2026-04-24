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
  bool _isSavingSuggestPermission = false;
  bool _isSavingPlanPermission = false;
  bool _isSavingEditPermission = false;
  bool _isSavingDeletePermission = false;
  bool _isResettingDefaults = false;

  bool get _isAnySaving =>
      _isSavingSuggestPermission ||
      _isSavingPlanPermission ||
      _isSavingEditPermission ||
      _isSavingDeletePermission;

  Future<void> _updateSuggestPermission({
    required TripPermissionRole minRole,
  }) async {
    if (_isSavingSuggestPermission || _isResettingDefaults) return;
    setState(() => _isSavingSuggestPermission = true);
    try {
      await ref.read(tripsRepositoryProvider).updateTripActivitiesPermission(
            tripId: widget.tripId,
            action: TripActivitiesPermissionAction.suggestActivity,
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
        setState(() => _isSavingSuggestPermission = false);
      }
    }
  }

  Future<void> _updatePlanPermission({
    required TripPermissionRole minRole,
  }) async {
    if (_isSavingPlanPermission || _isResettingDefaults) return;
    setState(() => _isSavingPlanPermission = true);
    try {
      await ref.read(tripsRepositoryProvider).updateTripActivitiesPermission(
            tripId: widget.tripId,
            action: TripActivitiesPermissionAction.planActivity,
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
        setState(() => _isSavingPlanPermission = false);
      }
    }
  }

  Future<void> _updateEditPermission({
    required TripPermissionRole minRole,
  }) async {
    if (_isSavingEditPermission || _isResettingDefaults) return;
    setState(() => _isSavingEditPermission = true);
    try {
      await ref.read(tripsRepositoryProvider).updateTripActivitiesPermission(
            tripId: widget.tripId,
            action: TripActivitiesPermissionAction.editActivity,
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
        setState(() => _isSavingEditPermission = false);
      }
    }
  }

  Future<void> _updateDeletePermission({
    required TripPermissionRole minRole,
  }) async {
    if (_isSavingDeletePermission || _isResettingDefaults) return;
    setState(() => _isSavingDeletePermission = true);
    try {
      await ref.read(tripsRepositoryProvider).updateTripActivitiesPermission(
            tripId: widget.tripId,
            action: TripActivitiesPermissionAction.deleteActivity,
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
        setState(() => _isSavingDeletePermission = false);
      }
    }
  }

  Future<void> _resetDefaults() async {
    if (_isResettingDefaults || _isAnySaving) return;
    setState(() => _isResettingDefaults = true);
    try {
      await ref
          .read(tripsRepositoryProvider)
          .resetTripActivitiesPermissionsToDefaults(tripId: widget.tripId);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripPermissionsResetDone)),
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
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
                        minRole: trip.activitiesPermissions.suggestActivityMinRole,
                        icon: Icons.lightbulb_outline,
                        busy: _isSavingSuggestPermission,
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updateSuggestPermission(minRole: role),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionActivitiesPlan,
                        minRole: trip.activitiesPermissions.planActivityMinRole,
                        icon: Icons.event_available_outlined,
                        busy: _isSavingPlanPermission,
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePlanPermission(minRole: role),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionActivitiesEdit,
                        minRole: trip.activitiesPermissions.editActivityMinRole,
                        icon: Icons.edit_outlined,
                        busy: _isSavingEditPermission,
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updateEditPermission(minRole: role),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionActivitiesDelete,
                        minRole: trip.activitiesPermissions.deleteActivityMinRole,
                        icon: Icons.delete_outline,
                        busy: _isSavingDeletePermission,
                        enabled: !_isResettingDefaults,
                        onChanged: (role) =>
                            _updateDeletePermission(minRole: role),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  const Spacer(),
                  TextButton.icon(
                    onPressed: (_isResettingDefaults || _isAnySaving)
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
