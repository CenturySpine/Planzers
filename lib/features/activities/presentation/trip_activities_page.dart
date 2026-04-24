import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_detail_page.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/features/trips/presentation/name_list_search.dart';
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
    final today = _dateOnly(DateTime.now());
    _agendaCenterDay = today;
    _agendaSelectedDay = today;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_agendaDayFromRouteApplied) return;
    _agendaDayFromRouteApplied = true;
    final routeDay = _agendaDayFromRoute();
    if (routeDay == null) return;
    _agendaCenterDay = routeDay;
    _agendaSelectedDay = routeDay;
  }

  DateTime? _agendaDayFromRoute() {
    try {
      final raw = GoRouterState.of(context).uri.queryParameters['agendaDay'];
      final value = (raw ?? '').trim();
      if (value.isEmpty) return null;
      final parsed = DateTime.tryParse(value);
      if (parsed == null) return null;
      return _dateOnly(parsed);
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
          final suggestionsQuery = _suggestionsSearchController.text;
          final plannedQuery = _plannedSearchController.text;
          final suggestionsEntries = _buildSuggestionsEntries(
            items,
            query: suggestionsQuery,
            creatorLabelFor: (activity) =>
                creatorLabelForActivity(
                  activity,
                  trip.memberPublicLabels,
                  unknownLabel: l10n.roleParticipant,
                ),
          );
          final plannedEntries = _buildPlannedEntries(
            items,
            query: plannedQuery,
            creatorLabelFor: (activity) =>
                creatorLabelForActivity(
                  activity,
                  trip.memberPublicLabels,
                  unknownLabel: l10n.roleParticipant,
                ),
            dayLabelFor: (day) => _dayLabelFor(day, l10n),
          );
          final agendaItems = _buildAgendaItemsForDay(
            items,
            selectedDay: _agendaSelectedDay,
          );
          final plannedDays = _plannedDaysSet(items);

          return DefaultTabController(
            length: 3,
            initialIndex: 2,
            child: Column(
              children: [
                const SizedBox(height: 8),
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
                      _ActivitiesTabList(
                        searchController: _suggestionsSearchController,
                        onSearchChanged: (_) => setState(() {}),
                        entries: suggestionsEntries,
                        tripId: trip.id,
                        tripMemberPublicLabels: trip.memberPublicLabels,
                        emptyMessage: l10n.activitiesNoSuggestion,
                      ),
                      _ActivitiesTabList(
                        searchController: _plannedSearchController,
                        onSearchChanged: (_) => setState(() {}),
                        entries: plannedEntries,
                        tripId: trip.id,
                        tripMemberPublicLabels: trip.memberPublicLabels,
                        emptyMessage: l10n.activitiesNoPlanned,
                      ),
                      _ActivitiesAgendaTab(
                        centerDay: _agendaCenterDay,
                        selectedDay: _agendaSelectedDay,
                        plannedDays: plannedDays,
                        agendaItems: agendaItems,
                        tripId: trip.id,
                        tripMemberPublicLabels: trip.memberPublicLabels,
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
              onPressed: () => _openAddActivitySheet(context, ref, trip.id),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _ActivitiesTabList extends StatelessWidget {
  const _ActivitiesTabList({
    required this.searchController,
    required this.onSearchChanged,
    required this.entries,
    required this.tripId,
    required this.tripMemberPublicLabels,
    required this.emptyMessage,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final List<_ActivitiesListEntry> entries;
  final String tripId;
  final Map<String, String> tripMemberPublicLabels;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: NameListSearchTextField(
            controller: searchController,
            onChanged: onSearchChanged,
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      searchController.text.trim().isEmpty
                          ? emptyMessage
                          : nameListSearchEmptyMessage(context),
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
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    if (entry.dayLabel != null) {
                      return _ActivityDayPill(label: entry.dayLabel!);
                    }
                    return _ActivityListTile(
                      tripId: tripId,
                      activity: entry.activity!,
                      tripMemberPublicLabels: tripMemberPublicLabels,
                    );
                  },
                ),
        ),
      ],
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
  final VoidCallback onMoveBackward;
  final VoidCallback onMoveForward;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final weekDays = List<DateTime>.generate(
      7,
      (index) => centerDay.add(Duration(days: index - 3)),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: onMoveBackward,
                icon: const Icon(Icons.chevron_left),
                tooltip: AppLocalizations.of(context)!.activitiesPreviousWeek,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Row(
                  children: [
                    for (final day in weekDays)
                      Expanded(
                        child: _AgendaDayCell(
                          day: day,
                          isSelected: _isSameDay(day, selectedDay),
                          hasPlannedActivities: plannedDays.contains(day),
                          onTap: () => onSelectDay(day),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onMoveForward,
                icon: const Icon(Icons.chevron_right),
                tooltip: AppLocalizations.of(context)!.activitiesNextWeek,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
              ),
            ],
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
                    return _ActivityListTile(
                      tripId: tripId,
                      activity: agendaItems[index],
                      tripMemberPublicLabels: tripMemberPublicLabels,
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
    final isToday = _isSameDay(day, _dateOnly(DateTime.now()));
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

class _ActivityListTile extends StatelessWidget {
  const _ActivityListTile({
    required this.tripId,
    required this.activity,
    required this.tripMemberPublicLabels,
  });

  final String tripId;
  final TripActivity activity;
  final Map<String, String> tripMemberPublicLabels;

  void _openDetail(BuildContext context) {
    context.push('/trips/$tripId/activities/${activity.id}');
  }

  @override
  Widget build(BuildContext context) {
    final label = activity.label.trim().isEmpty
        ? AppLocalizations.of(context)!.activitiesUntitled
        : activity.label.trim();

    return Card(
      color: activity.done ? context.planerzColors.successContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                activity.category.categoryIcon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(
                        context,
                      )!.activitiesProposedBy(_creatorLabel(context, activity)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              LinkPreviewThumbnail(preview: activity.linkPreview),
            ],
          ),
        ),
      ),
    );
  }

  String _creatorLabel(BuildContext context, TripActivity activity) {
    return creatorLabelForActivity(
      activity,
      tripMemberPublicLabels,
      unknownLabel: AppLocalizations.of(context)!.roleParticipant,
    );
  }
}

List<_ActivitiesListEntry> _buildSuggestionsEntries(
  List<TripActivity> items, {
  required String query,
  required String Function(TripActivity activity) creatorLabelFor,
}) {
  final suggestions = items
      .where((a) => a.plannedAt == null)
      .where(
        (a) => _activityMatchesQuery(
          a,
          query,
          creatorLabel: creatorLabelFor(a),
        ),
      )
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return suggestions.map(_ActivitiesListEntry.activity).toList();
}

List<_ActivitiesListEntry> _buildPlannedEntries(
  List<TripActivity> items, {
  required String query,
  required String Function(TripActivity activity) creatorLabelFor,
  required String Function(DateTime day) dayLabelFor,
}) {
  final dated = items
      .where((a) => a.plannedAt != null)
      .where(
        (a) => _activityMatchesQuery(
          a,
          query,
          creatorLabel: creatorLabelFor(a),
        ),
      )
      .toList()
    ..sort((a, b) {
      final aDate = _activityDateForGrouping(a);
      final bDate = _activityDateForGrouping(b);
      final byDay = bDate.compareTo(aDate);
      if (byDay != 0) return byDay;
      return b.createdAt.compareTo(a.createdAt);
    });

  final entries = <_ActivitiesListEntry>[];

  DateTime? previousDay;
  for (final activity in dated) {
    final date = _activityDateForGrouping(activity).toLocal();
    final day = DateTime(date.year, date.month, date.day);
    if (previousDay == null || previousDay != day) {
      entries.add(_ActivitiesListEntry.separator(dayLabelFor(day)));
      previousDay = day;
    }
    entries.add(_ActivitiesListEntry.activity(activity));
  }
  return entries;
}

List<TripActivity> _buildAgendaItemsForDay(
  List<TripActivity> items, {
  required DateTime selectedDay,
}) {
  final filtered = items
      .where((activity) => activity.plannedAt != null)
      .where(
          (activity) => _isSameDay(_dateOnly(activity.plannedAt!), selectedDay))
      .toList()
    ..sort((a, b) {
      final aPlanned = a.plannedAt!;
      final bPlanned = b.plannedAt!;
      final byPlanned = aPlanned.compareTo(bPlanned);
      if (byPlanned != 0) return byPlanned;
      return b.createdAt.compareTo(a.createdAt);
    });
  return filtered;
}

Set<DateTime> _plannedDaysSet(List<TripActivity> items) {
  return items
      .where((activity) => activity.plannedAt != null)
      .map((activity) => _dateOnly(activity.plannedAt!))
      .toSet();
}

DateTime _activityDateForGrouping(TripActivity activity) {
  return activity.plannedAt ?? activity.doneAt ?? activity.createdAt;
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _activityMatchesQuery(
  TripActivity activity,
  String rawQuery, {
  required String creatorLabel,
}) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return true;
  final previewValues = activity.linkPreview.values
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty);
  final haystack = <String>[
    activity.id,
    activity.label,
    activity.category.categoryLabelFr,
    activity.linkUrl,
    activity.address,
    activity.freeComments,
    activity.createdBy,
    creatorLabel,
    ...previewValues,
  ].join(' ').toLowerCase();
  return haystack.contains(query);
}

String creatorLabelForActivity(
  TripActivity activity,
  Map<String, String> tripMemberPublicLabels,
  {required String unknownLabel}
) {
  final id = activity.createdBy.trim();
  if (id.isEmpty) return unknownLabel;
  return tripMemberPublicLabels[id]?.trim().isNotEmpty == true
      ? tripMemberPublicLabels[id]!.trim()
      : id;
}

class _ActivityDayPill extends StatelessWidget {
  const _ActivityDayPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivitiesListEntry {
  const _ActivitiesListEntry.activity(this.activity) : dayLabel = null;
  const _ActivitiesListEntry.separator(this.dayLabel) : activity = null;

  final TripActivity? activity;
  final String? dayLabel;
}

Future<void> _openAddActivitySheet(
  BuildContext context,
  WidgetRef ref,
  String tripId,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _AddActivitySheet(
          tripId: tripId,
          onSaved: () {
            Navigator.of(sheetContext).pop();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context)!.activitiesAdded,
                  ),
                ),
              );
            }
          },
        ),
      );
    },
  );
}

class _AddActivitySheet extends ConsumerStatefulWidget {
  const _AddActivitySheet({
    required this.tripId,
    required this.onSaved,
  });

  final String tripId;
  final VoidCallback onSaved;

  @override
  ConsumerState<_AddActivitySheet> createState() => _AddActivitySheetState();
}

class _AddActivitySheetState extends ConsumerState<_AddActivitySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _linkController;
  late final TextEditingController _addressController;
  late final TextEditingController _commentsController;
  TripActivityCategory _category = TripActivityCategory.visit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
    _linkController = TextEditingController();
    _addressController = TextEditingController();
    _commentsController = TextEditingController();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _linkController.dispose();
    _addressController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  String? _validateOptionalUrl(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.isAbsolute) {
      return AppLocalizations.of(context)!.linkInvalidExample;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return AppLocalizations.of(context)!.activitiesLinkMustStartHttp;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _saving = true);
    try {
      await ref.read(activitiesRepositoryProvider).addActivity(
            tripId: widget.tripId,
            label: _labelController.text,
            category: _category,
            linkUrl: _linkController.text,
            address: _addressController.text,
            freeComments: _commentsController.text,
          );
      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(e.toString()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppLocalizations.of(context)!.activitiesNewActivity,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.activitiesCategory,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in TripActivityCategory.values)
                  FilterChip(
                    avatar: Icon(c.categoryIcon, size: 18),
                    label: Text(_activityCategoryLabel(context, c)),
                    selected: _category == c,
                    onSelected:
                        _saving ? null : (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _labelController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.activitiesLabel,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return AppLocalizations.of(context)!.activitiesLabelRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _linkController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.activitiesLink,
                hintText: 'https://...',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              validator: _validateOptionalUrl,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.activitiesAddress,
                hintText: AppLocalizations.of(context)!.activitiesAddressHint,
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _commentsController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.activitiesComments,
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              minLines: 2,
              maxLines: 6,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppLocalizations.of(context)!.commonSave),
            ),
          ],
        ),
      ),
    );
  }
}

String _activityCategoryLabel(BuildContext context, TripActivityCategory category) {
  final l10n = AppLocalizations.of(context)!;
  return switch (category) {
    TripActivityCategory.sport => l10n.activityCategorySport,
    TripActivityCategory.hiking => l10n.activityCategoryHiking,
    TripActivityCategory.shopping => l10n.activityCategoryShopping,
    TripActivityCategory.visit => l10n.activityCategoryVisit,
    TripActivityCategory.restaurant => l10n.activityCategoryRestaurant,
  };
}
