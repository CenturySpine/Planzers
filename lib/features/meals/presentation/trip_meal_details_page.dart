import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/ingredients/data/ingredient_catalog_item.dart';
import 'package:planerz/features/ingredients/data/ingredient_catalog_repository.dart';
import 'package:planerz/features/meals/data/meal_component_risks.dart';
import 'package:planerz/features/meals/data/meals_repository.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/meals/presentation/meal_component_editor_page.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripMealDetailsPage extends ConsumerStatefulWidget {
  const TripMealDetailsPage({
    super.key,
    required this.tripId,
    this.mealId,
  });

  final String tripId;
  final String? mealId;

  bool get isCreate => mealId == null || mealId!.trim().isEmpty;

  @override
  ConsumerState<TripMealDetailsPage> createState() =>
      _TripMealDetailsPageState();
}

class _TripMealDetailsPageState extends ConsumerState<TripMealDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _restaurantUrlController;
  bool _isSaving = false;
  bool _isSavingDate = false;
  bool _isSavingMealDayPart = false;
  bool _isSavingMealMode = false;
  bool _isSavingParticipants = false;
  bool _isSavingPotluckItems = false;
  bool _isSavingRestaurantUrl = false;
  bool _isSavingComponents = false;
  bool _isDeleting = false;
  bool _isHydrated = false;
  DateTime _mealDate = DateUtils.dateOnly(DateTime.now());
  TripDayPart _mealDayPart = TripDayPart.midday;
  Set<String> _participantIds = <String>{};
  String? _chefParticipantId;
  List<MealComponent> _components = const [];
  bool _componentsUserOrdered = false;
  _MealDetailsView _activeMealView = _MealDetailsView.cooked;
  List<MealPotluckItem> _potluckItems = const [];
  bool _isRestaurantLinkEditing = false;
  String _restaurantUrl = '';

  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  bool _isComponentLockedByOther(MealComponent component) {
    final lockOwner = (component.lockedBy ?? '').trim();
    return lockOwner.isNotEmpty && lockOwner != _currentUserId;
  }

  @override
  void initState() {
    super.initState();
    _restaurantUrlController = TextEditingController();
  }

  @override
  void dispose() {
    _restaurantUrlController.dispose();
    super.dispose();
  }

  String get _mealDateKey => TripMemberStay.dateKeyFromDateTime(_mealDate);

  String _componentKindLabel(AppLocalizations l10n, MealComponentKind kind) {
    return switch (kind) {
      MealComponentKind.entree => l10n.mealComponentKindEntree,
      MealComponentKind.plat => l10n.mealComponentKindMain,
      MealComponentKind.dessert => l10n.mealComponentKindDessert,
    };
  }

  Future<String?> _showPotluckItemDialog({
    required String title,
    String initialValue = '',
    required String confirmLabel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    var draft = initialValue;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.mealPotluckItemLabel,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => draft = value,
          onFieldSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(draft.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _addPotluckItem() async {
    final l10n = AppLocalizations.of(context)!;
    final value = await _showPotluckItemDialog(
      title: l10n.mealPotluckAddItemTitle,
      confirmLabel: l10n.commonAdd,
    );
    if (!mounted) return;
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final previousItems = _potluckItems;
    setState(() {
      _potluckItems = [
        ..._potluckItems,
        MealPotluckItem(
          id: 'potluck_${DateTime.now().microsecondsSinceEpoch}_${_potluckItems.length}',
          label: trimmed,
          addedBy: uid,
        ),
      ];
    });
    await _savePotluckItems(previousItems: previousItems);
  }

  Future<void> _editPotluckItem(int index) async {
    final l10n = AppLocalizations.of(context)!;
    final value = await _showPotluckItemDialog(
      title: l10n.commonEdit,
      initialValue: _potluckItems[index].label,
      confirmLabel: l10n.commonSave,
    );
    if (!mounted) return;
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return;
    final previousItems = _potluckItems;
    setState(() {
      final next = _potluckItems.toList(growable: true);
      next[index] = next[index].copyWith(label: trimmed);
      _potluckItems = next;
    });
    await _savePotluckItems(previousItems: previousItems);
  }

  Future<void> _deletePotluckItem(int index) async {
    final previousItems = _potluckItems;
    setState(() {
      final next = _potluckItems.toList(growable: true);
      next.removeAt(index);
      _potluckItems = next;
    });
    await _savePotluckItems(previousItems: previousItems);
  }

  Future<void> _savePotluckItems({
    required List<MealPotluckItem> previousItems,
  }) async {
    if (widget.isCreate || _isSavingPotluckItems || _isSaving) return;
    setState(() => _isSavingPotluckItems = true);
    try {
      await ref.read(mealsRepositoryProvider).updateMealPotluckItems(
            tripId: widget.tripId,
            mealId: widget.mealId!,
            potluckItems: _potluckItems,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _potluckItems = previousItems;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(
              e.toString(),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingPotluckItems = false);
      }
    }
  }

  String _mealModeDisplayLabel(AppLocalizations l10n) {
    return switch (_activeMealView) {
      _MealDetailsView.cooked => l10n.mealModeCookedLabel,
      _MealDetailsView.restaurant => l10n.mealModeRestaurantLabel,
      _MealDetailsView.potluck => l10n.mealModePotluckLabel,
    };
  }

  Widget _buildMealModeSelector({
    required AppLocalizations l10n,
    required TextTheme textTheme,
    required ColorScheme colorScheme,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SegmentedButton<_MealDetailsView>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment<_MealDetailsView>(
                      value: _MealDetailsView.cooked,
                      icon: SvgPicture.asset(
                        'assets/images/chef_hat.svg',
                        width: 18,
                        height: 18,
                      ),
                      tooltip: l10n.mealModeCooked,
                    ),
                    ButtonSegment<_MealDetailsView>(
                      value: _MealDetailsView.restaurant,
                      icon: SvgPicture.asset(
                        'assets/images/hand_meal.svg',
                        width: 18,
                        height: 18,
                      ),
                      tooltip: l10n.mealModeRestaurant,
                    ),
                    ButtonSegment<_MealDetailsView>(
                      value: _MealDetailsView.potluck,
                      icon: SvgPicture.asset(
                        'assets/images/tapas.svg',
                        width: 18,
                        height: 18,
                      ),
                      tooltip: l10n.mealModePotluck,
                    ),
                  ],
                  selected: {_activeMealView},
                  onSelectionChanged: _isSavingMealMode
                      ? null
                      : (selection) async {
                          if (selection.isEmpty) {
                            return;
                          }
                          if (_activeMealView == selection.first) {
                            return;
                          }
                          final previousMealView = _activeMealView;
                          setState(() {
                            _activeMealView = selection.first;
                          });
                          await _saveMealMode(
                            previousMealView: previousMealView,
                          );
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _mealModeDisplayLabel(l10n),
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRestaurantUrl() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isSavingRestaurantUrl) return;
    final trimmed = _restaurantUrlController.text.trim();
    if (trimmed.isNotEmpty) {
      final parsed = Uri.tryParse(trimmed);
      if (parsed == null || !parsed.isAbsolute) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.linkInvalid)),
        );
        return;
      }
    }
    final previousUrl = _restaurantUrl;
    final previousEditing = _isRestaurantLinkEditing;
    setState(() {
      _restaurantUrl = trimmed;
      _restaurantUrlController.text = trimmed;
      _isRestaurantLinkEditing = false;
      _isSavingRestaurantUrl = true;
    });
    if (widget.isCreate || _isSaving) {
      if (!mounted) return;
      setState(() => _isSavingRestaurantUrl = false);
      return;
    }
    try {
      await ref.read(mealsRepositoryProvider).updateMealRestaurantUrl(
            tripId: widget.tripId,
            mealId: widget.mealId!,
            restaurantUrl: _restaurantUrl,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _restaurantUrl = previousUrl;
        _restaurantUrlController.text = previousUrl;
        _isRestaurantLinkEditing = previousEditing;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.commonErrorWithDetails(e.toString()),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingRestaurantUrl = false);
      }
    }
  }

  void _startEditRestaurantUrl() {
    setState(() {
      _restaurantUrlController.text = _restaurantUrl;
      _isRestaurantLinkEditing = true;
    });
  }

  Future<void> _clearRestaurantUrl() async {
    _restaurantUrlController.text = '';
    await _saveRestaurantUrl();
  }

  void _cancelEditRestaurantUrl() {
    setState(() {
      _restaurantUrlController.text = _restaurantUrl;
      _isRestaurantLinkEditing = false;
    });
  }

  Widget _buildRestaurantUrlEditActions(AppLocalizations l10n) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: _isSavingRestaurantUrl ? null : _saveRestaurantUrl,
          tooltip: l10n.commonConfirm,
          icon: _isSavingRestaurantUrl
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: _isSavingRestaurantUrl ? null : _cancelEditRestaurantUrl,
          tooltip: l10n.commonCancel,
          icon: const Icon(Icons.undo_rounded),
        ),
      ],
    );
  }

  void _hydrateFromMeal(TripMeal meal) {
    if (widget.isCreate && _isHydrated) return;
    _mealDate = meal.mealDateAsDateTime;
    _mealDayPart = meal.mealDayPart;
    _participantIds = meal.participantIds.toSet();
    _chefParticipantId = meal.chefParticipantId != null &&
            _participantIds.contains(meal.chefParticipantId)
        ? meal.chefParticipantId
        : null;
    _components = meal.components.toList(growable: true)
      ..sort((a, b) => a.order.compareTo(b.order));
    _componentsUserOrdered = meal.componentsUserOrdered;
    _activeMealView = _mealViewFromDataMode(meal.mealMode);
    _restaurantUrl = meal.restaurantUrl.trim();
    _restaurantUrlController.text = _restaurantUrl;
    _potluckItems = meal.potluckItems.toList(growable: false);
    if (widget.isCreate) {
      _isHydrated = true;
    }
  }

  MealMode _dataModeFromMealView(_MealDetailsView view) {
    return switch (view) {
      _MealDetailsView.cooked => MealMode.cooked,
      _MealDetailsView.restaurant => MealMode.restaurant,
      _MealDetailsView.potluck => MealMode.potluck,
    };
  }

  _MealDetailsView _mealViewFromDataMode(MealMode mode) {
    return switch (mode) {
      MealMode.cooked => _MealDetailsView.cooked,
      MealMode.restaurant => _MealDetailsView.restaurant,
      MealMode.potluck => _MealDetailsView.potluck,
    };
  }

  bool get _shouldAutoOrderComponents =>
      _activeMealView == _MealDetailsView.cooked && !_componentsUserOrdered;

  int _componentKindSortIndex(MealComponentKind kind) {
    return switch (kind) {
      MealComponentKind.entree => 0,
      MealComponentKind.plat => 1,
      MealComponentKind.dessert => 2,
    };
  }

  List<MealComponent> _normalizeComponentOrder(
    List<MealComponent> components, {
    required bool shouldAutoOrder,
  }) {
    final normalizedComponents = components.toList(growable: true);
    if (shouldAutoOrder) {
      normalizedComponents.sort((leftComponent, rightComponent) {
        final kindCompare = _componentKindSortIndex(leftComponent.kind).compareTo(
          _componentKindSortIndex(rightComponent.kind),
        );
        if (kindCompare != 0) {
          return kindCompare;
        }
        return leftComponent.order.compareTo(rightComponent.order);
      });
    }
    return [
      for (var index = 0; index < normalizedComponents.length; index++)
        normalizedComponents[index].copyWith(order: index),
    ];
  }

  Future<void> _addComponent(MealComponentKind kind) async {
    if (widget.isCreate) return;
    final previousComponents = _components;
    final previousComponentsUserOrdered = _componentsUserOrdered;
    setState(() {
      final nextComponents = [
        ..._components,
        MealComponent(
          id: 'cmp_${DateTime.now().microsecondsSinceEpoch}_${_components.length}',
          kind: kind,
          order: _components.length,
          ingredients: const [],
        ),
      ];
      _components = _normalizeComponentOrder(
        nextComponents,
        shouldAutoOrder: _shouldAutoOrderComponents,
      );
    });
    await _saveMealComponents(
      previousComponents: previousComponents,
      previousComponentsUserOrdered: previousComponentsUserOrdered,
    );
  }

  Future<void> _openComponentEditor({
    required MealComponent component,
    required List<IngredientCatalogItem> catalogItems,
    required Set<String> participantAllergenIds,
    required Map<String, String> tripMemberPublicLabels,
  }) async {
    Future<void> openEditor() async {
      final updated = await Navigator.of(context).push<MealComponent>(
        MaterialPageRoute(
          builder: (_) => MealComponentEditorPage(
            component: component,
            catalogItems: catalogItems,
            participantAllergenIds: participantAllergenIds,
            showLockIndicator: true,
          ),
        ),
      );
      if (!mounted || updated == null) return;
      final previousComponents = _components;
      final previousComponentsUserOrdered = _componentsUserOrdered;
      final updatedComponent = updated.copyWith(
        order: component.order,
        lockedBy: _currentUserId,
      );
      final kindChanged = updatedComponent.kind != component.kind;
      final nextComponents = _components
          .map((existingComponent) =>
              existingComponent.id == updatedComponent.id
                  ? updatedComponent
                  : existingComponent)
          .toList(growable: false);
      setState(() {
        _components = _normalizeComponentOrder(
          nextComponents,
          shouldAutoOrder: kindChanged && _shouldAutoOrderComponents,
        );
      });
      await _saveMealComponents(
        previousComponents: previousComponents,
        previousComponentsUserOrdered: previousComponentsUserOrdered,
      );
    }

    final mealId = (widget.mealId ?? '').trim();
    if (mealId.isEmpty) return;

    if (_isComponentLockedByOther(component)) {
      final lockOwnerId = (component.lockedBy ?? '').trim();
      var lockOwnerData = <String, dynamic>{};
      if (lockOwnerId.isNotEmpty) {
        try {
          final users =
              await ref.read(usersDataByIdsProvider(lockOwnerId).future);
          lockOwnerData = users[lockOwnerId] ?? const <String, dynamic>{};
        } catch (_) {
          lockOwnerData = const <String, dynamic>{};
        }
      }
      if (!mounted) return;
      final label = resolveTripMemberDisplayLabel(
        memberId: lockOwnerId,
        userData: lockOwnerData,
        tripMemberPublicLabels: tripMemberPublicLabels,
        currentUserId: _currentUserId,
        emptyFallback: AppLocalizations.of(context)!.roleParticipant,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.mealComponentLockedByUser(label),
          ),
        ),
      );
      return;
    }

    final repo = ref.read(mealsRepositoryProvider);
    final lockOwner = await repo.lockMealComponent(
      tripId: widget.tripId,
      mealId: mealId,
      componentId: component.id,
    );
    if (!mounted) return;
    if (lockOwner != null && lockOwner.trim().isNotEmpty) {
      var lockOwnerData = <String, dynamic>{};
      try {
        final users = await ref.read(usersDataByIdsProvider(lockOwner).future);
        lockOwnerData = users[lockOwner] ?? const <String, dynamic>{};
      } catch (_) {
        lockOwnerData = const <String, dynamic>{};
      }
      if (!mounted) return;
      final label = resolveTripMemberDisplayLabel(
        memberId: lockOwner,
        userData: lockOwnerData,
        tripMemberPublicLabels: tripMemberPublicLabels,
        currentUserId: _currentUserId,
        emptyFallback: AppLocalizations.of(context)!.roleParticipant,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.mealComponentLockedByUser(label),
          ),
        ),
      );
      return;
    }

    try {
      await openEditor();
    } finally {
      await repo.unlockMealComponent(
        tripId: widget.tripId,
        mealId: mealId,
        componentId: component.id,
      );
    }
  }

  Future<void> _deleteComponent(String componentId) async {
    final previousComponents = _components;
    final previousComponentsUserOrdered = _componentsUserOrdered;
    MealComponent? component;
    for (final it in previousComponents) {
      if (it.id == componentId) {
        component = it;
        break;
      }
    }
    if (component != null && _isComponentLockedByOther(component)) {
      var lockOwnerData = <String, dynamic>{};
      final lockOwnerId = (component.lockedBy ?? '').trim();
      if (lockOwnerId.isNotEmpty) {
        try {
          final users =
              await ref.read(usersDataByIdsProvider(lockOwnerId).future);
          lockOwnerData = users[lockOwnerId] ?? const <String, dynamic>{};
        } catch (_) {
          lockOwnerData = const <String, dynamic>{};
        }
      }
      if (!mounted) return;
      final label = resolveTripMemberDisplayLabel(
        memberId: lockOwnerId,
        userData: lockOwnerData,
        tripMemberPublicLabels: const {},
        currentUserId: _currentUserId,
        emptyFallback: AppLocalizations.of(context)!.roleParticipant,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.mealComponentLockedByUser(label),
          ),
        ),
      );
      return;
    }
    setState(() {
      final filtered = _components
          .where((component) => component.id != componentId)
          .toList(growable: false);
      _components = [
        for (var i = 0; i < filtered.length; i++)
          filtered[i].copyWith(order: i),
      ];
    });
    await _saveMealComponents(
      previousComponents: previousComponents,
      previousComponentsUserOrdered: previousComponentsUserOrdered,
    );
  }

  Future<void> _reorderComponents(int oldIndex, int newIndex) async {
    final previousComponents = _components;
    final previousComponentsUserOrdered = _componentsUserOrdered;
    final movingComponent = previousComponents[oldIndex];
    if (_isComponentLockedByOther(movingComponent)) {
      final lockOwnerId = (movingComponent.lockedBy ?? '').trim();
      var lockOwnerData = <String, dynamic>{};
      if (lockOwnerId.isNotEmpty) {
        try {
          final users =
              await ref.read(usersDataByIdsProvider(lockOwnerId).future);
          lockOwnerData = users[lockOwnerId] ?? const <String, dynamic>{};
        } catch (_) {
          lockOwnerData = const <String, dynamic>{};
        }
      }
      if (!mounted) return;
      final label = resolveTripMemberDisplayLabel(
        memberId: lockOwnerId,
        userData: lockOwnerData,
        tripMemberPublicLabels: const {},
        currentUserId: _currentUserId,
        emptyFallback: AppLocalizations.of(context)!.roleParticipant,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.mealComponentLockedByUser(label),
          ),
        ),
      );
      return;
    }
    setState(() {
      final next = _components.toList(growable: true);
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final moved = next.removeAt(oldIndex);
      next.insert(newIndex, moved);
      _components = [
        for (var i = 0; i < next.length; i++) next[i].copyWith(order: i),
      ];
      _componentsUserOrdered = true;
    });
    await _saveMealComponents(
      previousComponents: previousComponents,
      previousComponentsUserOrdered: previousComponentsUserOrdered,
    );
  }

  Future<void> _saveMealComponents({
    required List<MealComponent> previousComponents,
    required bool previousComponentsUserOrdered,
  }) async {
    if (widget.isCreate || _isSavingComponents || _isSaving) return;
    setState(() => _isSavingComponents = true);
    try {
      await ref.read(mealsRepositoryProvider).updateMealComponents(
            tripId: widget.tripId,
            mealId: widget.mealId!,
            components: _components,
            componentsUserOrdered: _componentsUserOrdered,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _components = previousComponents;
        _componentsUserOrdered = previousComponentsUserOrdered;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(
              e.toString(),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingComponents = false);
      }
    }
  }

  Future<void> _autoRecalculateParticipants(List<String> memberIds) async {
    if (_isSavingParticipants) return;
    final previousParticipantIds = _participantIds.toSet();
    final previousChefParticipantId = _chefParticipantId;
    try {
      final ids =
          await ref.read(mealsRepositoryProvider).calculateMealParticipants(
                tripId: widget.tripId,
                mealDateKey: _mealDateKey,
                mealDayPart: tripDayPartToFirestore(_mealDayPart),
                allMemberIds: memberIds,
              );
      if (!mounted) return;
      setState(() {
        _participantIds = ids.toSet();
        if (_chefParticipantId != null &&
            !_participantIds.contains(_chefParticipantId)) {
          _chefParticipantId = null;
        }
      });
      await _saveMealParticipants(
        previousParticipantIds: previousParticipantIds,
        previousChefParticipantId: previousChefParticipantId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(
              e.toString(),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _toggleAllParticipants(List<String> memberIds) async {
    if (_isSavingParticipants) return;
    final previousParticipantIds = _participantIds.toSet();
    final previousChefParticipantId = _chefParticipantId;
    final allSelected =
        memberIds.isNotEmpty && memberIds.every(_participantIds.contains);
    setState(() {
      _participantIds = allSelected ? <String>{} : memberIds.toSet();
      if (_chefParticipantId != null &&
          !_participantIds.contains(_chefParticipantId)) {
        _chefParticipantId = null;
      }
    });
    await _saveMealParticipants(
      previousParticipantIds: previousParticipantIds,
      previousChefParticipantId: previousChefParticipantId,
    );
  }

  Future<void> _saveMealParticipants({
    required Set<String> previousParticipantIds,
    required String? previousChefParticipantId,
  }) async {
    if (widget.isCreate || _isSavingParticipants || _isSaving) return;
    setState(() => _isSavingParticipants = true);
    try {
      await ref.read(mealsRepositoryProvider).updateMealParticipants(
            tripId: widget.tripId,
            mealId: widget.mealId!,
            participantIds: _participantIds.toList(growable: false),
            chefParticipantId: _chefParticipantId,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _participantIds = previousParticipantIds;
        _chefParticipantId = previousChefParticipantId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(
              e.toString(),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingParticipants = false);
      }
    }
  }

  Future<void> _toggleChefParticipant(String participantId) async {
    if (_isSavingParticipants) return;
    if (_activeMealView != _MealDetailsView.cooked) return;
    if (!_participantIds.contains(participantId)) return;
    final previousParticipantIds = _participantIds.toSet();
    final previousChefParticipantId = _chefParticipantId;
    setState(() {
      if (_chefParticipantId == participantId) {
        _chefParticipantId = null;
      } else {
        _chefParticipantId = participantId;
      }
    });
    await _saveMealParticipants(
      previousParticipantIds: previousParticipantIds,
      previousChefParticipantId: previousChefParticipantId,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      locale: Localizations.localeOf(context),
      initialDate: _mealDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: AppLocalizations.of(context)!.mealDateHelp,
    );
    if (picked == null || !mounted) return;
    final previousDate = _mealDate;
    setState(() {
      _mealDate = DateUtils.dateOnly(picked);
    });
    await _saveMealDate(previousDate: previousDate);
  }

  Future<void> _saveMealDayPart({
    required TripDayPart previousDayPart,
  }) async {
    if (widget.isCreate || _isSavingMealDayPart || _isSaving) return;
    setState(() => _isSavingMealDayPart = true);
    try {
      await ref.read(mealsRepositoryProvider).updateMealDayPart(
            tripId: widget.tripId,
            mealId: widget.mealId!,
            mealDayPart: tripDayPartToFirestore(_mealDayPart),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.mealUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mealDayPart = previousDayPart;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(
              e.toString(),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingMealDayPart = false);
      }
    }
  }

  Future<void> _saveMealDate({required DateTime previousDate}) async {
    if (widget.isCreate || _isSavingDate || _isSaving) return;
    setState(() => _isSavingDate = true);
    try {
      await ref.read(mealsRepositoryProvider).updateMealDate(
            tripId: widget.tripId,
            mealId: widget.mealId!,
            mealDateKey: _mealDateKey,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.mealUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mealDate = DateUtils.dateOnly(previousDate);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(
              e.toString(),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingDate = false);
      }
    }
  }

  Future<void> _saveMealMode({
    required _MealDetailsView previousMealView,
  }) async {
    if (widget.isCreate || _isSavingMealMode || _isSaving) return;
    setState(() => _isSavingMealMode = true);
    try {
      await ref.read(mealsRepositoryProvider).updateMealMode(
            tripId: widget.tripId,
            mealId: widget.mealId!,
            mealMode: _dataModeFromMealView(_activeMealView),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.mealUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activeMealView = previousMealView;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(
              e.toString(),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingMealMode = false);
      }
    }
  }

  Future<void> _save() async {
    if (!widget.isCreate) return;
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(mealsRepositoryProvider);
      final mealDayPart = tripDayPartToFirestore(_mealDayPart);
      final participantIds = _participantIds.toList()..sort();
      final mealMode = _dataModeFromMealView(_activeMealView);
      final restaurantUrl =
          mealMode == MealMode.restaurant ? _restaurantUrl.trim() : '';
      final potluckItems = mealMode == MealMode.potluck
          ? _potluckItems
          : const <MealPotluckItem>[];
      await repo.addMeal(
        tripId: widget.tripId,
        mealDateKey: _mealDateKey,
        mealDayPart: mealDayPart,
        participantIds: participantIds,
        chefParticipantId: _chefParticipantId,
        notes: '',
        components: _components,
        mealMode: mealMode,
        restaurantUrl: restaurantUrl,
        potluckItems: potluckItems,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.mealCreated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(
              e.toString(),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmAndDelete() async {
    if (widget.isCreate || _isDeleting) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.mealDeleteTitle),
        content: Text(AppLocalizations.of(context)!.mealDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(context)!.commonDelete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await ref.read(mealsRepositoryProvider).deleteMeal(
            tripId: widget.tripId,
            mealId: widget.mealId!,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.mealDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(
              e.toString(),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));
    final catalogAsync = ref.watch(ingredientCatalogProvider);
    final mealAsync = widget.isCreate
        ? const AsyncValue<TripMeal?>.data(null)
        : ref.watch(
            tripMealStreamProvider(
              (tripId: widget.tripId, mealId: widget.mealId!),
            ),
          );

    return tripAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.commonErrorWithDetails(e.toString()))),
      ),
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(l10n.tripNotFound)),
          );
        }
        final memberIds = trip.memberIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toList();
        final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
        final labels = <String, String>{
          for (final id in memberIds)
            id: (id == myUid)
                ? l10n.commonMe
                : ((trip.memberPublicLabels[id]?.trim().isNotEmpty ?? false)
                    ? trip.memberPublicLabels[id]!.trim()
                    : l10n.roleParticipant)
        };

        return mealAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body:
                Center(child: Text(l10n.commonErrorWithDetails(e.toString()))),
          ),
          data: (meal) {
            if (!widget.isCreate && meal == null) {
              return Scaffold(
                appBar: AppBar(),
                body: Center(child: Text(l10n.mealNotFound)),
              );
            }
            if (meal != null) {
              _hydrateFromMeal(meal);
            } else if (!_isHydrated) {
              _isHydrated = true;
              final tripStart = trip.startDate;
              if (tripStart != null) {
                _mealDate = DateUtils.dateOnly(tripStart);
              }
            }
            final areAllParticipantsSelected = memberIds.isNotEmpty &&
                memberIds.every(_participantIds.contains);
            final participantIdsForRisk = _participantIds.toList()..sort();
            final participantIdsRiskKey = participantIdsForRisk.join('|');
            final componentLockOwnerIds = _components
                .map((component) => (component.lockedBy ?? '').trim())
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList(growable: false)
              ..sort();
            final componentLockOwnerRiskKey = componentLockOwnerIds.join('|');
            final potluckAddedByIds = _potluckItems
                .map((item) => item.addedBy.trim())
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList(growable: false)
              ..sort();
            final potluckAddedByRiskKey = potluckAddedByIds.join('|');
            final usersAsync = ref.watch(
              usersDataByIdsProvider(participantIdsRiskKey),
            );
            final potluckUsersAsync = ref.watch(
              usersDataByIdsProvider(potluckAddedByRiskKey),
            );
            final lockOwnersAsync = ref.watch(
              usersDataByIdsProvider(componentLockOwnerRiskKey),
            );
            final colorScheme = Theme.of(context).colorScheme;
            final textTheme = Theme.of(context).textTheme;

            return Scaffold(
              appBar: AppBar(
                title: Text(
                  widget.isCreate ? l10n.mealNew : l10n.mealEdit,
                ),
                actions: [
                  if (!widget.isCreate)
                    IconButton(
                      tooltip: l10n.commonDelete,
                      onPressed: _isDeleting ? null : _confirmAndDelete,
                      icon: _isDeleting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline),
                    ),
                ],
              ),
              body: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  children: [
                    Card.outlined(
                      color: colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    for (final part in TripDayPart.values)
                                      ChoiceChip(
                                        showCheckmark: false,
                                        label: SvgPicture.asset(
                                          _dayPartIconAsset(part),
                                          width: 16,
                                          height: 16,
                                        ),
                                        tooltip: _dayPartLabel(context, part),
                                        selected: _mealDayPart == part,
                                        onSelected: _isSavingMealDayPart
                                            ? null
                                            : (_) async {
                                                if (_mealDayPart == part) {
                                                  return;
                                                }
                                                final previousDayPart =
                                                    _mealDayPart;
                                                setState(() {
                                                  _mealDayPart = part;
                                                });
                                                await _saveMealDayPart(
                                                  previousDayPart:
                                                      previousDayPart,
                                                );
                                              },
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _dayPartLabel(context, _mealDayPart),
                                    style: textTheme.bodyLarge?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: l10n.commonDate,
                                  onPressed: _isSavingDate ? null : _pickDate,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: _isSavingDate
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.calendar_today_outlined),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    DateFormat.yMMMMEEEEd(
                                      Localizations.localeOf(context)
                                          .toString(),
                                    ).format(_mealDate),
                                    style: textTheme.bodyLarge,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card.outlined(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.mealParticipantsCount(
                                        _participantIds.length),
                                    style: textTheme.labelLarge,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _isSavingParticipants
                                      ? null
                                      : () => _autoRecalculateParticipants(
                                          memberIds),
                                  icon:
                                      const Icon(Icons.auto_fix_high_outlined),
                                  label: Text(l10n.commonAuto),
                                ),
                                TextButton.icon(
                                  onPressed: _isSavingParticipants
                                      ? null
                                      : () => _toggleAllParticipants(memberIds),
                                  icon: const Icon(Icons.done_all_outlined),
                                  label: Text(
                                    areAllParticipantsSelected
                                        ? l10n.commonNone
                                        : l10n.commonAll,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_activeMealView == _MealDetailsView.cooked) ...[
                              Text(
                                l10n.mealChefLongPressHint,
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final memberId in memberIds)
                                  GestureDetector(
                                    onLongPress: _activeMealView ==
                                            _MealDetailsView.cooked
                                        ? () => _toggleChefParticipant(memberId)
                                        : null,
                                    child: Builder(
                                      builder: (context) {
                                        final isSelected =
                                            _participantIds.contains(memberId);
                                        final isChef = _activeMealView ==
                                                _MealDetailsView.cooked &&
                                            _chefParticipantId == memberId;
                                        return FilterChip(
                                          showCheckmark: false,
                                          label: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isChef) ...[
                                                SvgPicture.asset(
                                                  'assets/images/chef_hat.svg',
                                                  width: 16,
                                                  height: 16,
                                                ),
                                                const SizedBox(width: 6),
                                              ],
                                              Text(
                                                labels[memberId] ??
                                                    l10n.roleParticipant,
                                              ),
                                            ],
                                          ),
                                          labelStyle: isChef
                                              ? const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                )
                                              : null,
                                          selected: isSelected,
                                          selectedColor: isChef
                                              ? colorScheme.primaryContainer
                                              : null,
                                          side: isChef
                                              ? BorderSide(
                                                  color: colorScheme.primary,
                                                )
                                              : null,
                                          onSelected: (selected) {
                                            if (_isSavingParticipants) return;
                                            final previousParticipantIds =
                                                _participantIds.toSet();
                                            final previousChefParticipantId =
                                                _chefParticipantId;
                                            setState(() {
                                              if (selected) {
                                                _participantIds.add(memberId);
                                              } else {
                                                _participantIds
                                                    .remove(memberId);
                                                if (_chefParticipantId ==
                                                    memberId) {
                                                  _chefParticipantId = null;
                                                }
                                              }
                                            });
                                            _saveMealParticipants(
                                              previousParticipantIds:
                                                  previousParticipantIds,
                                              previousChefParticipantId:
                                                  previousChefParticipantId,
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_activeMealView == _MealDetailsView.cooked) ...[
                      Card.outlined(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildMealModeSelector(
                                l10n: l10n,
                                textTheme: textTheme,
                                colorScheme: colorScheme,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l10n.mealComponentsTitle,
                                      style: textTheme.titleMedium,
                                    ),
                                  ),
                                  if (!widget.isCreate)
                                    PopupMenuButton<MealComponentKind>(
                                      tooltip: l10n.mealAddComponent,
                                      onSelected: _isSavingComponents
                                          ? null
                                          : (kind) => _addComponent(kind),
                                      icon: const Icon(Icons.add),
                                      itemBuilder: (context) => [
                                        for (final kind
                                            in MealComponentKind.values)
                                          PopupMenuItem(
                                            value: kind,
                                            child: Text(
                                              l10n.mealAddComponentWithKind(
                                                _componentKindLabel(l10n, kind),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_components.isEmpty)
                                Text(
                                  l10n.mealAddComponentHint,
                                  style: textTheme.bodyMedium,
                                )
                              else
                                ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  itemCount: _components.length,
                                  onReorder: _isSavingComponents
                                      ? (_, __) {}
                                      : _reorderComponents,
                                  itemBuilder: (context, index) {
                                    final component = _components[index];
                                    final isLocked = (component.lockedBy ?? '')
                                        .trim()
                                        .isNotEmpty;
                                    final usersData = usersAsync.asData?.value;
                                    final catalogItems =
                                        catalogAsync.asData?.value;
                                    final participantAllergenIds = usersData ==
                                            null
                                        ? <String>{}
                                        : participantAllergenIdsFromUsersData(
                                            usersData,
                                            _participantIds,
                                          );
                                    final risk = catalogItems == null
                                        ? null
                                        : buildMealComponentRisks(
                                            components: [component],
                                            catalogItems: catalogItems,
                                            participantAllergenIds:
                                                participantAllergenIds,
                                          )[component.id];
                                    final allergenLabelById = <String, String>{
                                      if (catalogItems != null)
                                        for (final item in catalogItems.where(
                                            (it) => it.type == 'allergen'))
                                          item.id: item.label,
                                    };

                                    return Card(
                                      key: ValueKey(component.id),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      child: ListTile(
                                        onTap: catalogItems == null
                                            || widget.isCreate
                                            ? null
                                            : () => _openComponentEditor(
                                                  component: component,
                                                  catalogItems: catalogItems,
                                                  participantAllergenIds:
                                                      participantAllergenIds,
                                                  tripMemberPublicLabels:
                                                      trip.memberPublicLabels,
                                                ),
                                        leading: _isComponentLockedByOther(
                                                component)
                                            ? const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                ),
                                                child: Icon(Icons.lock_outline),
                                              )
                                            : ReorderableDragStartListener(
                                                index: index,
                                                child: const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                                  child: Icon(
                                                      Icons.drag_indicator),
                                                ),
                                              ),
                                        title: Text(
                                          component.title.trim().isEmpty
                                              ? _componentKindLabel(
                                                  l10n,
                                                  component.kind,
                                                )
                                              : '${component.title.trim()} (${_componentKindLabel(
                                                  l10n,
                                                  component.kind,
                                                )})',
                                        ),
                                        subtitle: Text(
                                          l10n.mealIngredientsCount(
                                            component.ingredients.length,
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if ((component.lockedBy ?? '')
                                                .trim()
                                                .isNotEmpty)
                                              Builder(
                                                builder: (context) {
                                                  final lockOwnerId =
                                                      (component.lockedBy ?? '')
                                                          .trim();
                                                  final lockOwnersData =
                                                      lockOwnersAsync
                                                          .asData?.value;
                                                  final lockOwnerData =
                                                      lockOwnersData?[
                                                          lockOwnerId];
                                                  final lockOwnerLabel =
                                                      resolveTripMemberDisplayLabel(
                                                    memberId: lockOwnerId,
                                                    userData: lockOwnerData,
                                                    tripMemberPublicLabels:
                                                        trip.memberPublicLabels,
                                                    currentUserId:
                                                        _currentUserId,
                                                    emptyFallback:
                                                        l10n.roleParticipant,
                                                  );
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      right: 4,
                                                    ),
                                                    child: SizedBox(
                                                      width: 24,
                                                      height: 24,
                                                      child: buildProfileBadge(
                                                        context: context,
                                                        displayLabel:
                                                            lockOwnerLabel,
                                                        userData: lockOwnerData,
                                                        size: 22,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            if (!isLocked &&
                                                risk != null &&
                                                (risk.containsAllergenIds
                                                        .isNotEmpty ||
                                                    risk.mayContainAllergenIds
                                                        .isNotEmpty))
                                              Tooltip(
                                                message: [
                                                  ...risk.containsAllergenIds
                                                      .map(
                                                    (id) => l10n
                                                        .mealContainsAllergen(
                                                      allergenLabelById[id] ??
                                                          id,
                                                    ),
                                                  ),
                                                  ...risk.mayContainAllergenIds
                                                      .map(
                                                    (id) => l10n
                                                        .mealMayContainAllergen(
                                                      allergenLabelById[id] ??
                                                          id,
                                                    ),
                                                  ),
                                                ].join('\n'),
                                                child: const Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: Colors.orange,
                                                ),
                                              ),
                                            if (!isLocked) ...[
                                              IconButton(
                                                tooltip:
                                                    l10n.mealDeleteComponent,
                                                onPressed: _isSavingComponents
                                                    ? null
                                                    : _isComponentLockedByOther(
                                                        component,
                                                      )
                                                        ? null
                                                        : () =>
                                                            _deleteComponent(
                                                              component.id,
                                                            ),
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                              ),
                                              const Icon(Icons.chevron_right),
                                            ],
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ] else if (_activeMealView ==
                        _MealDetailsView.restaurant) ...[
                      Card.outlined(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: _isRestaurantLinkEditing
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildMealModeSelector(
                                      l10n: l10n,
                                      textTheme: textTheme,
                                      colorScheme: colorScheme,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller:
                                                _restaurantUrlController,
                                            textInputAction:
                                                TextInputAction.done,
                                            enabled: !_isSavingRestaurantUrl,
                                            onFieldSubmitted: (_) =>
                                                _saveRestaurantUrl(),
                                            decoration: InputDecoration(
                                              labelText: l10n
                                                  .mealRestaurantLinkLabel,
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        _buildRestaurantUrlEditActions(l10n),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      l10n.mealRestaurantLinkHint,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildMealModeSelector(
                                      l10n: l10n,
                                      textTheme: textTheme,
                                      colorScheme: colorScheme,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: _restaurantUrl.isEmpty
                                              ? Text(
                                                  l10n.mealRestaurantLinkHint,
                                                  style: textTheme.bodyMedium
                                                      ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                )
                                              : LinkPreviewCardFromFirestore(
                                                  url: _restaurantUrl,
                                                  preview: meal?.restaurantLinkPreview ?? const {},
                                                ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: l10n.commonEdit,
                                              onPressed:
                                                  _startEditRestaurantUrl,
                                              icon: const Icon(
                                                  Icons.edit_outlined),
                                            ),
                                            if (_restaurantUrl.isNotEmpty)
                                              IconButton(
                                                tooltip: l10n.commonDelete,
                                                onPressed:
                                                    _isSavingRestaurantUrl
                                                        ? null
                                                        : _clearRestaurantUrl,
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ] else ...[
                      Card.outlined(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildMealModeSelector(
                                l10n: l10n,
                                textTheme: textTheme,
                                colorScheme: colorScheme,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l10n.mealPotluckTitle,
                                      style: textTheme.titleMedium,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: l10n.commonAdd,
                                    onPressed: _isSavingPotluckItems
                                        ? null
                                        : _addPotluckItem,
                                    icon: const Icon(Icons.add),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_potluckItems.isEmpty)
                                Text(
                                  l10n.mealPotluckEmptyHint,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _potluckItems.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Builder(
                                        builder: (context) {
                                          final item = _potluckItems[index];
                                          final addedBy = item.addedBy.trim();
                                          final usersData =
                                              potluckUsersAsync.asData?.value;
                                          final userData = addedBy.isEmpty
                                              ? null
                                              : usersData?[addedBy];
                                          final label =
                                              resolveTripMemberDisplayLabel(
                                            memberId: addedBy,
                                            userData: userData,
                                            tripMemberPublicLabels:
                                                trip.memberPublicLabels,
                                            currentUserId: FirebaseAuth
                                                .instance.currentUser?.uid,
                                            emptyFallback: l10n.roleParticipant,
                                          );
                                          return buildProfileBadge(
                                            context: context,
                                            displayLabel: label,
                                            userData: userData,
                                            size: 26,
                                          );
                                        },
                                      ),
                                      title: Text(_potluckItems[index].label),
                                      trailing: Wrap(
                                        spacing: 4,
                                        children: [
                                          IconButton(
                                            tooltip: l10n.commonEdit,
                                            onPressed: _isSavingPotluckItems
                                                ? null
                                                : () => _editPotluckItem(index),
                                            icon:
                                                const Icon(Icons.edit_outlined),
                                          ),
                                          IconButton(
                                            tooltip: l10n.commonDelete,
                                            onPressed: _isSavingPotluckItems
                                                ? null
                                                : () =>
                                                    _deletePotluckItem(index),
                                            icon: const Icon(
                                                Icons.delete_outline),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              bottomNavigationBar: widget.isCreate
                  ? SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _save,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _isSaving ? l10n.commonSaving : l10n.commonSave,
                          ),
                        ),
                      ),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

enum _MealDetailsView {
  cooked,
  restaurant,
  potluck,
}

String _dayPartLabel(BuildContext context, TripDayPart dayPart) {
  final l10n = AppLocalizations.of(context)!;
  return switch (dayPart) {
    TripDayPart.morning => l10n.dayPartMorning,
    TripDayPart.midday => l10n.dayPartMidday,
    TripDayPart.evening => l10n.dayPartEvening,
  };
}

String _dayPartIconAsset(TripDayPart dayPart) {
  return switch (dayPart) {
    TripDayPart.morning => 'assets/images/meal_breakfast.svg',
    TripDayPart.midday => 'assets/images/meal_lunch.svg',
    TripDayPart.evening => 'assets/images/meal_dinner.svg',
  };
}
