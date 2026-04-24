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
  late final TextEditingController _nameController;
  late final TextEditingController _restaurantUrlController;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isHydrated = false;
  DateTime _mealDate = DateUtils.dateOnly(DateTime.now());
  TripDayPart _mealDayPart = TripDayPart.midday;
  Set<String> _participantIds = <String>{};
  String? _chefParticipantId;
  List<MealComponent> _components = const [];
  String? _initialMealSignature;
  Map<String, String> _initialComponentSignatures = const {};
  bool _allowNextPop = false;
  _MealDetailsView _activeMealView = _MealDetailsView.cooked;
  List<MealPotluckItem> _potluckItems = const [];
  bool _isRestaurantLinkEditing = true;
  String _restaurantUrl = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _restaurantUrlController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _restaurantUrlController.dispose();
    super.dispose();
  }

  String get _mealDateKey => TripMemberStay.dateKeyFromDateTime(_mealDate);

  String _componentKindLabel(AppLocalizations l10n, MealComponentKind kind) {
    return switch (kind) {
      MealComponentKind.entree => l10n.mealComponentKindEntree,
      MealComponentKind.plat => l10n.mealComponentKindMain,
      MealComponentKind.dessert => l10n.mealComponentKindDessert,
      MealComponentKind.autre => l10n.mealComponentKindOther,
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
    setState(
      () => _potluckItems = [
        ..._potluckItems,
        MealPotluckItem(
          id: 'potluck_${DateTime.now().microsecondsSinceEpoch}_${_potluckItems.length}',
          label: trimmed,
          addedBy: uid,
        ),
      ],
    );
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
    setState(() {
      final next = _potluckItems.toList(growable: true);
      next[index] = next[index].copyWith(label: trimmed);
      _potluckItems = next;
    });
  }

  void _deletePotluckItem(int index) {
    setState(() {
      final next = _potluckItems.toList(growable: true);
      next.removeAt(index);
      _potluckItems = next;
    });
  }

  String _mealModeDisplayLabel(AppLocalizations l10n) {
    return switch (_activeMealView) {
      _MealDetailsView.cooked => l10n.mealModeCookedLabel,
      _MealDetailsView.restaurant => l10n.mealModeRestaurantLabel,
      _MealDetailsView.potluck => l10n.mealModePotluckLabel,
    };
  }

  void _saveRestaurantUrl() {
    final l10n = AppLocalizations.of(context)!;
    final trimmed = _restaurantUrlController.text.trim();
    if (trimmed.isEmpty) return;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.isAbsolute) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkInvalid)),
      );
      return;
    }
    setState(() {
      _restaurantUrl = trimmed;
      _restaurantUrlController.text = trimmed;
      _isRestaurantLinkEditing = false;
    });
  }

  void _startEditRestaurantUrl() {
    setState(() {
      _restaurantUrlController.text = _restaurantUrl;
      _isRestaurantLinkEditing = true;
    });
  }

  void _hydrateFromMeal(TripMeal meal) {
    if (_isHydrated) return;
    _nameController.text = meal.name;
    _mealDate = meal.mealDateAsDateTime;
    _mealDayPart = meal.mealDayPart;
    _participantIds = meal.participantIds.toSet();
    _chefParticipantId = meal.chefParticipantId != null &&
            _participantIds.contains(meal.chefParticipantId)
        ? meal.chefParticipantId
        : null;
    _components = meal.components.toList(growable: true)
      ..sort((a, b) => a.order.compareTo(b.order));
    _activeMealView = _mealViewFromDataMode(meal.mealMode);
    _restaurantUrl = meal.restaurantUrl.trim();
    _restaurantUrlController.text = _restaurantUrl;
    _isRestaurantLinkEditing = _restaurantUrl.isEmpty;
    _potluckItems = meal.potluckItems.toList(growable: false);
    _saveCurrentAsBaseline();
    _isHydrated = true;
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

  String _componentSignature(MealComponent component) {
    final ingredients = component.ingredients
        .map(
          (ingredient) =>
              '${ingredient.catalogItemId.trim()}|${ingredient.label.trim()}|'
              '${ingredient.quantityValue}|${ingredient.quantityUnit.trim()}',
        )
        .join('~');
    return '${component.order}|${component.kind.firestoreValue}|'
        '${component.title.trim()}|$ingredients';
  }

  Map<String, String> _componentSignaturesById(List<MealComponent> components) {
    return {
      for (final component in components)
        component.id: _componentSignature(component),
    };
  }

  String _currentMealSignature() {
    final sortedParticipants = _participantIds.toList()..sort();
    final componentsSignature = _components
        .map((component) => '${component.id}:${_componentSignature(component)}')
        .join('||');
    return '${_nameController.text.trim()}|$_mealDateKey|'
        '${tripDayPartToFirestore(_mealDayPart)}|'
        '${sortedParticipants.join(",")}|${_chefParticipantId ?? ""}|'
        '$componentsSignature|${_activeMealView.name}|'
        '${_restaurantUrl.trim()}|'
        '${_potluckItems.map((item) => "${item.id}:${item.label}:${item.addedBy}").join("~")}';
  }

  void _saveCurrentAsBaseline() {
    _initialMealSignature = _currentMealSignature();
    _initialComponentSignatures = _componentSignaturesById(_components);
  }

  bool get _hasUnsavedChanges {
    final baseline = _initialMealSignature;
    if (baseline == null) return false;
    return baseline != _currentMealSignature();
  }

  Set<String> get _changedComponentIds {
    final current = _componentSignaturesById(_components);
    final changed = <String>{};
    for (final entry in current.entries) {
      if (_initialComponentSignatures[entry.key] != entry.value) {
        changed.add(entry.key);
      }
    }
    for (final initialId in _initialComponentSignatures.keys) {
      if (!current.containsKey(initialId)) {
        changed.add(initialId);
      }
    }
    return changed;
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_hasUnsavedChanges) return true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.commonUnsavedChangesTitle),
        content: Text(
          AppLocalizations.of(context)!.mealUnsavedChangesBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(context)!.commonStay),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(context)!.tripOverviewLeaveAction),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  void _addComponent(MealComponentKind kind) {
    setState(() {
      _components = [
        ..._components,
        MealComponent(
          id: 'cmp_${DateTime.now().microsecondsSinceEpoch}_${_components.length}',
          kind: kind,
          order: _components.length,
          ingredients: const [],
        ),
      ];
    });
  }

  Future<void> _openComponentEditor({
    required MealComponent component,
    required List<IngredientCatalogItem> catalogItems,
    required Set<String> participantAllergenIds,
  }) async {
    final updated = await Navigator.of(context).push<MealComponent>(
      MaterialPageRoute(
        builder: (_) => MealComponentEditorPage(
          component: component,
          catalogItems: catalogItems,
          participantAllergenIds: participantAllergenIds,
        ),
      ),
    );
    if (!mounted || updated == null) return;
    _updateComponent(updated.copyWith(order: component.order));
  }

  void _updateComponent(MealComponent next) {
    setState(() {
      _components = _components
          .map((component) => component.id == next.id ? next : component)
          .toList(growable: false);
    });
  }

  void _deleteComponent(String componentId) {
    setState(() {
      final filtered = _components
          .where((component) => component.id != componentId)
          .toList(growable: false);
      _components = [
        for (var i = 0; i < filtered.length; i++)
          filtered[i].copyWith(order: i),
      ];
    });
  }

  void _reorderComponents(int oldIndex, int newIndex) {
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
    });
  }

  Future<void> _autoRecalculateParticipants(List<String> memberIds) async {
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(
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

  void _selectAllParticipants(List<String> memberIds) {
    setState(() {
      _participantIds = memberIds.toSet();
      if (_chefParticipantId != null &&
          !_participantIds.contains(_chefParticipantId)) {
        _chefParticipantId = null;
      }
    });
  }

  void _toggleChefParticipant(String participantId) {
    if (_activeMealView != _MealDetailsView.cooked) return;
    if (!_participantIds.contains(participantId)) return;
    setState(() {
      if (_chefParticipantId == participantId) {
        _chefParticipantId = null;
      } else {
        _chefParticipantId = participantId;
      }
    });
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
    setState(() {
      _mealDate = DateUtils.dateOnly(picked);
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(mealsRepositoryProvider);
      final mealDayPart = tripDayPartToFirestore(_mealDayPart);
      final participantIds = _participantIds.toList()..sort();
      final mealMode = _dataModeFromMealView(_activeMealView);
      final restaurantUrl = mealMode == MealMode.restaurant
          ? _restaurantUrl.trim()
          : '';
      final potluckItems = mealMode == MealMode.potluck
          ? _potluckItems
          : const <MealPotluckItem>[];
      if (widget.isCreate) {
        await repo.addMeal(
          tripId: widget.tripId,
          name: _nameController.text,
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
        ScaffoldMessenger.of(context)
            .showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)!.mealCreated)),
            );
      } else {
        await repo.updateMeal(
          tripId: widget.tripId,
          mealId: widget.mealId!,
          name: _nameController.text,
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
        setState(_saveCurrentAsBaseline);
        ScaffoldMessenger.of(context)
            .showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)!.mealUpdated)),
            );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(
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
      ScaffoldMessenger.of(context)
          .showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.mealDeleted)),
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(
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
            body: Center(child: Text(l10n.commonErrorWithDetails(e.toString()))),
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
              _saveCurrentAsBaseline();
            }

            final changedComponentIds = _changedComponentIds;
            final participantIdsForRisk = _participantIds.toList()..sort();
            final participantIdsRiskKey = participantIdsForRisk.join('|');
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

            return PopScope(
                canPop: _allowNextPop || !_hasUnsavedChanges,
                onPopInvokedWithResult: (didPop, _) async {
                  if (didPop) return;
                  final allow = await _confirmDiscardIfNeeded();
                  if (!allow || !context.mounted) return;
                  setState(() => _allowNextPop = true);
                  Navigator.of(context).pop();
                },
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(
                      '${widget.isCreate ? l10n.mealNew : l10n.mealEdit}'
                      '${_hasUnsavedChanges ? ' • ${l10n.commonUnsaved}' : ''}',
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
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                  body: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        TextFormField(
                          controller: _nameController,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: l10n.mealNameLabel,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.commonDate),
                          subtitle: Text(
                            DateFormat(
                              'EEEE d MMMM yyyy',
                              Localizations.localeOf(context).toString(),
                            ).format(_mealDate),
                          ),
                          trailing: TextButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text(l10n.commonChoose),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.mealMomentLabel,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final part in TripDayPart.values)
                              ChoiceChip(
                                label: Text(_dayPartLabel(context, part)),
                                selected: _mealDayPart == part,
                                onSelected: (_) => setState(() {
                                  _mealDayPart = part;
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.mealParticipantsCount(_participantIds.length),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  _autoRecalculateParticipants(memberIds),
                              icon: const Icon(Icons.auto_fix_high_outlined),
                              label: Text(l10n.commonAuto),
                            ),
                            TextButton.icon(
                              onPressed: () => _selectAllParticipants(memberIds),
                              icon: const Icon(Icons.done_all_outlined),
                              label: Text(l10n.commonSelectAll),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_activeMealView == _MealDetailsView.cooked) ...[
                          Text(
                            l10n.mealChefLongPressHint,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
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
                                      showCheckmark: !isChef,
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
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                          : null,
                                      side: isChef
                                          ? BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            )
                                          : null,
                                      onSelected: (selected) {
                                        setState(() {
                                          if (selected) {
                                            _participantIds.add(memberId);
                                          } else {
                                            _participantIds.remove(memberId);
                                            if (_chefParticipantId == memberId) {
                                              _chefParticipantId = null;
                                            }
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
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
                                onSelectionChanged: (selection) {
                                  if (selection.isEmpty) return;
                                  setState(() {
                                    _activeMealView = selection.first;
                                    if (_activeMealView !=
                                        _MealDetailsView.cooked) {
                                      _chefParticipantId = null;
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _mealModeDisplayLabel(l10n),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                        const SizedBox(height: 12),
                        if (_activeMealView == _MealDetailsView.cooked) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.mealComponentsTitle,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              PopupMenuButton<MealComponentKind>(
                                tooltip: l10n.mealAddComponent,
                                onSelected: _addComponent,
                                itemBuilder: (context) => [
                                  for (final kind in MealComponentKind.values)
                                    PopupMenuItem(
                                      value: kind,
                                      child: Text(
                                        l10n.mealAddComponentWithKind(
                                          _componentKindLabel(l10n, kind),
                                        ),
                                      ),
                                    ),
                                ],
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Icon(Icons.add_circle_outline),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_components.isEmpty)
                            Text(
                              l10n.mealAddComponentHint,
                              style: Theme.of(context).textTheme.bodyMedium,
                            )
                          else
                            ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              itemCount: _components.length,
                              onReorder: _reorderComponents,
                              itemBuilder: (context, index) {
                                final component = _components[index];
                                final usersData = usersAsync.asData?.value;
                                final catalogItems = catalogAsync.asData?.value;
                                final participantAllergenIds = usersData == null
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
                                    for (final item in catalogItems
                                        .where((it) => it.type == 'allergen'))
                                      item.id: item.label,
                                };

                                return Card(
                                  key: ValueKey(component.id),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    onTap: catalogItems == null
                                        ? null
                                        : () => _openComponentEditor(
                                              component: component,
                                              catalogItems: catalogItems,
                                              participantAllergenIds:
                                                  participantAllergenIds,
                                            ),
                                    leading: ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding:
                                            EdgeInsets.symmetric(horizontal: 4),
                                        child: Icon(Icons.drag_indicator),
                                      ),
                                    ),
                                    title: Text(
                                      component.title.trim().isEmpty
                                          ? _componentKindLabel(
                                              l10n,
                                              component.kind,
                                            )
                                          : component.title.trim(),
                                    ),
                                    subtitle: Text(
                                      l10n.mealIngredientsCount(
                                        component.ingredients.length,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (changedComponentIds
                                            .contains(component.id))
                                          Tooltip(
                                            message:
                                                l10n.mealComponentChangedUnsaved,
                                            child: Icon(Icons.edit_note, size: 20),
                                          ),
                                        if (risk != null &&
                                            (risk.containsAllergenIds
                                                    .isNotEmpty ||
                                                risk.mayContainAllergenIds
                                                    .isNotEmpty))
                                          Tooltip(
                                            message: [
                                              ...risk.containsAllergenIds.map(
                                                (id) =>
                                                    l10n.mealContainsAllergen(
                                                  allergenLabelById[id] ?? id,
                                                ),
                                              ),
                                              ...risk.mayContainAllergenIds.map(
                                                (id) =>
                                                    l10n.mealMayContainAllergen(
                                                  allergenLabelById[id] ?? id,
                                                ),
                                              ),
                                            ].join('\n'),
                                            child: const Icon(
                                              Icons.warning_amber_rounded,
                                              color: Colors.orange,
                                            ),
                                          ),
                                        IconButton(
                                          tooltip: l10n.mealDeleteComponent,
                                          onPressed: () =>
                                              _deleteComponent(component.id),
                                          icon: const Icon(Icons.delete_outline),
                                        ),
                                        const Icon(Icons.chevron_right),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ] else if (_activeMealView == _MealDetailsView.restaurant) ...[
                          if (_isRestaurantLinkEditing) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _restaurantUrlController,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _saveRestaurantUrl(),
                                    decoration: InputDecoration(
                                      labelText: l10n.mealRestaurantLinkLabel,
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: l10n.commonSave,
                                  onPressed: _saveRestaurantUrl,
                                  icon: const Icon(Icons.check),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.mealRestaurantLinkHint,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ]
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    tooltip: l10n.commonEdit,
                                    onPressed: _startEditRestaurantUrl,
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ),
                                LinkPreviewCardFromFirestore(
                                  url: _restaurantUrl,
                                  preview: const {},
                                ),
                              ],
                            ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.mealPotluckTitle,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.commonAdd,
                                onPressed: _addPotluckItem,
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_potluckItems.isEmpty)
                            Text(
                              l10n.mealPotluckEmptyHint,
                              style: Theme.of(context).textTheme.bodyMedium,
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _potluckItems.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Builder(
                                    builder: (context) {
                                      final item = _potluckItems[index];
                                      final addedBy = item.addedBy.trim();
                                      final usersData = potluckUsersAsync
                                          .asData
                                          ?.value;
                                      final userData = addedBy.isEmpty
                                          ? null
                                          : usersData?[addedBy];
                                      final label = resolveTripMemberDisplayLabel(
                                        memberId: addedBy,
                                        userData: userData,
                                        tripMemberPublicLabels:
                                            trip.memberPublicLabels,
                                        currentUserId:
                                            FirebaseAuth.instance.currentUser?.uid,
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
                                        onPressed: () => _editPotluckItem(index),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: l10n.commonDelete,
                                        onPressed: () => _deletePotluckItem(index),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ],
                    ),
                  ),
                  bottomNavigationBar: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _isSaving ? l10n.commonSaving : l10n.commonSave,
                        ),
                      ),
                    ),
                  ),
                ));
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
