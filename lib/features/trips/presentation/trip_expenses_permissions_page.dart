import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/widgets/trip_permission_table_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripExpensesPermissionsPage extends ConsumerStatefulWidget {
  const TripExpensesPermissionsPage({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  ConsumerState<TripExpensesPermissionsPage> createState() =>
      _TripExpensesPermissionsPageState();
}

class _TripExpensesPermissionsPageState
    extends ConsumerState<TripExpensesPermissionsPage> {
  final Set<TripExpensesPermissionAction> _savingActions =
      <TripExpensesPermissionAction>{};
  bool _isResettingDefaults = false;

  Future<void> _updatePermission({
    required TripExpensesPermissionAction action,
    required TripPermissionRole minRole,
  }) async {
    if (_savingActions.contains(action) || _isResettingDefaults) return;
    setState(() => _savingActions.add(action));
    try {
      await ref.read(tripsRepositoryProvider).updateTripExpensesPermission(
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
    if (_isResettingDefaults) return;
    setState(() => _isResettingDefaults = true);
    try {
      await ref
          .read(tripsRepositoryProvider)
          .resetTripExpensesPermissionsToDefaults(tripId: widget.tripId);
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
              title: Text(l10n.tripSectionExpenses),
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
              title: Text(l10n.tripSectionExpenses),
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
            title: Text(l10n.tripSectionExpenses),
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
                        l10n.tripPermissionsExpensesTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.tripPermissionsExpensesDescription,
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
                        title: l10n.tripPermissionExpensesCreatePost,
                        minRole: trip.expensesPermissions.createExpensePostMinRole,
                        icon: Icons.create_new_folder_outlined,
                        busy: _savingActions.contains(
                          TripExpensesPermissionAction.createExpensePost,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripExpensesPermissionAction.createExpensePost,
                          minRole: role,
                        ),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionExpensesEditPost,
                        minRole: trip.expensesPermissions.editExpensePostMinRole,
                        icon: Icons.edit_outlined,
                        busy: _savingActions.contains(
                          TripExpensesPermissionAction.editExpensePost,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripExpensesPermissionAction.editExpensePost,
                          minRole: role,
                        ),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionExpensesDeletePost,
                        minRole: trip.expensesPermissions.deleteExpensePostMinRole,
                        icon: Icons.delete,
                        iconColor: Theme.of(context).colorScheme.error,
                        busy: _savingActions.contains(
                          TripExpensesPermissionAction.deleteExpensePost,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripExpensesPermissionAction.deleteExpensePost,
                          minRole: role,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionExpensesCreateExpense,
                        minRole: trip.expensesPermissions.createExpenseMinRole,
                        icon: Icons.add_circle_outline,
                        busy: _savingActions.contains(
                          TripExpensesPermissionAction.createExpense,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripExpensesPermissionAction.createExpense,
                          minRole: role,
                        ),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionExpensesEditExpense,
                        minRole: trip.expensesPermissions.editExpenseMinRole,
                        icon: Icons.edit_note_outlined,
                        busy: _savingActions.contains(
                          TripExpensesPermissionAction.editExpense,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripExpensesPermissionAction.editExpense,
                          minRole: role,
                        ),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionExpensesDeleteExpense,
                        minRole: trip.expensesPermissions.deleteExpenseMinRole,
                        icon: Icons.remove_circle_outline,
                        busy: _savingActions.contains(
                          TripExpensesPermissionAction.deleteExpense,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripExpensesPermissionAction.deleteExpense,
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
          title: Text(l10n.tripSectionExpenses),
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

