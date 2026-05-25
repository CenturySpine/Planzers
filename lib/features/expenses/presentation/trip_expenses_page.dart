import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/expenses/data/expense.dart';
import 'package:planerz/features/expenses/data/expense_group.dart';
import 'package:planerz/features/expenses/data/expenses_repository.dart';
import 'package:planerz/features/expenses/data/expenses_states.dart';
import 'package:planerz/features/expenses/data/suggested_reimbursement.dart';
import 'package:planerz/features/expenses/presentation/expense_group_editor_page.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_member.dart';
import 'package:planerz/core/presentation/state_pill_toggle.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Participant doc IDs who can appear as payer/participant for this expense post.
/// [group.visibleToMemberIds] holds TripMember doc IDs; returns the doc IDs of
/// all participants (including unclaimed) whose doc ID is in that set.
List<String> participantScopeMemberIdsForGroup(
  TripExpenseGroup group,
  List<TripMember> participants,
) {
  if (group.visibleToMemberIds.isEmpty) return [];
  final allowed = group.visibleToMemberIds.toSet();
  return participants
      .where((m) => allowed.contains(m.id))
      .map((m) => m.id)
      .toSet()
      .toList()
    ..sort();
}


class TripExpensesPage extends ConsumerStatefulWidget {
  const TripExpensesPage({super.key});

  @override
  ConsumerState<TripExpensesPage> createState() => _TripExpensesPageState();
}

class _TripExpensesPageState extends ConsumerState<TripExpensesPage> {
  String? _activeGroupId;
  bool _isFabMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trip = TripScope.of(context);
    final groupsAsync = ref.watch(tripExpenseGroupsStreamProvider(trip.id));
    final expensesAsync = ref.watch(tripExpensesStreamProvider(trip.id));
    final participants =
        ref.watch(tripParticipantsStreamProvider(trip.id)).asData?.value ?? [];
    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(trip.id));
    final memberIds = participants.map((m) => m.id).toList();
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final currentUserMemberId = participants
        .where((m) => m.userId?.trim() == viewerId?.trim())
        .map((m) => m.id)
        .firstOrNull;
    final canCreateExpensePost = canCreateExpensePostForTrip(
      trip: trip,
      userId: viewerId,
    );
    final canCreateExpense = groupsAsync.maybeWhen(
      data: (groups) {
        final visibleGroups = groups
            .where((group) => group.isVisibleTo(currentUserMemberId))
            .toList();
        return visibleGroups.any(
          (group) => canCreateExpenseForTrip(
            trip: trip,
            userId: viewerId,
            currentUserMemberId: currentUserMemberId,
            expensePostVisibleToMemberIds: group.visibleToMemberIds,
          ),
        );
      },
      orElse: () => false,
    );
    final states = ref.watch(tripExpensesStatesStreamProvider(trip.id)).asData?.value ??
        TripExpensesStates.defaults;
    final isAdminOrAbove = isTripRoleAllowed(
      currentRole: resolveTripPermissionRole(trip: trip, userId: viewerId),
      minRole: TripPermissionRole.admin,
    );
    final lockRestrictsEditing = states.expensesLocked && !isAdminOrAbove;
    final showExpensesFab =
        (canCreateExpense || canCreateExpensePost) &&
        (isAdminOrAbove || !states.expensesLocked);

    return Scaffold(
      body: groupsAsync.when(
        data: (groups) => expensesAsync.when(
          data: (expenses) {
            return _TripExpensesBody(
              trip: trip,
              participants: participants,
              memberLabels: memberLabels,
              memberIds: memberIds,
              currentUserMemberId: currentUserMemberId,
              groups: groups,
              expenses: expenses,
              activeGroupId: _activeGroupId,
              lockRestrictsEditing: lockRestrictsEditing,
              isAdminOrAbove: isAdminOrAbove,
              expensesLocked: states.expensesLocked,
              onActiveGroupChanged: (groupId) {
                if (_activeGroupId == groupId) return;
                setState(() => _activeGroupId = groupId);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                AppLocalizations.of(context)!.commonErrorWithDetails(e.toString()),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              AppLocalizations.of(context)!.commonErrorWithDetails(e.toString()),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      floatingActionButton: showExpensesFab
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_isFabMenuOpen) ...[
                  if (canCreateExpensePost) ...[
                    FloatingActionButton.extended(
                      heroTag: 'trip_expenses_add_post',
                      tooltip: l10n.expensesFabAddExpensePost,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: Text(l10n.expensesFabAddExpensePost),
                      onPressed: () {
                        setState(() => _isFabMenuOpen = false);
                        _openExpenseGroupEditor(
                          context,
                          trip.id,
                          memberIds,
                          memberLabels,
                          currentUserMemberId,
                          existing: null,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (canCreateExpense) ...[
                    FloatingActionButton.extended(
                      heroTag: 'trip_expenses_add_expense',
                      tooltip: l10n.expensesAddExpenseTooltip,
                      icon: const Icon(Icons.add_card_outlined),
                      label: Text(l10n.expensesAddExpenseTooltip),
                      onPressed: () {
                        setState(() => _isFabMenuOpen = false);
                        _openAddExpensePageFromFab(
                          context,
                          ref,
                          trip.id,
                          participants,
                          memberLabels,
                          _activeGroupId,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
                FloatingActionButton(
                  heroTag: 'trip_expenses_main_fab',
                  tooltip: l10n.expensesFabTooltip,
                  onPressed: () {
                    setState(() => _isFabMenuOpen = !_isFabMenuOpen);
                  },
                  child: Icon(_isFabMenuOpen ? Icons.close : Icons.add),
                ),
              ],
            )
          : null,
    );
  }

  static Future<void> _openExpenseGroupEditor(
    BuildContext context,
    String tripId,
    List<String> memberIds,
    Map<String, String> memberLabels,
    String? currentUserMemberId, {
    required TripExpenseGroup? existing,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => ExpenseGroupEditorPage(
          tripId: tripId,
          memberIds: memberIds,
          memberLabels: memberLabels,
          currentUserMemberId: currentUserMemberId,
          existing: existing,
        ),
      ),
    );
  }

  static Future<void> _openAddExpensePageFromFab(
    BuildContext context,
    WidgetRef ref,
    String tripId,
    List<TripMember> participants,
    Map<String, String> memberLabels,
    String? preferredGroupId,
  ) async {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final currentUserMemberId = participants
        .where((m) => m.userId?.trim() == viewerId?.trim())
        .map((m) => m.id)
        .firstOrNull;
    final groups =
        await ref.read(expensesRepositoryProvider).watchTripExpenseGroups(tripId).first;
    final visible = groups.where((g) => g.isVisibleTo(currentUserMemberId)).toList();
    if (!context.mounted) return;
    if (visible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.expensesCreatePostFirst,
          ),
        ),
      );
      return;
    }
    TripExpenseGroup? chosenGroup;
    if (preferredGroupId != null && preferredGroupId.trim().isNotEmpty) {
      for (final g in visible) {
        if (g.id == preferredGroupId) {
          chosenGroup = g;
          break;
        }
      }
    }
    final group = chosenGroup ?? visible.first;
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => _AddExpensePage(
          tripId: tripId,
          groupId: group.id,
          participantScopeMemberIds:
              participantScopeMemberIdsForGroup(group, participants),
          memberLabels: memberLabels,
          currentUserMemberId: currentUserMemberId,
        ),
      ),
    );
  }
}

class _TripExpensesBody extends StatelessWidget {
  const _TripExpensesBody({
    required this.trip,
    required this.participants,
    required this.memberLabels,
    required this.memberIds,
    required this.currentUserMemberId,
    required this.groups,
    required this.expenses,
    required this.activeGroupId,
    required this.lockRestrictsEditing,
    required this.isAdminOrAbove,
    required this.expensesLocked,
    required this.onActiveGroupChanged,
  });

  final Trip trip;
  final List<TripMember> participants;
  final Map<String, String> memberLabels;
  final List<String> memberIds;
  final String? currentUserMemberId;
  final List<TripExpenseGroup> groups;
  final List<TripExpense> expenses;
  final String? activeGroupId;
  final bool lockRestrictsEditing;
  final bool isAdminOrAbove;
  final bool expensesLocked;
  final ValueChanged<String> onActiveGroupChanged;

  @override
  Widget build(BuildContext context) {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final visibleGroups = groups.where((g) => g.isVisibleTo(currentUserMemberId)).toList()
      ..sort((a, b) {
        if (a.isDefault != b.isDefault) {
          return a.isDefault ? -1 : 1;
        }
        final createdAtOrder = a.createdAt.compareTo(b.createdAt);
        if (createdAtOrder != 0) return createdAtOrder;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    return _buildScrollView(context, visibleGroups, viewerId, trip);
  }

  Widget _buildScrollView(
    BuildContext context,
    List<TripExpenseGroup> visibleGroups,
    String? viewerId,
    Trip trip,
  ) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        if (visibleGroups.isEmpty)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
              child: Column(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 48,
                    color: cs.primary.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.expensesNoPostYet,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          )
        else if (visibleGroups.length == 1)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
               child: _ExpensePostPanel(
                 trip: trip,
                 group: visibleGroups.single,
                 groupExpenses: expenses
                      .where((e) => e.groupId == visibleGroups.single.id)
                      .toList(),
                  participants: participants,
                  memberIds: memberIds,
                  memberLabels: memberLabels,
                  currentUserMemberId: currentUserMemberId,
                 viewerUserId: viewerId,
                 lockRestrictsEditing: lockRestrictsEditing,
                 isAdminOrAbove: isAdminOrAbove,
                 expensesLocked: expensesLocked,
              ),
            ),
          )
        else
          Expanded(
            child: _ExpensePostsTabbedView(
              trip: trip,
              groups: visibleGroups,
               expenses: expenses,
                participants: participants,
                memberIds: memberIds,
              memberLabels: memberLabels,
              currentUserMemberId: currentUserMemberId,
              viewerUserId: viewerId,
              initialGroupId: activeGroupId,
              lockRestrictsEditing: lockRestrictsEditing,
              isAdminOrAbove: isAdminOrAbove,
              expensesLocked: expensesLocked,
              onActiveGroupChanged: onActiveGroupChanged,
            ),
          ),
      ],
    );
  }
}

class _ExpensePostsTabbedView extends StatefulWidget {
  const _ExpensePostsTabbedView({
    required this.trip,
    required this.groups,
    required this.expenses,
    required this.participants,
    required this.memberIds,
    required this.memberLabels,
    required this.currentUserMemberId,
    required this.viewerUserId,
    required this.initialGroupId,
    required this.lockRestrictsEditing,
    required this.isAdminOrAbove,
    required this.expensesLocked,
    required this.onActiveGroupChanged,
  });

  final Trip trip;
  final List<TripExpenseGroup> groups;
  final List<TripExpense> expenses;
  final List<TripMember> participants;
  final List<String> memberIds;
  final Map<String, String> memberLabels;
  final String? currentUserMemberId;
  final String? viewerUserId;
  final String? initialGroupId;
  final bool lockRestrictsEditing;
  final bool isAdminOrAbove;
  final bool expensesLocked;
  final ValueChanged<String> onActiveGroupChanged;

  @override
  State<_ExpensePostsTabbedView> createState() => _ExpensePostsTabbedViewState();
}

class _ExpensePostsTabbedViewState extends State<_ExpensePostsTabbedView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.groups.length, vsync: this);
    final initialIndex = _indexForGroupId(widget.initialGroupId);
    if (initialIndex != null) {
      _tabController.index = initialIndex;
    }
    _tabController.addListener(_onTabChanged);
    _notifyActiveGroup(deferToPostFrame: true);
  }

  @override
  void didUpdateWidget(covariant _ExpensePostsTabbedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groups.length == widget.groups.length) return;
    final oldIndex = _tabController.index;
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    _tabController = TabController(length: widget.groups.length, vsync: this);
    final newIndex = oldIndex.clamp(0, widget.groups.length - 1);
    _tabController.index = newIndex;
    _tabController.addListener(_onTabChanged);
    _notifyActiveGroup(deferToPostFrame: true);
  }

  void _onTabChanged() {
    if (!mounted) return;
    _notifyActiveGroup();
    setState(() {});
  }

  int? _indexForGroupId(String? groupId) {
    if (groupId == null || groupId.trim().isEmpty) return null;
    final index = widget.groups.indexWhere((g) => g.id == groupId);
    return index >= 0 ? index : null;
  }

  void _notifyActiveGroup({bool deferToPostFrame = false}) {
    final index = _tabController.index;
    if (index < 0 || index >= widget.groups.length) return;
    final groupId = widget.groups[index].id;
    if (deferToPostFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onActiveGroupChanged(groupId);
      });
      return;
    }
    widget.onActiveGroupChanged(groupId);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            for (final group in widget.groups)
              Tab(
                text: group.title.isEmpty
                    ? AppLocalizations.of(context)!.activitiesUntitled
                    : group.title,
              ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final group in widget.groups)
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                   child: _ExpensePostPanel(
                     trip: widget.trip,
                     group: group,
                      groupExpenses:
                          widget.expenses.where((e) => e.groupId == group.id).toList(),
                      participants: widget.participants,
                      memberIds: widget.memberIds,
                      memberLabels: widget.memberLabels,
                      currentUserMemberId: widget.currentUserMemberId,
                    viewerUserId: widget.viewerUserId,
                    lockRestrictsEditing: widget.lockRestrictsEditing,
                    isAdminOrAbove: widget.isAdminOrAbove,
                    expensesLocked: widget.expensesLocked,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpensePostPanel extends ConsumerStatefulWidget {
  const _ExpensePostPanel({
    required this.trip,
    required this.group,
    required this.groupExpenses,
    required this.participants,
    required this.memberIds,
    required this.memberLabels,
    required this.currentUserMemberId,
    required this.viewerUserId,
    required this.lockRestrictsEditing,
    required this.isAdminOrAbove,
    required this.expensesLocked,
  });

  final Trip trip;
  final TripExpenseGroup group;
  final List<TripExpense> groupExpenses;
  final List<TripMember> participants;
  final List<String> memberIds;
  final Map<String, String> memberLabels;
  final String? currentUserMemberId;
  final String? viewerUserId;
  final bool lockRestrictsEditing;
  final bool isAdminOrAbove;
  final bool expensesLocked;

  @override
  ConsumerState<_ExpensePostPanel> createState() => _ExpensePostPanelState();
}

class _ExpensePostPanelState extends ConsumerState<_ExpensePostPanel> {
  bool _deletingPost = false;
  _ExpensePostView _activeView = _ExpensePostView.operations;
  late final NotificationCenterRepository _notificationCenter;
  DateTime? _lastReadMarkedAt;
  DateTime? _lastPresencePingAt;
  String? _presenceTripId;

  @override
  void initState() {
    super.initState();
    _notificationCenter = ref.read(notificationCenterRepositoryProvider);
  }

  @override
  void dispose() {
    final tripId = _presenceTripId;
    if (tripId != null && tripId.isNotEmpty) {
      unawaited(_notificationCenter.clearOpenChannel(tripId: tripId));
    }
    super.dispose();
  }

  bool _isExpensesBalancesVisible() {
    try {
      final path = GoRouterState.of(context).uri.path;
      if (!path.endsWith('/expenses') || path.contains('/settings/')) {
        return false;
      }
      return _activeView == _ExpensePostView.settlement;
    } catch (_) {
      return false;
    }
  }

  void _markExpensesNotificationsReadIfNeeded(String tripId) {
    if (!_isExpensesBalancesVisible()) return;
    final now = DateTime.now().toUtc();
    final lastMarked = _lastReadMarkedAt;
    if (lastMarked != null &&
        now.difference(lastMarked) < const Duration(seconds: 2)) {
      return;
    }
    _lastReadMarkedAt = now;
    unawaited(
      _notificationCenter.markReadUpTo(
        tripId: tripId,
        channel: TripNotificationChannel.expenses,
        timestamp: now,
      ),
    );
  }

  void _syncExpensesPresenceIfNeeded(String tripId) {
    if (!_isExpensesBalancesVisible()) return;
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
        channel: TripNotificationChannel.expenses,
      ),
    );
  }

  void _clearExpensesPresenceIfNeeded(String tripId) {
    if (_presenceTripId != tripId) return;
    _presenceTripId = null;
    _lastPresencePingAt = null;
    unawaited(_notificationCenter.clearOpenChannel(tripId: tripId));
  }

  Future<void> _confirmDeletePost() async {
    if (_deletingPost) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.expensesDeletePostTitle),
        content: Text(
          AppLocalizations.of(context)!.expensesDeletePostBody(
            widget.group.title.isEmpty
                ? AppLocalizations.of(context)!.activitiesUntitled
                : widget.group.title,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deletingPost = true);
    try {
      await ref.read(expensesRepositoryProvider).deleteExpenseGroup(
            tripId: widget.trip.id,
            groupId: widget.group.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesPostDeleted)),
      );
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
      if (mounted) setState(() => _deletingPost = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _markExpensesNotificationsReadIfNeeded(widget.trip.id);
    _syncExpensesPresenceIfNeeded(widget.trip.id);
    final viewerUserId = widget.viewerUserId?.trim();
    final viewerMemberId = widget.currentUserMemberId?.trim();
    final groupScope = (
      tripId: widget.trip.id,
      groupId: widget.group.id,
    );
    final summary =
        ref.watch(expenseGroupSummaryStreamProvider(groupScope)).asData?.value;
    final postTotalsByCurrency = summary?.postTotalsByCurrency ?? const {};
    final myTotalsByCurrency = viewerMemberId != null
        ? summary?.paidByTotalsByCurrency[viewerMemberId] ?? const {}
        : const <String, double>{};
    final Map<String, double>? myCostByCurrency = viewerMemberId != null
        ? () {
            final result = <String, double>{};
            for (final expense in widget.groupExpenses) {
              if (expense.operationType == ExpenseOperationType.settlement) {
                continue;
              }
              if (!expense.participantIds.contains(viewerMemberId)) continue;
              final share =
                  expense.splitMode == ExpenseSplitMode.customAmounts
                      ? (expense.participantShares[viewerMemberId] ?? 0.0)
                      : (expense.participantIds.isEmpty
                          ? 0.0
                          : expense.amount / expense.participantIds.length);
              result[expense.currency] =
                  (result[expense.currency] ?? 0.0) + share;
            }
            return result;
          }()
        : null;
    final canMarkReimbursement =
        widget.group.isVisibleTo(widget.currentUserMemberId);
    final scope = participantScopeMemberIdsForGroup(
      widget.group,
      widget.participants,
    );

    final canEditPost = canEditExpensePostForTrip(
      trip: widget.trip,
      userId: viewerUserId,
      currentUserMemberId: widget.currentUserMemberId,
      expensePostVisibleToMemberIds: widget.group.visibleToMemberIds,
    );
    final canDeletePost = canDeleteExpensePostForTrip(
      trip: widget.trip,
      userId: viewerUserId,
      currentUserMemberId: widget.currentUserMemberId,
      expensePostVisibleToMemberIds: widget.group.visibleToMemberIds,
    );
    final canEditExpense = canEditExpenseForTrip(
      trip: widget.trip,
      userId: viewerUserId,
      currentUserMemberId: widget.currentUserMemberId,
      expensePostVisibleToMemberIds: widget.group.visibleToMemberIds,
    );
    final canDeleteExpense = canDeleteExpenseForTrip(
      trip: widget.trip,
      userId: viewerUserId,
      currentUserMemberId: widget.currentUserMemberId,
      expensePostVisibleToMemberIds: widget.group.visibleToMemberIds,
    );
    final effectiveCanEditPost = canEditPost && !widget.lockRestrictsEditing;
    final effectiveCanDeletePost = canDeletePost && !widget.lockRestrictsEditing;
    final effectiveCanEditExpense = canEditExpense && !widget.lockRestrictsEditing;
    final effectiveCanDeleteExpense =
        canDeleteExpense && !widget.lockRestrictsEditing;
    final showPostMenu = !widget.group.isDefault &&
        (effectiveCanEditPost || effectiveCanDeletePost);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SegmentedButton<_ExpensePostView>(
                segments: [
                  ButtonSegment<_ExpensePostView>(
                    value: _ExpensePostView.operations,
                    label: Text(l10n.tripSectionExpenses),
                    icon: const Icon(Icons.receipt_long_outlined),
                  ),
                  ButtonSegment<_ExpensePostView>(
                    value: _ExpensePostView.settlement,
                    label: Text(l10n.expensesBalancesTab),
                    icon: const Icon(Icons.balance_outlined),
                  ),
                ],
                selected: {_activeView},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  final next = selection.first;
                  setState(() => _activeView = next);
                  if (next == _ExpensePostView.settlement) {
                    _markExpensesNotificationsReadIfNeeded(widget.trip.id);
                    _syncExpensesPresenceIfNeeded(widget.trip.id);
                  } else {
                    _clearExpensesPresenceIfNeeded(widget.trip.id);
                  }
                },
              ),
            ),
            if (showPostMenu)
              PopupMenuButton<_ExpensePostMenuAction>(
                    tooltip: l10n.tripOverviewActions,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) async {
                      if (action == _ExpensePostMenuAction.edit) {
                        await _TripExpensesPageState._openExpenseGroupEditor(
                          context,
                          widget.trip.id,
                          widget.memberIds,
                          widget.memberLabels,
                          widget.currentUserMemberId,
                          existing: widget.group,
                        );
                        return;
                      }
                      await _confirmDeletePost();
                    },
                    itemBuilder: (context) {
                      final items = <PopupMenuEntry<_ExpensePostMenuAction>>[];
                      if (effectiveCanEditPost) {
                        items.add(
                          PopupMenuItem<_ExpensePostMenuAction>(
                            value: _ExpensePostMenuAction.edit,
                            child: Row(
                              children: [
                                const Icon(Icons.edit_outlined, size: 18),
                                const SizedBox(width: 10),
                                Text(l10n.commonEdit),
                              ],
                            ),
                          ),
                        );
                      }
                      if (effectiveCanDeletePost) {
                        items.add(
                          PopupMenuItem<_ExpensePostMenuAction>(
                            value: _ExpensePostMenuAction.delete,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  l10n.commonDelete,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return items;
                    },
                  ),
          ],
        ),
        const SizedBox(height: 12),
        if (_activeView == _ExpensePostView.settlement)
          _SettlementSection(
            tripId: widget.trip.id,
            group: widget.group,
            groupExpenses: widget.groupExpenses,
            memberLabels: widget.memberLabels,
            currentUserMemberId: widget.currentUserMemberId,
            canMarkReimbursement: canMarkReimbursement,
            expensesLocked: widget.expensesLocked,
            isAdmin: widget.isAdminOrAbove,
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _ExpenseTotalsHeader(
                      myTotalsByCurrency: myTotalsByCurrency,
                      postTotalsByCurrency: postTotalsByCurrency,
                      myCostByCurrency: myCostByCurrency,
                    ),
                  ),
                  if (widget.expensesLocked) ...[
                    const SizedBox(width: 8),
                    const _ExpensesLockedIndicator(),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              if (widget.groupExpenses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 40,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.35),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.expensesNoOperationInPost,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                )
              else
                ..._buildExpensesGroupedByDate(
                  context,
                  widget.groupExpenses,
                  widget.trip.id,
                  scope,
                  widget.memberLabels,
                  canEditExpense: effectiveCanEditExpense,
                  canDeleteExpense: effectiveCanDeleteExpense,
                ),
            ],
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

enum _ExpensePostView { operations, settlement }

const _kDefaultExpenseCurrency = 'EUR';

String _formatTotalsByCurrency(Map<String, double> totalsByCurrency) {
  if (totalsByCurrency.isEmpty) {
    return _formatMoney(_kDefaultExpenseCurrency, 0);
  }
  final sortedEntries = totalsByCurrency.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return sortedEntries
      .map((entry) => _formatMoney(entry.key, entry.value))
      .join(' · ');
}

String _formatMoney(String currency, double amount) {
  final c = currency.trim().toUpperCase();
  if (c == 'EUR') {
    return NumberFormat.currency(locale: 'fr_FR', symbol: '€').format(amount);
  }
  if (c == 'USD') {
    return NumberFormat.currency(locale: 'en_US', symbol: r'$').format(amount);
  }
  return '$amount $c';
}

String _formatExpenseDate(DateTime date) {
  return DateFormat('dd/MM/yyyy').format(date);
}


enum _ExpenseDetailsMenuAction { edit, delete }
enum _ExpensePostMenuAction { edit, delete }

class _ExpenseTotalsHeader extends StatelessWidget {
  const _ExpenseTotalsHeader({
    required this.myTotalsByCurrency,
    required this.postTotalsByCurrency,
    this.myCostByCurrency,
  });

  final Map<String, double> myTotalsByCurrency;
  final Map<String, double> postTotalsByCurrency;
  final Map<String, double>? myCostByCurrency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
        );
    final valueStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        );

    Widget divider() => Container(
          width: 1,
          height: 36,
          color: cs.outlineVariant,
          margin: const EdgeInsets.symmetric(horizontal: 12),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.expensesMyTotalSpend, style: labelStyle),
                const SizedBox(height: 3),
                Text(
                  _formatTotalsByCurrency(myTotalsByCurrency),
                  style: valueStyle?.copyWith(color: cs.primary),
                ),
              ],
            ),
          ),
          if (myCostByCurrency != null) ...[
            divider(),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(l10n.expensesMyCost, style: labelStyle),
                  const SizedBox(height: 3),
                  Text(
                    _formatTotalsByCurrency(myCostByCurrency!),
                    textAlign: TextAlign.center,
                    style: valueStyle?.copyWith(color: cs.onSurface),
                  ),
                ],
              ),
            ),
          ],
          divider(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(l10n.expensesPostTotal, style: labelStyle),
                const SizedBox(height: 3),
                Text(
                  _formatTotalsByCurrency(postTotalsByCurrency),
                  textAlign: TextAlign.right,
                  style: valueStyle?.copyWith(color: cs.inverseSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only indicator shown to all members when expenses are UI-locked.
class _ExpensesLockedIndicator extends StatelessWidget {
  const _ExpensesLockedIndicator();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.lock_outline,
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

class _SettlementSection extends ConsumerStatefulWidget {
  const _SettlementSection({
    required this.tripId,
    required this.group,
    required this.groupExpenses,
    required this.memberLabels,
    required this.currentUserMemberId,
    required this.canMarkReimbursement,
    required this.expensesLocked,
    required this.isAdmin,
  });

  final String tripId;
  final TripExpenseGroup group;
  final List<TripExpense> groupExpenses;
  final Map<String, String> memberLabels;
  final String? currentUserMemberId;
  final bool canMarkReimbursement;
  final bool expensesLocked;
  final bool isAdmin;

  @override
  ConsumerState<_SettlementSection> createState() => _SettlementSectionState();
}

class _SettlementSectionState extends ConsumerState<_SettlementSection> {
  bool _showAllPost = false;
  String? _busySuggestionKey;
  bool _refreshing = false;

  ExpenseGroupScope get _scope => (
        tripId: widget.tripId,
        groupId: widget.group.id,
      );

  bool _involvesCurrentUser(SuggestedReimbursement suggestion) {
    final memberId = widget.currentUserMemberId?.trim();
    if (memberId == null || memberId.isEmpty) return false;
    return suggestion.fromParticipantId == memberId ||
        suggestion.toParticipantId == memberId;
  }

  bool _involvesCurrentUserSettlement(TripExpense expense) {
    final memberId = widget.currentUserMemberId?.trim();
    if (memberId == null || memberId.isEmpty) return false;
    final beneficiary = expense.participantIds.isNotEmpty
        ? expense.participantIds.first
        : '';
    return expense.paidBy == memberId || beneficiary == memberId;
  }

  Future<void> _markPaid(SuggestedReimbursement suggestion) async {
    if (!widget.canMarkReimbursement ||
        !widget.expensesLocked ||
        _busySuggestionKey != null) {
      return;
    }
    final key =
        '${suggestion.fromParticipantId}|${suggestion.toParticipantId}|${suggestion.currency}|${suggestion.amount}';
    setState(() => _busySuggestionKey = key);
    try {
      await ref.read(expensesRepositoryProvider).markExpenseReimbursementPaid(
            tripId: widget.tripId,
            groupId: widget.group.id,
            fromParticipantId: suggestion.fromParticipantId,
            toParticipantId: suggestion.toParticipantId,
            amount: suggestion.amount,
            currency: suggestion.currency,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!
                .expensesMarkReimbursementFailed(e.toString()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busySuggestionKey = null);
    }
  }

  Future<void> _unmarkPaid(TripExpense settlement) async {
    if (!widget.canMarkReimbursement ||
        !widget.expensesLocked ||
        _busySuggestionKey != null) {
      return;
    }
    setState(() => _busySuggestionKey = settlement.id);
    try {
      await ref.read(expensesRepositoryProvider).unmarkExpenseReimbursementPaid(
            tripId: widget.tripId,
            groupId: widget.group.id,
            expenseId: settlement.id,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!
                .expensesUnmarkReimbursementFailed(e.toString()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busySuggestionKey = null);
    }
  }

  Future<void> _setExpensesUiLocked(bool locked) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(expensesRepositoryProvider).setExpensesUiLocked(
            tripId: widget.tripId,
            locked: locked,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            locked ? l10n.expensesLockedSnackBar : l10n.expensesUnlockedSnackBar,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.commonErrorWithDetails(e.toString())),
        ),
      );
    }
  }

  Future<void> _setExpensesNotificationsEnabled(bool enabled) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(expensesRepositoryProvider).setExpensesNotificationsEnabled(
            tripId: widget.tripId,
            enabled: enabled,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? l10n.expensesNotificationsEnabledSnackBar
                : l10n.expensesNotificationsDisabledSnackBar,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.commonErrorWithDetails(e.toString())),
        ),
      );
    }
  }

  Future<void> _refreshSettlement() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(expensesRepositoryProvider).refreshExpenseGroupSettlement(
            tripId: widget.tripId,
            groupId: widget.group.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.expensesBalancesRefreshed),
        ),
      );
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
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _participantLabel(String participantId) {
    return widget.memberLabels[participantId] ??
        AppLocalizations.of(context)!.tripParticipantsTraveler;
  }

  ({String title, bool bold}) _reimbursementLabel(String fromId, String toId) {
    final l10n = AppLocalizations.of(context)!;
    final me = widget.currentUserMemberId?.trim();
    if (me != null && me.isNotEmpty) {
      if (fromId == me) {
        return (title: l10n.expensesReimbursementYouOweTo(_participantLabel(toId)), bold: true);
      }
      if (toId == me) {
        return (title: l10n.expensesReimbursementOwesYou(_participantLabel(fromId)), bold: true);
      }
    }
    return (
      title: l10n.expensesReimbursementFromTo(_participantLabel(fromId), _participantLabel(toId)),
      bold: false,
    );
  }

  Widget _buildFilterSegment(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? cs.secondaryContainer : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final pz = context.planerzColors;
    final balancesAsync =
        ref.watch(expenseGroupBalancesStreamProvider(_scope));
    final suggestionsAsync =
        ref.watch(expenseGroupSuggestedReimbursementsStreamProvider(_scope));
    final states =
        ref.watch(tripExpensesStatesStreamProvider(widget.tripId)).asData?.value ??
            TripExpensesStates.defaults;

    final balances = balancesAsync.asData?.value ?? const [];
    final allSuggestions = suggestionsAsync.asData?.value ?? const [];
    final visibleSuggestions = _showAllPost
        ? allSuggestions
        : allSuggestions.where(_involvesCurrentUser).toList();

    final allSettlements = widget.groupExpenses
        .where((e) => e.operationType == ExpenseOperationType.settlement)
        .toList();
    final visibleSettlements = _showAllPost
        ? allSettlements
        : allSettlements.where(_involvesCurrentUserSettlement).toList();

    final hasBalances = balances.any((b) => b.nets.isNotEmpty);
    final waitingForData = balancesAsync.isLoading || suggestionsAsync.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SectionHeader(
                icon: Icons.balance_outlined,
                label: l10n.expensesBalancesByCurrency,
                iconColor: cs.secondary,
              ),
            ),
            if (widget.isAdmin) ...[
              Tooltip(
                message: states.expensesLocked
                    ? l10n.expensesTooltipUnlockExpenses
                    : l10n.expensesTooltipLockExpenses,
                child: StatePillToggle(
                  offIcon: Icons.lock_open_outlined,
                  onIcon: Icons.lock_outline,
                  on: states.expensesLocked,
                  onChanged: _setExpensesUiLocked,
                ),
              ),
              Tooltip(
                message: states.expensesNotificationsEnabled
                    ? l10n.expensesTooltipDisableExpenseNotifications
                    : l10n.expensesTooltipEnableExpenseNotifications,
                child: StatePillToggle(
                  offIcon: Icons.notifications_off_outlined,
                  onIcon: Icons.notifications_active_outlined,
                  on: states.expensesNotificationsEnabled,
                  onChanged: _setExpensesNotificationsEnabled,
                ),
              ),
              IconButton(
                tooltip: l10n.expensesRefreshBalances,
                onPressed: _refreshing ? null : _refreshSettlement,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (waitingForData && !hasBalances)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.expensesNoCalculationYet,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          )
        else if (!hasBalances)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.expensesAddToSeeBreakdown,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          )
        else
          for (final balance in balances)
            if (balance.nets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        balance.currency,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                              letterSpacing: 1.1,
                            ),
                      ),
                      const SizedBox(height: 6),
                      for (final memberId in (widget.group.visibleToMemberIds.isNotEmpty
                          ? (widget.group.visibleToMemberIds.toList()..sort())
                          : (balance.nets.keys.toList()..sort())))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _participantLabel(memberId),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              _BalanceChip(
                                amount: balance.nets[memberId] ?? 0.0,
                                currency: balance.currency,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _SectionHeader(
                icon: Icons.sync_alt,
                label: l10n.expensesSuggestedReimbursements,
                iconColor: cs.primary,
              ),
            ),
            Container(
              height: 30,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildFilterSegment(context, l10n.commonAll, _showAllPost,
                      () => setState(() => _showAllPost = true)),
                  _buildFilterSegment(context, l10n.commonMe, !_showAllPost,
                      () => setState(() => _showAllPost = false)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.expensesSuggestedReimbursementsHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        if (visibleSuggestions.isEmpty)
          Text(
            waitingForData
                ? l10n.expensesNoCalculationYet
                : l10n.expensesAddToSeeBreakdown,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          )
        else
          ...visibleSuggestions.map((suggestion) {
            final lbl = _reimbursementLabel(
              suggestion.fromParticipantId,
              suggestion.toParticipantId,
            );
            return _ReimbursementRow(
              title: lbl.title,
              bold: lbl.bold,
              amountLabel: _formatMoney(suggestion.currency, suggestion.amount),
              actionIcon: Icons.check,
              actionTooltip: l10n.expensesMarkReimbursementPaid,
              actionColor: pz.success,
              showAction:
                  widget.canMarkReimbursement && widget.expensesLocked,
              busy: _busySuggestionKey ==
                  '${suggestion.fromParticipantId}|${suggestion.toParticipantId}|${suggestion.currency}|${suggestion.amount}',
              onAction: () => _markPaid(suggestion),
            );
          }),
        const SizedBox(height: 12),
        _SectionHeader(
          icon: Icons.check_circle_outline,
          label: l10n.expensesSettledReimbursements,
          iconColor: cs.tertiary,
        ),
        const SizedBox(height: 8),
        if (visibleSettlements.isEmpty)
          Text(
            l10n.expensesAddToSeeBreakdown,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          )
        else
          ...visibleSettlements.map((settlement) {
            final toId = settlement.participantIds.isNotEmpty
                ? settlement.participantIds.first
                : '';
            final lbl = _reimbursementLabel(settlement.paidBy, toId);
            return _ReimbursementRow(
              title: lbl.title,
              bold: lbl.bold,
              amountLabel: _formatMoney(settlement.currency, settlement.amount),
              actionIcon: Icons.close,
              actionTooltip: l10n.expensesUnmarkReimbursementPaid,
              actionColor: cs.error,
              showAction:
                  widget.canMarkReimbursement && widget.expensesLocked,
              busy: _busySuggestionKey == settlement.id,
              onAction: () => _unmarkPaid(settlement),
            );
          }),
      ],
    );
  }
}

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({required this.amount, required this.currency});

  final double amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final pz = context.planerzColors;

    const threshold = 0.5;
    final effectiveAmount = amount.abs() < threshold ? 0.0 : amount;
    final isCreditor = effectiveAmount > 0;
    final isDebtor = effectiveAmount < 0;

    final bg = isCreditor
        ? pz.successContainer
        : isDebtor
            ? cs.errorContainer
            : cs.surfaceContainerHighest;
    final fg = isCreditor
        ? pz.success
        : isDebtor
            ? cs.error
            : cs.onSurfaceVariant;
    final prefix = isCreditor
        ? l10n.expensesToReceive
        : isDebtor
            ? l10n.expensesToPay
            : l10n.expensesBalanced;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$prefix · ${_formatMoney(currency, effectiveAmount.abs())}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _ReimbursementRow extends StatelessWidget {
  const _ReimbursementRow({
    required this.title,
    required this.amountLabel,
    required this.actionIcon,
    required this.actionTooltip,
    required this.showAction,
    required this.busy,
    required this.onAction,
    this.actionColor,
    this.bold = false,
  });

  final String title;
  final String amountLabel;
  final IconData actionIcon;
  final String actionTooltip;
  final bool showAction;
  final bool busy;
  final VoidCallback onAction;
  final Color? actionColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: bold ? FontWeight.w700 : null,
                    ),
              ),
            ),
            Text(
              amountLabel,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (showAction) ...[
              const SizedBox(width: 8),
              busy
                  ? SizedBox(
                      width: 32,
                      height: 32,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: actionColor ?? cs.primary,
                        ),
                      ),
                    )
                  : Tooltip(
                      message: actionTooltip,
                      child: InkWell(
                        onTap: onAction,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: (actionColor ?? cs.primary)
                                  .withValues(alpha: 0.45),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x26000000),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Icon(actionIcon, size: 12, color: actionColor),
                        ),
                      ),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

/// Operations under each post: newest days first, with a date header per calendar day.
List<Widget> _buildExpensesGroupedByDate(
  BuildContext context,
  List<TripExpense> expenses,
  String tripId,
  List<String> participantScopeMemberIds,
  Map<String, String> memberLabels,
  {required bool canEditExpense, required bool canDeleteExpense}
) {
  if (expenses.isEmpty) return const [];

  final sorted = [...expenses]
    ..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));

  final byDay = <DateTime, List<TripExpense>>{};
  for (final e in sorted) {
    final day = DateTime(
      e.expenseDate.year,
      e.expenseDate.month,
      e.expenseDate.day,
    );
    byDay.putIfAbsent(day, () => []).add(e);
  }

  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  final cs = Theme.of(context).colorScheme;

  final widgets = <Widget>[];
  for (var i = 0; i < days.length; i++) {
    final day = days[i];
    final dayExpenses = byDay[day]!;

    widgets.add(
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 12, bottom: 6),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              DateFormat.yMMMEd(
                Localizations.localeOf(context).toString(),
              ).format(day),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.inverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );

    for (final e in dayExpenses) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _ExpenseCard(
            tripId: tripId,
            expense: e,
            participantScopeMemberIds: participantScopeMemberIds,
            memberLabels: memberLabels,
            canEditExpense: canEditExpense,
            canDeleteExpense: canDeleteExpense,
          ),
        ),
      );
    }
  }

  return widgets;
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.tripId,
    required this.expense,
    required this.participantScopeMemberIds,
    required this.memberLabels,
    required this.canEditExpense,
    required this.canDeleteExpense,
  });

  final String tripId;
  final TripExpense expense;
  final List<String> participantScopeMemberIds;
  final Map<String, String> memberLabels;
  final bool canEditExpense;
  final bool canDeleteExpense;

  Future<void> _openDetails(BuildContext context) async {
    if (expense.operationType == ExpenseOperationType.settlement) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ExpenseDetailsPage(
          tripId: tripId,
          expense: expense,
          participantScopeMemberIds: participantScopeMemberIds,
          memberLabels: memberLabels,
          canEditExpense: canEditExpense,
          canDeleteExpense: canDeleteExpense,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isSettlement = e.operationType == ExpenseOperationType.settlement;
    final accentColor = isSettlement ? cs.tertiary : cs.primary;
    final paidByLabel =
        memberLabels[e.paidBy] ?? l10n.tripParticipantsTraveler;
    final subtitle = isSettlement
        ? (e.participantIds.isNotEmpty
            ? l10n.expensesReimbursementFromTo(
                paidByLabel,
                memberLabels[e.participantIds.first] ??
                    l10n.tripParticipantsTraveler,
              )
            : l10n.expensesSettlementType)
        : l10n.expensesPaidByWithLabel(paidByLabel);
    final title = isSettlement
        ? l10n.expensesSettlementType
        : (e.title.isEmpty ? l10n.activitiesUntitled : e.title);

    return Card(
      margin: EdgeInsets.zero,
      color: isSettlement
          ? cs.tertiaryContainer.withValues(alpha: 0.35)
          : cs.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isSettlement ? null : () => _openDetails(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 52,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(12),
                  ),
                ),
              ),
              if (isSettlement) ...[
                const SizedBox(width: 8),
                Icon(Icons.swap_horiz, color: accentColor, size: 22),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSettlement
                        ? cs.tertiaryContainer
                        : cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatMoney(e.currency, e.amount),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: isSettlement
                              ? cs.onTertiaryContainer
                              : cs.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseDetailsPage extends ConsumerStatefulWidget {
  const _ExpenseDetailsPage({
    required this.tripId,
    required this.expense,
    required this.participantScopeMemberIds,
    required this.memberLabels,
    required this.canEditExpense,
    required this.canDeleteExpense,
  });

  final String tripId;
  final TripExpense expense;
  final List<String> participantScopeMemberIds;
  final Map<String, String> memberLabels;
  final bool canEditExpense;
  final bool canDeleteExpense;

  @override
  ConsumerState<_ExpenseDetailsPage> createState() =>
      _ExpenseDetailsPageState();
}

class _ExpenseDetailsPageState extends ConsumerState<_ExpenseDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late String _currency;
  late String? _paidBy;
  late Set<String> _participantIds;
  late DateTime _expenseDate;
  late ExpenseSplitMode _splitMode;
  final Map<String, TextEditingController> _shareControllers = {};
  bool _editing = false;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final scope = widget.participantScopeMemberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    _titleController = TextEditingController(text: widget.expense.title);
    _amountController = TextEditingController(
      text: widget.expense.amount.toStringAsFixed(2),
    );
    _currency = widget.expense.currency;
    final paid = widget.expense.paidBy.trim();
    _paidBy = scope.contains(paid) ? paid : null;
    _participantIds = widget.expense.participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && scope.contains(id))
        .toSet();
    if (_participantIds.isEmpty && scope.isNotEmpty) {
      _participantIds = {...scope};
    }
    if (_paidBy == null && scope.isNotEmpty) {
      _paidBy = scope.first;
    }
    _expenseDate = DateTime(
      widget.expense.expenseDate.year,
      widget.expense.expenseDate.month,
      widget.expense.expenseDate.day,
    );
    _splitMode = widget.expense.splitMode;
    if (_splitMode == ExpenseSplitMode.customAmounts) {
      final n = _participantIds.length;
      final each = n > 0 ? widget.expense.amount / n : 0.0;
      for (final id in _participantIds) {
        final v = widget.expense.participantShares[id] ?? each;
        _shareControllers[id] = TextEditingController(
          text: v.toStringAsFixed(2),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _shareControllers.values) {
      c.dispose();
    }
    _shareControllers.clear();
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  double _parsedTotalAmount() {
    return double.tryParse(
          _amountController.text.trim().replaceAll(',', '.'),
        ) ??
        widget.expense.amount;
  }

  String _formatShareMoney(double value) {
    final symbol = _currency == 'USD' ? r'$' : '€';
    return NumberFormat.currency(
      locale: Localizations.localeOf(context).toString(),
      symbol: symbol,
      decimalDigits: 2,
    ).format(value);
  }

  void _onSplitModeChanged(ExpenseSplitMode mode) {
    setState(() {
      _splitMode = mode;
      if (mode == ExpenseSplitMode.equal) {
        for (final c in _shareControllers.values) {
          c.dispose();
        }
        _shareControllers.clear();
      } else {
        final total = _parsedTotalAmount();
        final ids = _participantIds.toList();
        final n = ids.length;
        final each = n > 0 ? total / n : 0.0;
        final idSet = ids.toSet();
        for (final id in ids) {
          if (!_shareControllers.containsKey(id)) {
            _shareControllers[id] = TextEditingController(
              text: each.toStringAsFixed(2),
            );
          }
        }
        final toRemove =
            _shareControllers.keys.where((k) => !idSet.contains(k)).toList();
        for (final k in toRemove) {
          _shareControllers.remove(k)?.dispose();
        }
      }
    });
  }

  Map<String, double>? _parseCustomSharesForSave() {
    final ids = _participantIds.toList();
    if (ids.isEmpty) return null;
    final out = <String, double>{};
    for (final id in ids) {
      final c = _shareControllers[id];
      final t = (c?.text ?? '').trim().replaceAll(',', '.');
      final n = double.tryParse(t);
      if (n == null || n < 0) return null;
      out[id] = n;
    }
    final sum = out.values.fold<double>(0, (a, b) => a + b);
    final total = _parsedTotalAmount();
    if ((sum - total).abs() > 0.02) return null;
    return out;
  }

  Widget? _shareAmountTrailing(String memberId) {
    if (!_participantIds.contains(memberId)) {
      return Text(
        AppLocalizations.of(context)!.commonDash,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    if (_splitMode == ExpenseSplitMode.equal) {
      final n = _participantIds.length;
      final per = n > 0 ? _parsedTotalAmount() / n : 0.0;
      return Text(
        _formatShareMoney(per),
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    if (_editing) {
      final c = _shareControllers[memberId];
      if (c == null) {
        return const SizedBox(width: 88);
      }
      return SizedBox(
        width: 100,
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          textAlign: TextAlign.end,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            border: OutlineInputBorder(),
          ),
        ),
      );
    }
    final c = _shareControllers[memberId];
    final parsed = c != null
        ? double.tryParse(c.text.trim().replaceAll(',', '.'))
        : null;
    final v = parsed ?? widget.expense.participantShares[memberId] ?? 0.0;
    return Text(
      _formatShareMoney(v),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  Future<void> _pickExpenseDate() async {
    final picked = await showDatePicker(
      context: context,
      locale: Localizations.localeOf(context),
      initialDate: _expenseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _expenseDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _confirmDelete() async {
    if (_deleting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.expensesDeleteExpenseTitle),
        content: Text(
          AppLocalizations.of(context)!.expensesDeleteExpenseBody(
            widget.expense.title.trim().isEmpty
                ? AppLocalizations.of(context)!.activitiesUntitled
                : widget.expense.title,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(expensesRepositoryProvider).deleteExpense(
            tripId: widget.tripId,
            expenseId: widget.expense.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.expensesExpenseDeleted),
        ),
      );
      Navigator.of(context).pop();
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
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final paidBy = _paidBy;
    if (paidBy == null || paidBy.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesChoosePayer)),
      );
      return;
    }
    final scopeSet = widget.participantScopeMemberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (scopeSet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesNoAllowedTraveler)),
      );
      return;
    }
    if (!scopeSet.contains(paidBy.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesInvalidPayerForPost)),
      );
      return;
    }
    if (_participantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesSelectAtLeastOneParticipant)),
      );
      return;
    }
    if (_participantIds.any((id) => !scopeSet.contains(id))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesParticipantOutOfScope)),
      );
      return;
    }

    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesInvalidAmount)),
      );
      return;
    }

    Map<String, double>? customShares;
    if (_splitMode == ExpenseSplitMode.customAmounts) {
      customShares = _parseCustomSharesForSave();
      if (customShares == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.expensesCustomAmountValidation,
            ),
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await ref.read(expensesRepositoryProvider).updateExpense(
            tripId: widget.tripId,
            expenseId: widget.expense.id,
            title: _titleController.text,
            amount: amount,
            currency: _currency,
            paidBy: paidBy,
            participantIds: _participantIds.toList(),
            expenseDate: _expenseDate,
            splitMode: _splitMode,
            participantShares: customShares,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesExpenseUpdated)),
      );
      setState(() => _editing = false);
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
    final l10n = AppLocalizations.of(context)!;
    final canShowActions = widget.canEditExpense || widget.canDeleteExpense;
    final members = widget.participantScopeMemberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.expensesExpenseDetailTitle),
        actions: [
          if (canShowActions)
            PopupMenuButton<_ExpenseDetailsMenuAction>(
              enabled: !_saving && !_deleting,
              onSelected: (action) async {
                if (action == _ExpenseDetailsMenuAction.edit) {
                  if (!widget.canEditExpense) return;
                  setState(() => _editing = true);
                  return;
                }
                if (!widget.canDeleteExpense) return;
                await _confirmDelete();
              },
              itemBuilder: (context) => [
                if (widget.canEditExpense)
                  PopupMenuItem<_ExpenseDetailsMenuAction>(
                    value: _ExpenseDetailsMenuAction.edit,
                    child: Text(l10n.commonEdit),
                  ),
                if (widget.canDeleteExpense)
                  PopupMenuItem<_ExpenseDetailsMenuAction>(
                    value: _ExpenseDetailsMenuAction.delete,
                    child: Text(l10n.commonDelete),
                  ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Summary banner
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primaryContainer, cs.secondaryContainer],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.expense.title.isEmpty
                            ? l10n.activitiesUntitled
                            : widget.expense.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatMoney(
                        widget.expense.currency,
                        widget.expense.amount,
                      ),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
              if (members.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    l10n.expensesNoAllowedTravelerInPostHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.error,
                        ),
                  ),
                ),
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                readOnly: !_editing,
                decoration: InputDecoration(
                  labelText: l10n.activitiesLabel,
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.commonRequired : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      readOnly: !_editing,
                      onChanged: !_editing
                          ? null
                          : (_) => setState(() {}),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.expensesAmountLabel,
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim().replaceAll(',', '.');
                        final n = double.tryParse(t);
                        if (n == null || n <= 0) return l10n.expensesInvalidAmount;
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey<String>(_currency),
                      initialValue: _currency,
                      decoration: InputDecoration(
                        labelText: l10n.expensesCurrencyLabel,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'EUR',
                          child: Text(l10n.expensesCurrencyEuro),
                        ),
                        DropdownMenuItem(
                          value: 'USD',
                          child: Text(l10n.expensesCurrencyDollar),
                        ),
                      ],
                      onChanged: !_editing
                          ? null
                          : (v) {
                              if (v != null) setState(() => _currency = v);
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey<String>(_paidBy ?? ''),
                      isExpanded: true,
                      initialValue: _paidBy != null && members.contains(_paidBy)
                          ? _paidBy
                          : null,
                      decoration: InputDecoration(
                        labelText: l10n.expensesPaidByLabel,
                        border: OutlineInputBorder(),
                      ),
                      selectedItemBuilder: (context) => [
                        for (final id in members)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.memberLabels[id] ?? id,
                              maxLines: 2,
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      items: [
                        for (final id in members)
                          DropdownMenuItem(
                            value: id,
                            child: Text(
                              widget.memberLabels[id] ?? id,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged:
                          _editing ? (v) => setState(() => _paidBy = v) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _editing ? _pickExpenseDate : null,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: l10n.expensesDateLabel,
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(_formatExpenseDate(_expenseDate)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      l10n.expensesAmountSplit,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (_editing)
                    DropdownButton<ExpenseSplitMode>(
                      value: _splitMode,
                      underline: const SizedBox.shrink(),
                      alignment: AlignmentDirectional.centerEnd,
                      items: [
                        DropdownMenuItem(
                          value: ExpenseSplitMode.equal,
                          child: Text(l10n.expensesSplitEqual),
                        ),
                        DropdownMenuItem(
                          value: ExpenseSplitMode.customAmounts,
                          child: Text(l10n.expensesSplitCustomAmounts),
                        ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) _onSplitModeChanged(mode);
                      },
                    )
                  else
                    Text(
                      _splitMode == ExpenseSplitMode.equal
                          ? l10n.expensesSplitEqual
                          : l10n.expensesSplitCustomAmounts,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: cs.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (final id in members)
                      CheckboxListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          widget.memberLabels[id] ?? id,
                          overflow: TextOverflow.ellipsis,
                        ),
                        secondary: _shareAmountTrailing(id),
                        value: _participantIds.contains(id),
                        onChanged: !_editing
                            ? null
                            : (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _participantIds.add(id);
                                    if (_splitMode ==
                                        ExpenseSplitMode.customAmounts) {
                                      final total = _parsedTotalAmount();
                                      final n = _participantIds.length;
                                      final each =
                                          n > 0 ? total / n : 0.0;
                                      _shareControllers[id] =
                                          TextEditingController(
                                        text: each.toStringAsFixed(2),
                                      );
                                    }
                                  } else {
                                    _participantIds.remove(id);
                                    if (_splitMode ==
                                        ExpenseSplitMode.customAmounts) {
                                      _shareControllers
                                          .remove(id)
                                          ?.dispose();
                                    }
                                  }
                                });
                              },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_editing)
                FilledButton(
                  onPressed:
                      (_saving || members.isEmpty) ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.expensesSaveChanges),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddExpensePage extends ConsumerStatefulWidget {
  const _AddExpensePage({
    required this.tripId,
    required this.groupId,
    required this.participantScopeMemberIds,
    required this.memberLabels,
    required this.currentUserMemberId,
  });

  final String tripId;
  final String groupId;
  final List<String> participantScopeMemberIds;
  final Map<String, String> memberLabels;
  final String? currentUserMemberId;

  @override
  ConsumerState<_AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends ConsumerState<_AddExpensePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  String _currency = 'EUR';
  String? _paidBy;
  final Set<String> _participantIds = {};
  DateTime _expenseDate = DateTime.now();
  bool _saving = false;

  List<String> get _scopeMemberIds => widget.participantScopeMemberIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    final myParticipantId = widget.currentUserMemberId;
    final members = _scopeMemberIds;
    _paidBy = (myParticipantId != null && members.contains(myParticipantId))
        ? myParticipantId
        : (members.isNotEmpty ? members.first : null);
    _participantIds.addAll(members);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickExpenseDate() async {
    final picked = await showDatePicker(
      context: context,
      locale: Localizations.localeOf(context),
      initialDate: _expenseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _expenseDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final paidBy = _paidBy;
    if (paidBy == null || paidBy.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesChoosePayer)),
      );
      return;
    }

    if (_participantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesSelectAtLeastOneParticipant)),
      );
      return;
    }

    final amountText = _amountController.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesInvalidAmount)),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(expensesRepositoryProvider).addExpense(
            tripId: widget.tripId,
            groupId: widget.groupId,
            title: _titleController.text,
            amount: amount,
            currency: _currency,
            paidBy: paidBy,
            participantIds: _participantIds.toList(),
            expenseDate: _expenseDate,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.expensesExpenseSaved)),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.commonErrorWithDetails(e.toString()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final members = _scopeMemberIds;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.expensesNewExpenseTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            if (members.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.expensesNoAllowedTravelerInPostForShare,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.error,
                    ),
              ),
            ],
            if (members.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.activitiesLabel,
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return l10n.commonRequired;
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.expensesAmountLabel,
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim().replaceAll(',', '.');
                        final n = double.tryParse(t);
                        if (n == null || n <= 0) return l10n.expensesInvalidAmount;
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey<String>(_currency),
                      initialValue: _currency,
                      decoration: InputDecoration(
                        labelText: l10n.expensesCurrencyLabel,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'EUR',
                          child: Text(l10n.expensesCurrencyEuro),
                        ),
                        DropdownMenuItem(
                          value: 'USD',
                          child: Text(l10n.expensesCurrencyDollar),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _currency = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey<String>(_paidBy ?? ''),
                          initialValue:
                              _paidBy != null && members.contains(_paidBy)
                                  ? _paidBy
                                  : null,
                          decoration: InputDecoration(
                            labelText: l10n.expensesPaidByLabel,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final id in members)
                              DropdownMenuItem(
                                value: id,
                                child: Text(
                                  widget.memberLabels[id] ??
                                      l10n.tripParticipantsTraveler,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _paidBy = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _pickExpenseDate,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: l10n.expensesDateLabel,
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_today_outlined),
                            ),
                            child: Text(_formatExpenseDate(_expenseDate)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.expensesAmountSplit,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        for (final id in members)
                          CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              widget.memberLabels[id] ??
                                  l10n.tripParticipantsTraveler,
                              overflow: TextOverflow.ellipsis,
                            ),
                            value: _participantIds.contains(id),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _participantIds.add(id);
                                } else {
                                  _participantIds.remove(id);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            FilledButton(
              onPressed: _saving || members.isEmpty ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.commonSave),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
