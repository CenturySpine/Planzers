import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_card.dart';
import 'package:planerz/features/activities/presentation/trip_activity_creators_provider.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/features/activities/presentation/trip_activity_searchable_tab_list.dart';
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
    return DateFormat('d MMM yyyy', localeTag).format(day);
  }

  late final NotificationCenterRepository _notificationCenter;
  DateTime? _lastReadMarkedAt;
  DateTime? _lastPresencePingAt;
  String? _presenceTripId;
  final TextEditingController _suggestionsSearchController =
      TextEditingController();
  final TextEditingController _plannedSearchController =
      TextEditingController();
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
    _syncPresenceIfNeeded(trip.id);
    final activitiesAsync = ref.watch(tripActivitiesStreamProvider(trip.id));

    return Scaffold(
      body: activitiesAsync.when(
        data: (items) {
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
          final suggestionsQuery = _suggestionsSearchController.text;
          final plannedQuery = _plannedSearchController.text;
          final suggestionsEntries = buildTripActivitiesSuggestionEntries(
            items,
            query: suggestionsQuery,
            creatorLabelFor: (activity) => creatorLabelForActivity(
              activity,
              trip.memberPublicLabels,
              usersDataById: creatorsDataById,
              currentUserId: myUid,
              unknownLabel: l10n.roleParticipant,
            ),
          );
          final plannedEntries = buildTripActivitiesPlannedEntries(
            items,
            query: plannedQuery,
            creatorLabelFor: (activity) => creatorLabelForActivity(
              activity,
              trip.memberPublicLabels,
              usersDataById: creatorsDataById,
              currentUserId: myUid,
              unknownLabel: l10n.roleParticipant,
            ),
            dayLabelFor: (day) => _dayLabelFor(day, l10n),
          );
          final agendaItems = tripActivitiesAgendaItemsForDay(
            items,
            selectedDay: _agendaSelectedDay,
          );
          final plannedDays = tripActivitiesPlannedDaysSet(items);

          return DefaultTabController(
            length: 3,
            initialIndex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.tripTabActivities,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TabBar(
                  tabs: [
                    Tab(text: l10n.activitiesTabSuggestions),
                    Tab(text: l10n.activitiesTabPlanned),
                    Tab(text: l10n.activitiesTabAgenda),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      TripActivitiesSearchableTabList(
                        searchController: _suggestionsSearchController,
                        onSearchChanged: (_) => setState(() {}),
                        entries: suggestionsEntries,
                        tripId: trip.id,
                        tripMemberPublicLabels: trip.memberPublicLabels,
                        usersDataById: creatorsDataById,
                        currentUserId: myUid,
                        emptyMessage: l10n.activitiesNoSuggestion,
                        showVoteButton: true,
                        myUid: myUid,
                      ),
                      TripActivitiesSearchableTabList(
                        searchController: _plannedSearchController,
                        onSearchChanged: (_) => setState(() {}),
                        entries: plannedEntries,
                        tripId: trip.id,
                        tripMemberPublicLabels: trip.memberPublicLabels,
                        usersDataById: creatorsDataById,
                        currentUserId: myUid,
                        emptyMessage: l10n.activitiesNoPlanned,
                      ),
                      _ActivitiesAgendaTab(
                        centerDay: _agendaCenterDay,
                        selectedDay: _agendaSelectedDay,
                        plannedDays: plannedDays,
                        agendaItems: agendaItems,
                        tripId: trip.id,
                        tripMemberPublicLabels: trip.memberPublicLabels,
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
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.commonErrorWithDetails(e.toString()),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      floatingActionButton: canSuggestActivity
          ? FloatingActionButton(
              heroTag: 'trip_activities_add',
              tooltip: l10n.activitiesSuggestAction,
              onPressed: () => context.push('/trips/${trip.id}/activities/new'),
              child: const Icon(Icons.add),
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
    required this.agendaItems,
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
  final List<TripActivity> agendaItems;
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
    final weekStart = startOfAtomicWeekForLocale(centerDay, locale);
    final weekDays = List<DateTime>.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );
    final monthSpans = _agendaMonthSpans(
      weekDays,
      localeTag: Localizations.localeOf(context).toString(),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: _AgendaWeekGrid(
            weekDays: weekDays,
            monthSpans: monthSpans,
            selectedDay: selectedDay,
            plannedDays: plannedDays,
            onSelectDay: onSelectDay,
            onMoveBackward: onMoveBackward,
            onMoveForward: onMoveForward,
          ),
        ),
        Expanded(
          child: agendaItems.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      AppLocalizations.of(context)!.activitiesNoPlannedThisDay,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                  itemCount: agendaItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return TripActivityCard(
                      tripId: tripId,
                      activity: agendaItems[index],
                      tripMemberPublicLabels: tripMemberPublicLabels,
                      usersDataById: usersDataById,
                      currentUserId: currentUserId,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AgendaDayCell extends StatelessWidget {
  const _AgendaDayCell({
    required this.day,
    required this.isSelected,
    required this.hasPlannedActivities,
    required this.onTap,
  });

  final DateTime day;
  final bool isSelected;
  final bool hasPlannedActivities;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday =
        tripActivitiesSameDay(day, tripActivityDateOnly(DateTime.now()));
    final textColor = isSelected ? scheme.onPrimary : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isToday ? scheme.primary : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat(
                  'E',
                  Localizations.localeOf(context).toString(),
                ).format(day),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat('d').format(day),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 8,
                child: hasPlannedActivities
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? scheme.secondaryContainer
                              : scheme.secondary,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 8, height: 8),
                      )
                    : const SizedBox(width: 8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgendaWeekGrid extends StatelessWidget {
  const _AgendaWeekGrid({
    required this.weekDays,
    required this.monthSpans,
    required this.selectedDay,
    required this.plannedDays,
    required this.onSelectDay,
    required this.onMoveBackward,
    required this.onMoveForward,
  });

  final List<DateTime> weekDays;
  final List<_AgendaMonthSpan> monthSpans;
  final DateTime selectedDay;
  final Set<DateTime> plannedDays;
  final ValueChanged<DateTime> onSelectDay;
  final VoidCallback onMoveBackward;
  final VoidCallback onMoveForward;
  static const _chevronSlotWidth = 36.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        );
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: _chevronSlotWidth),
            Expanded(
              child: SizedBox(
                height: 16,
                child: Row(
                  children: [
                    for (var i = 0; i < monthSpans.length; i++)
                      Expanded(
                        flex: monthSpans[i].dayCount,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: i < monthSpans.length - 1
                                ? Border(
                                    right: BorderSide(
                                      color: scheme.outlineVariant,
                                      width: 1,
                                    ),
                                  )
                                : null,
                          ),
                          child: Text(
                            monthSpans[i].monthLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: _chevronSlotWidth),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(
              width: _chevronSlotWidth,
              child: Center(
                child: IconButton(
                  onPressed: onMoveBackward,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: AppLocalizations.of(context)!.activitiesPreviousWeek,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: _chevronSlotWidth,
                    height: _chevronSlotWidth,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  for (final day in weekDays)
                    Expanded(
                      child: _AgendaDayCell(
                        day: day,
                        isSelected: tripActivitiesSameDay(day, selectedDay),
                        hasPlannedActivities: plannedDays.contains(day),
                        onTap: () => onSelectDay(day),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: _chevronSlotWidth,
              child: Center(
                child: IconButton(
                  onPressed: onMoveForward,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: AppLocalizations.of(context)!.activitiesNextWeek,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: _chevronSlotWidth,
                    height: _chevronSlotWidth,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AgendaMonthSpan {
  const _AgendaMonthSpan({required this.monthLabel, required this.dayCount});

  final String monthLabel;
  final int dayCount;
}

List<_AgendaMonthSpan> _agendaMonthSpans(
  List<DateTime> weekDays, {
  required String localeTag,
}) {
  final spans = <_AgendaMonthSpan>[];
  for (final day in weekDays) {
    if (spans.isEmpty ||
        spans.last.monthLabel != _agendaMonthLabel(day, localeTag)) {
      spans.add(
        _AgendaMonthSpan(
          monthLabel: _agendaMonthLabel(day, localeTag),
          dayCount: 1,
        ),
      );
    } else {
      final previous = spans.removeLast();
      spans.add(
        _AgendaMonthSpan(
          monthLabel: previous.monthLabel,
          dayCount: previous.dayCount + 1,
        ),
      );
    }
  }
  return spans;
}

String _agendaMonthLabel(DateTime day, String localeTag) {
  return DateFormat('MMMM', localeTag).format(day);
}
