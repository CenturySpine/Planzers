import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activities_ui.dart';
import 'package:planerz/features/activities/presentation/trip_activity_card.dart';
import 'package:planerz/features/activities/presentation/trip_activity_creators_provider.dart';
import 'package:planerz/features/activities/presentation/trip_activity_duration.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/features/activities/presentation/trip_activity_searchable_tab_list.dart';
import 'package:planerz/features/meals/data/meals_repository.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/meals/presentation/trip_meal_card.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripActivitiesPage extends ConsumerStatefulWidget {
  const TripActivitiesPage({super.key});

  @override
  ConsumerState<TripActivitiesPage> createState() => _TripActivitiesPageState();
}

class _TripActivitiesPageState extends ConsumerState<TripActivitiesPage> {
  String _dayLabelFor(DateTime day, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return l10n.commonToday;
    if (day == yesterday) return l10n.commonYesterday;
    final localeTag = Localizations.localeOf(context).toString();
    return DateFormat('EEEE d MMM yyyy', localeTag).format(day);
  }

  late final NotificationCenterRepository _notificationCenter;
  DateTime? _lastReadMarkedAt;
  DateTime? _lastPresencePingAt;
  String? _presenceTripId;
  final TextEditingController _suggestionsSearchController =
      TextEditingController();
  final TextEditingController _plannedSearchController =
      TextEditingController();
  final Set<ActivityFilterGroup> _activeFilters = {};
  late DateTime _agendaCenterDay;
  late DateTime _agendaSelectedDay;
  bool _agendaDayFromRouteApplied = false;

  @override
  void initState() {
    super.initState();
    _notificationCenter = ref.read(notificationCenterRepositoryProvider);
    final today = tripActivityDateOnly(DateTime.now());
    _agendaCenterDay = today;
    _agendaSelectedDay = today;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_agendaDayFromRouteApplied) return;
    _agendaDayFromRouteApplied = true;
    final routeDay = _agendaDayFromRoute();
    final trip = TripScope.of(context);
    final defaultDay = routeDay ?? defaultAgendaDayForTrip(trip);
    _agendaCenterDay = defaultDay;
    _agendaSelectedDay = defaultDay;
  }

  DateTime? _agendaDayFromRoute() {
    try {
      final raw = GoRouterState.of(context).uri.queryParameters['agendaDay'];
      final value = (raw ?? '').trim();
      if (value.isEmpty) return null;
      final parsed = DateTime.tryParse(value);
      if (parsed == null) return null;
      return tripActivityDateOnly(parsed);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    final tripId = _presenceTripId;
    if (tripId != null && tripId.isNotEmpty) {
      unawaited(
        _notificationCenter.clearOpenChannel(
          tripId: tripId,
        ),
      );
    }
    _suggestionsSearchController.dispose();
    _plannedSearchController.dispose();
    super.dispose();
  }

  bool _isActivitiesTabCurrentlyVisible() {
    try {
      final path = GoRouterState.of(context).uri.path;
      return path.endsWith('/activities');
    } catch (_) {
      return false;
    }
  }

  void _markActivitiesAsReadIfNeeded({
    required String tripId,
    required List<TripActivity> items,
  }) {
    if (!_isActivitiesTabCurrentlyVisible()) return;
    final latest = DateTime.now().toUtc();
    final lastMarked = _lastReadMarkedAt;
    if (lastMarked != null &&
        latest.difference(lastMarked) < const Duration(seconds: 2)) {
      return;
    }
    _lastReadMarkedAt = latest;
    unawaited(
      _notificationCenter.markReadUpTo(
        tripId: tripId,
        channel: TripNotificationChannel.activities,
        timestamp: latest,
      ),
    );
  }

  void _syncPresenceIfNeeded(String tripId) {
    if (!_isActivitiesTabCurrentlyVisible()) return;
    final now = DateTime.now().toUtc();
    final sameTrip = _presenceTripId == tripId;
    final shouldPing = !sameTrip ||
        _lastPresencePingAt == null ||
        now.difference(_lastPresencePingAt!) > const Duration(seconds: 25);
    if (!shouldPing) return;
    _presenceTripId = tripId;
    _lastPresencePingAt = now;
    unawaited(
      _notificationCenter.setOpenChannel(
        tripId: tripId,
        channel: TripNotificationChannel.activities,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trip = TripScope.of(context);
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final canSuggestActivity = canSuggestActivityForTrip(
      trip: trip,
      userId: myUid,
    );
    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(trip.id));
    _syncPresenceIfNeeded(trip.id);
    final activitiesAsync = ref.watch(tripActivitiesStreamProvider(trip.id));
    final mealsAsync = ref.watch(tripMealsStreamProvider(trip.id));

    final activitiesError = activitiesAsync.error;
    final mealsError = mealsAsync.error;
    final activities = activitiesAsync.asData?.value;
    final meals = mealsAsync.asData?.value;

    Widget body;
    if (activitiesError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.commonErrorWithDetails(activitiesError.toString()),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (mealsError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.commonErrorWithDetails(mealsError.toString()),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (activities == null || meals == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Builder(builder: (context) {
          final items = activities;
          _markActivitiesAsReadIfNeeded(tripId: trip.id, items: items);
          final creatorIds = items
              .map((activity) => activity.createdBy.trim())
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList(growable: false)
            ..sort();
          final creatorIdsKey = creatorIds.join('|');
          final creatorsDataAsync = creatorIdsKey.isEmpty
              ? const AsyncValue<Map<String, Map<String, dynamic>>>.data({})
              : ref.watch(tripActivityCreatorsDataProvider(creatorIdsKey));
          final creatorsDataById =
              creatorsDataAsync.asData?.value ?? const <String, Map<String, dynamic>>{};
          final mealFilterActive = _activeFilters.contains(ActivityFilterGroup.repas);
          final activeActivityFilters = _activeFilters
              .where((group) => group != ActivityFilterGroup.repas)
              .toSet();
          final hasAnyFilter = _activeFilters.isNotEmpty;
          final filteredActivities = !hasAnyFilter
              ? items
              : activeActivityFilters.isEmpty
                  ? const <TripActivity>[]
                  : items
                      .where(
                        (activity) => activeActivityFilters
                            .contains(activity.category.filterGroup),
                      )
                      .toList(growable: false);
          // For suggestions: repas filter includes restaurant activities.
          final activeSuggestionFilters = mealFilterActive
              ? {...activeActivityFilters, ActivityFilterGroup.repas}
              : activeActivityFilters;
          final filteredActivitiesForSuggestions = !hasAnyFilter
              ? items
              : activeSuggestionFilters.isEmpty
                  ? const <TripActivity>[]
                  : items
                      .where(
                        (activity) => activeSuggestionFilters
                            .contains(activity.category.filterGroup),
                      )
                      .toList(growable: false);
          final filteredMeals = _activeFilters.isEmpty || mealFilterActive
              ? meals
              : const <TripMeal>[];

          final suggestionsQuery = _suggestionsSearchController.text;
          final plannedQuery = _plannedSearchController.text;
          final suggestionsEntries = buildTripActivitiesSuggestionEntries(
            filteredActivitiesForSuggestions,
            query: suggestionsQuery,
            creatorLabelFor: (activity) => creatorLabelForActivity(
              activity,
              memberLabels,
              unknownLabel: l10n.roleParticipant,
            ),
          );
          final plannedEntries = buildTripActivitiesPlannedEntriesMixed(
            activities: filteredActivities,
            meals: filteredMeals,
            query: plannedQuery,
            creatorLabelForActivity: (activity) => creatorLabelForActivity(
                  activity,
                  memberLabels,
                  unknownLabel: l10n.roleParticipant,
                ),
            dayLabelFor: (day) => _dayLabelFor(day, l10n),
          );
          final agendaEntries = tripActivitiesAgendaEntriesForDayMixed(
            activities: filteredActivities,
            meals: filteredMeals,
            selectedDay: _agendaSelectedDay,
          );
          final plannedDays = tripActivitiesPlannedDaysSetMixed(
            activities: items,
            meals: meals,
          );
          final dayGroups = <DateTime, Set<ActivityFilterGroup>>{};
          for (final activity in items) {
            final plannedAt = activity.plannedAt;
            if (plannedAt == null) continue;
            dayGroups
                .putIfAbsent(tripActivityDateOnly(plannedAt), () => {})
                .add(activity.category.filterGroup);
          }
          for (final meal in meals) {
            final day = DateTime.tryParse(meal.mealDateKey);
            if (day == null) continue;
            dayGroups
                .putIfAbsent(tripActivityDateOnly(day), () => {})
                .add(ActivityFilterGroup.repas);
          }

          final filterLabels = {
            ActivityFilterGroup.repas: l10n.activitiesFilterRepas,
            ActivityFilterGroup.nuits: l10n.activitiesFilterNuits,
            ActivityFilterGroup.loisirs: l10n.activitiesFilterLoisirs,
            ActivityFilterGroup.trajets: l10n.activitiesFilterTrajets,
          };

          return DefaultTabController(
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TripActivitiesSegmentedTabBar(
                  labels: [
                    l10n.activitiesTabAgenda,
                    l10n.activitiesTabPlanned,
                    l10n.activitiesTabSuggestions,
                  ],
                ),
                TripActivitiesFilterChips(
                  activeFilters: _activeFilters,
                  filterLabels: filterLabels,
                  onToggle: (group) => setState(() {
                    if (_activeFilters.contains(group)) {
                      _activeFilters.remove(group);
                    } else {
                      _activeFilters.add(group);
                    }
                  }),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _ActivitiesAgendaTab(
                        centerDay: _agendaCenterDay,
                        selectedDay: _agendaSelectedDay,
                        plannedDays: plannedDays,
                        dayGroups: dayGroups,
                        tripStartDate: trip.startDate,
                        tripEndDate: trip.endDate,
                        agendaEntries: agendaEntries,
                        tripId: trip.id,
                        tripMemberPublicLabels: memberLabels,
                        usersDataById: creatorsDataById,
                        currentUserId: myUid,
                        onMoveBackward: () => setState(
                          () => _agendaCenterDay = _agendaCenterDay.subtract(
                            const Duration(days: 7),
                          ),
                        ),
                        onMoveForward: () => setState(
                          () => _agendaCenterDay = _agendaCenterDay.add(
                            const Duration(days: 7),
                          ),
                        ),
                        onSelectDay: (day) => setState(
                          () => _agendaSelectedDay = day,
                        ),
                      ),
                      TripActivitiesSearchableTabList(
                        searchController: _plannedSearchController,
                        onSearchChanged: (_) => setState(() {}),
                        entries: plannedEntries,
                        tripId: trip.id,
                        tripMemberPublicLabels: memberLabels,
                        usersDataById: creatorsDataById,
                        currentUserId: myUid,
                        emptyMessage: l10n.activitiesNoPlanned,
                      ),
                      TripActivitiesSearchableTabList(
                        searchController: _suggestionsSearchController,
                        onSearchChanged: (_) => setState(() {}),
                        entries: suggestionsEntries,
                        tripId: trip.id,
                        tripMemberPublicLabels: memberLabels,
                        usersDataById: creatorsDataById,
                        currentUserId: myUid,
                        emptyMessage: l10n.activitiesNoSuggestion,
                        showVoteButton: true,
                        myUid: myUid,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
      });
    }

    final canCreateMeal = canCreateMealForTrip(
      trip: trip,
      userId: myUid,
    );

    return Scaffold(
      body: body,
      floatingActionButton: canSuggestActivity
          ? _ActivitiesExpandableFab(
              tripId: trip.id,
              canCreateMeal: canCreateMeal,
            )
          : null,
    );
  }
}

class _ActivitiesAgendaTab extends StatelessWidget {
  const _ActivitiesAgendaTab({
    required this.centerDay,
    required this.selectedDay,
    required this.plannedDays,
    required this.dayGroups,
    required this.tripStartDate,
    required this.tripEndDate,
    required this.agendaEntries,
    required this.tripId,
    required this.tripMemberPublicLabels,
    required this.usersDataById,
    required this.currentUserId,
    required this.onMoveBackward,
    required this.onMoveForward,
    required this.onSelectDay,
  });

  final DateTime centerDay;
  final DateTime selectedDay;
  final Set<DateTime> plannedDays;
  final Map<DateTime, Set<ActivityFilterGroup>> dayGroups;
  final DateTime? tripStartDate;
  final DateTime? tripEndDate;
  final List<TripActivitiesListEntry> agendaEntries;
  final String tripId;
  final Map<String, String> tripMemberPublicLabels;
  final Map<String, Map<String, dynamic>> usersDataById;
  final String? currentUserId;
  final VoidCallback onMoveBackward;
  final VoidCallback onMoveForward;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final localeTag = locale.toString();
    final weekStart = startOfAtomicWeekForLocale(centerDay, locale);
    final weekDays = List<DateTime>.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );
    final dayTitle = DateFormat('EEEE d MMMM', localeTag).format(selectedDay);
    final visibleEntries = agendaEntries
        .where((e) => e.activity != null || e.meal != null)
        .toList(growable: false);

    return Column(
      children: [
        TripActivitiesAgendaWeekStrip(
          weekDays: weekDays,
          selectedDay: selectedDay,
          plannedDays: plannedDays,
          dayGroups: dayGroups,
          tripStartDate: tripStartDate,
          tripEndDate: tripEndDate,
          onSelectDay: onSelectDay,
          onMoveBackward: onMoveBackward,
          onMoveForward: onMoveForward,
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 16, 88),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: TripActivityDaySeparatorRail(label: dayTitle),
              ),
              if (visibleEntries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    AppLocalizations.of(context)!.activitiesNoPlannedThisDay,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTokens.onSurfaceVariant,
                    ),
                  ),
                ),
              for (var index = 0; index < visibleEntries.length; index++)
                _buildTimelineRow(
                  context,
                  visibleEntries[index],
                  isFirst: index == 0,
                  isLast: index == visibleEntries.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineRow(
    BuildContext context,
    TripActivitiesListEntry entry, {
    required bool isFirst,
    required bool isLast,
  }) {
    final activity = entry.activity;
    if (activity != null) {
      final plannedAt = activity.plannedAt;
      final end = tripActivityEndTime(context, activity);
      return TripAgendaTimelineRow(
        timeLabel: plannedAt == null
            ? ''
            : DateFormat.Hm(Localizations.localeOf(context).toString())
                .format(plannedAt.toLocal()),
        endTimeLabel: end?.time,
        endDayOffset: end?.dayOffset ?? 0,
        color: activity.category.filterGroup.filterColor,
        isFirst: isFirst,
        isLast: isLast,
        child: TripActivityCard(
          tripId: tripId,
          activity: activity,
          tripMemberPublicLabels: tripMemberPublicLabels,
          showTime: false,
        ),
      );
    }
    final meal = entry.meal!;
    return TripAgendaTimelineRow(
      timeLabel: meal.mealTimeHHMM,
      color: ActivityFilterGroup.repas.filterColor,
      isFirst: isFirst,
      isLast: isLast,
      child: TripMealCard(
        tripId: tripId,
        meal: meal,
        memberLabels: tripMemberPublicLabels,
        showTime: false,
      ),
    );
  }
}

/// Planning "+" button: opens a standard bottom sheet listing what can be
/// added (one row per category, in its hue).
class _ActivitiesExpandableFab extends StatelessWidget {
  const _ActivitiesExpandableFab({
    required this.tripId,
    required this.canCreateMeal,
  });

  final String tripId;
  final bool canCreateMeal;

  void _openActivityCreate(
    BuildContext context,
    List<TripActivityCategory> categories,
  ) {
    final param = categories.map((c) => c.firestoreValue).join(',');
    context.push('/trips/$tripId/activities/new?initialCategory=$param');
  }

  Future<void> _openSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final loisirCategories = TripActivityCategory.values
        .where((c) =>
            c != TripActivityCategory.accommodation &&
            c != TripActivityCategory.transport)
        .toList();
    final choice = await showModalBottomSheet<VoidCallback>(
      context: context,
      builder: (sheetContext) {
        Widget option(ActivityFilterGroup group, String label,
                VoidCallback action) =>
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: group.filterLightBgColor,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Icon(group.filterIcon,
                    size: 20, color: group.filterColor),
              ),
              title: Text(label),
              trailing: const Icon(PhosphorIconsRegular.plus),
              onTap: () => Navigator.of(sheetContext).pop(action),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Text(
                    l10n.commonAdd,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                option(
                  ActivityFilterGroup.loisirs,
                  l10n.activitiesFilterLoisirs,
                  () => _openActivityCreate(context, loisirCategories),
                ),
                if (canCreateMeal)
                  option(
                    ActivityFilterGroup.repas,
                    l10n.activitiesFilterRepas,
                    () => context.push('/trips/$tripId/meals/new'),
                  ),
                option(
                  ActivityFilterGroup.nuits,
                  l10n.activitiesFilterNuits,
                  () => _openActivityCreate(
                      context, [TripActivityCategory.accommodation]),
                ),
                option(
                  ActivityFilterGroup.trajets,
                  l10n.activitiesFilterTrajets,
                  () => _openActivityCreate(
                      context, [TripActivityCategory.transport]),
                ),
              ],
            ),
          ),
        );
      },
    );
    choice?.call();
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'trip_activities_add',
      tooltip: AppLocalizations.of(context)!.commonAdd,
      onPressed: () => _openSheet(context),
      child: const Icon(PhosphorIconsRegular.plus, size: 28),
    );
  }
}
