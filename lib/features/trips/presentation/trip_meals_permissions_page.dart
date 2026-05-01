import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/widgets/trip_permission_table_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripMealsPermissionsPage extends ConsumerStatefulWidget {
  const TripMealsPermissionsPage({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  ConsumerState<TripMealsPermissionsPage> createState() =>
      _TripMealsPermissionsPageState();
}

class _TripMealsPermissionsPageState
    extends ConsumerState<TripMealsPermissionsPage> {
  final Set<TripMealsPermissionAction> _savingActions =
      <TripMealsPermissionAction>{};
  bool _isResettingDefaults = false;

  Future<void> _updatePermission({
    required TripMealsPermissionAction action,
    required TripPermissionRole minRole,
  }) async {
    if (_savingActions.contains(action) || _isResettingDefaults) return;
    setState(() => _savingActions.add(action));
    try {
      await ref.read(tripsRepositoryProvider).updateTripMealsPermission(
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
          .resetTripMealsPermissionsToDefaults(tripId: widget.tripId);
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
              title: Text(l10n.tripSectionMeals),
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
        final currentRole = resolveTripPermissionRole(
          trip: trip,
          userId: currentUserId,
        );
        final canAccessTripSettings = isTripRoleAllowed(
          currentRole: currentRole,
          minRole: trip.generalPermissions.manageTripSettingsMinRole,
        );
        if (!canAccessTripSettings) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.tripSectionMeals),
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
            title: Text(l10n.tripSectionMeals),
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
                        l10n.tripPermissionsMealsTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.tripPermissionsMealsDescription,
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
                        title: l10n.tripPermissionMealsCreate,
                        minRole: trip.mealsPermissions.createMealMinRole,
                        icon: Icons.add_circle_outline,
                        busy: _savingActions.contains(
                          TripMealsPermissionAction.createMeal,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripMealsPermissionAction.createMeal,
                          minRole: role,
                        ),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionMealsDelete,
                        minRole: trip.mealsPermissions.deleteMealMinRole,
                        icon: Icons.delete_outline,
                        iconColor: Theme.of(context).colorScheme.error,
                        busy: _savingActions.contains(
                          TripMealsPermissionAction.deleteMeal,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripMealsPermissionAction.deleteMeal,
                          minRole: role,
                        ),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionMealsEdit,
                        minRole: trip.mealsPermissions.editMealMinRole,
                        icon: Icons.edit_outlined,
                        busy: _savingActions.contains(
                          TripMealsPermissionAction.editMeal,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripMealsPermissionAction.editMeal,
                          minRole: role,
                        ),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionMealsSuggestRestaurant,
                        minRole: trip.mealsPermissions.suggestRestaurantMinRole,
                        icon: Icons.restaurant_menu_outlined,
                        busy: _savingActions.contains(
                          TripMealsPermissionAction.suggestRestaurant,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripMealsPermissionAction.suggestRestaurant,
                          minRole: role,
                        ),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionMealsAddContribution,
                        minRole: trip.mealsPermissions.addContributionMinRole,
                        icon: Icons.volunteer_activism_outlined,
                        busy: _savingActions.contains(
                          TripMealsPermissionAction.addContribution,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripMealsPermissionAction.addContribution,
                          minRole: role,
                        ),
                      ),
                      TripPermissionItemRow(
                        title: l10n.tripPermissionMealsManageRecipe,
                        minRole: trip.mealsPermissions.manageRecipeMinRole,
                        icon: Icons.menu_book_outlined,
                        availableRoles: const <TripPermissionRole>[
                          TripPermissionRole.participant,
                          TripPermissionRole.chef,
                          TripPermissionRole.admin,
                          TripPermissionRole.owner,
                        ],
                        busy: _savingActions.contains(
                          TripMealsPermissionAction.manageRecipe,
                        ),
                        enabled: !_isResettingDefaults,
                        onChanged: (role) => _updatePermission(
                          action: TripMealsPermissionAction.manageRecipe,
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
          title: Text(l10n.tripSectionMeals),
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
