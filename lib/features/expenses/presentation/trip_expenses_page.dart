import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/expenses/data/expense.dart';
import 'package:planerz/features/expenses/data/expense_group.dart';
import 'package:planerz/features/expenses/data/expenses_repository.dart';
import 'package:planerz/features/expenses/data/expense_group_state.dart';
import 'package:planerz/features/expenses/data/expenses_states.dart';
import 'package:planerz/features/expenses/data/suggested_reimbursement.dart';
import 'package:planerz/features/expenses/data/expense_icon_catalog.dart';
import 'package:planerz/features/expenses/presentation/expense_editor_pages.dart';
import 'package:planerz/features/expenses/presentation/expense_format.dart';
import 'package:planerz/features/trips/data/participant_group.dart';
import 'package:planerz/features/trips/data/participant_groups_repository.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_member.dart';
import 'package:planerz/features/expenses/presentation/expense_group_editor_page.dart';
import 'package:planerz/core/presentation/state_pill_toggle.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Billing unit IDs (ungrouped member IDs + applicable group IDs) for an expense post.
///
/// Ungrouped members: allowed by [group.visibleToMemberIds] and not in any group.
/// Groups: those whose every member is within the allowed set.
List<String> participantScopeUnitIdsForGroup(
  TripExpenseGroup group,
  List<TripMember> participants,
  List<ParticipantGroup> participantGroups,
) {
  if (group.visibleToMemberIds.isEmpty) return [];
  final allowed = group.visibleToMemberIds.toSet();
  final groupedMemberIds = participantGroups.expand((g) => g.memberIds).toSet();
  final ungrouped = participants
      .where((m) =>
          !m.isChild &&
          allowed.contains(m.id) &&
          !groupedMemberIds.contains(m.id))
      .map((m) => m.id)
      .toList();
  final scopeGroups = participantGroups
      .where((g) => g.memberIds.isNotEmpty && g.memberIds.every(allowed.contains))
      .map((g) => g.id)
      .toList();
  return [...ungrouped, ...scopeGroups]..sort();
}


class TripExpensesPage extends ConsumerStatefulWidget {
  const TripExpensesPage({super.key});

  @override
  ConsumerState<TripExpensesPage> createState() => _TripExpensesPageState();
}

class _TripExpensesPageState extends ConsumerState<TripExpensesPage> {
  String? _activeGroupId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trip = TripScope.of(context);
    final groupsAsync = ref.watch(tripExpenseGroupsStreamProvider(trip.id));
    final expensesAsync = ref.watch(tripExpensesStreamProvider(trip.id));
    final participants =
        ref.watch(tripParticipantsStreamProvider(trip.id)).asData?.value ?? [];
    final unitLabels = ref.watch(tripExpenseUnitLabelsProvider(trip.id));
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
    final isAdminOrAbove = isTripRoleAllowed(
      currentRole: resolveTripPermissionRole(trip: trip, userId: viewerId),
      minRole: TripPermissionRole.admin,
    );
    final groupsForFab = groupsAsync.asData?.value;
    final visibleGroupsForFab = groupsForFab == null
        ? const <TripExpenseGroup>[]
        : groupsForFab
            .where((group) => group.isVisibleTo(currentUserMemberId))
            .toList();
    final resolvedActiveGroupId = () {
      final preferred = _activeGroupId?.trim();
      if (preferred != null && preferred.isNotEmpty) return preferred;
      if (visibleGroupsForFab.length == 1) return visibleGroupsForFab.single.id;
      return null;
    }();
    final activeGroupLocked = resolvedActiveGroupId != null
        ? (ref
                    .watch(
                      expenseGroupStateStreamProvider((
                        tripId: trip.id,
                        groupId: resolvedActiveGroupId,
                      )),
                    )
                    .asData
                    ?.value ??
                TripExpenseGroupState.defaults)
            .expensesLocked
        : false;
    final showExpensesFab =
        canCreateExpensePost || (canCreateExpense && !activeGroupLocked);

    return Scaffold(
      body: groupsAsync.when(
        data: (groups) => expensesAsync.when(
          data: (expenses) {
            return _TripExpensesBody(
              trip: trip,
              participants: participants,
              memberLabels: unitLabels,
              memberIds: memberIds,
              currentUserMemberId: currentUserMemberId,
              groups: groups,
              expenses: expenses,
              activeGroupId: _activeGroupId,
              isAdminOrAbove: isAdminOrAbove,
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
      floatingActionButton: showExpensesFab && canCreateExpense && !activeGroupLocked
          ? FloatingActionButton(
              heroTag: 'trip_expenses_add',
              backgroundColor: NeonPalette.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              tooltip: l10n.expensesAddExpenseTooltip,
              onPressed: () => _openAddExpensePageFromFab(
                context,
                ref,
                trip.id,
                participants,
                unitLabels,
                _activeGroupId,
              ),
              child: const Icon(Icons.add, size: 28),
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
    final participantGroupsList =
        ref.read(tripParticipantGroupsStreamProvider(tripId)).asData?.value ?? [];
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => AddExpensePage(
          tripId: tripId,
          groupId: group.id,
          participantScopeMemberIds:
              participantScopeUnitIdsForGroup(group, participants, participantGroupsList),
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
    required this.isAdminOrAbove,
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
  final bool isAdminOrAbove;
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
    if (visibleGroups.isEmpty) {
      return SingleChildScrollView(
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
      );
    }

    final activeId = activeGroupId != null &&
            visibleGroups.any((g) => g.id == activeGroupId)
        ? activeGroupId!
        : visibleGroups.first.id;
    final activeGroup =
        visibleGroups.firstWhere((g) => g.id == activeId);
    final canCreatePost = canCreateExpensePostForTrip(
      trip: trip,
      userId: viewerId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExpensePostTabs(
          groups: visibleGroups,
          activeGroupId: activeId,
          canCreatePost: canCreatePost,
          onGroupSelected: onActiveGroupChanged,
          onAddPost: () => _TripExpensesPageState._openExpenseGroupEditor(
            context,
            trip.id,
            memberIds,
            memberLabels,
            currentUserMemberId,
            existing: null,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            child: _ExpensePostPanel(
              trip: trip,
              group: activeGroup,
              groupExpenses:
                  expenses.where((e) => e.groupId == activeGroup.id).toList(),
              participants: participants,
              memberIds: memberIds,
              memberLabels: memberLabels,
              currentUserMemberId: currentUserMemberId,
              viewerUserId: viewerId,
              isAdminOrAbove: isAdminOrAbove,
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpensePostTabs extends StatelessWidget {
  const _ExpensePostTabs({
    required this.groups,
    required this.activeGroupId,
    required this.canCreatePost,
    required this.onGroupSelected,
    required this.onAddPost,
  });

  final List<TripExpenseGroup> groups;
  final String activeGroupId;
  final bool canCreatePost;
  final ValueChanged<String> onGroupSelected;
  final VoidCallback onAddPost;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _PostTab(
                label: group.title.isEmpty
                    ? l10n.activitiesUntitled
                    : group.title,
                iconKey: group.icon,
                isDefault: group.isDefault,
                selected: group.id == activeGroupId,
                onTap: () => onGroupSelected(group.id),
              ),
            ),
          if (canCreatePost)
            _PostTab(
              label: l10n.expensesFabAddPost,
              iconKey: 'add',
              dashed: true,
              selected: false,
              onTap: onAddPost,
            ),
        ],
      ),
    );
  }
}

class _PostTab extends StatelessWidget {
  const _PostTab({
    required this.label,
    required this.iconKey,
    required this.selected,
    required this.onTap,
    this.isDefault = false,
    this.dashed = false,
  });

  final String label;
  final String iconKey;
  final bool selected;
  final bool isDefault;
  final bool dashed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = iconKey == 'add'
        ? Icons.add
        : expenseIconForPost(iconKey, isDefault: isDefault);
    final borderColor = dashed
        ? NeonPalette.divider
        : selected
            ? Color.lerp(NeonPalette.divider, NeonPalette.accent, 0.45)!
            : NeonPalette.divider;
    final backgroundColor = selected
        ? Color.lerp(NeonPalette.surface, NeonPalette.accent, 0.09)!
        : NeonPalette.surface;
    final labelColor = dashed
        ? NeonPalette.onSurfaceVariant
        : selected
            ? NeonPalette.accent
            : NeonPalette.text700;
    final iconBoxColor = selected
        ? NeonPalette.accent
        : Color.lerp(NeonPalette.surface, NeonPalette.accent, 0.14)!;
    final iconColor = selected ? Colors.white : NeonPalette.accent;

    final content = Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 38,
          child: Padding(
            padding: EdgeInsets.fromLTRB(dashed ? 14 : 10, 0, 14, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dashed)
                  Icon(icon, size: 16, color: NeonPalette.onSurfaceVariant)
                else
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: iconBoxColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 15, color: iconColor),
                  ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: labelColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (dashed) {
      return CustomPaint(
        painter: _DashedPillBorderPainter(color: borderColor),
        child: content,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: content,
    );
  }
}

class _DashedPillBorderPainter extends CustomPainter {
  const _DashedPillBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
      const Radius.circular(999),
    );
    final path = Path()..addRRect(rect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + 5;
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 4;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPillBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// Removed _ExpensePostsTabbedView — post tabs are inline above.

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
    required this.isAdminOrAbove,
  });

  final Trip trip;
  final TripExpenseGroup group;
  final List<TripExpense> groupExpenses;
  final List<TripMember> participants;
  final List<String> memberIds;
  final Map<String, String> memberLabels;
  final String? currentUserMemberId;
  final String? viewerUserId;
  final bool isAdminOrAbove;

  @override
  ConsumerState<_ExpensePostPanel> createState() => _ExpensePostPanelState();
}

class _ExpensePostPanelState extends ConsumerState<_ExpensePostPanel> {
  bool _deletingPost = false;
  _ExpensePostView _activeView = _ExpensePostView.operations;
  bool _showAllOperations = true;
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

  Future<void> _setExpensesUiLocked(bool locked) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(expensesRepositoryProvider).setExpensesUiLocked(
            tripId: widget.trip.id,
            groupId: widget.group.id,
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
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _markExpensesNotificationsReadIfNeeded(widget.trip.id);
    _syncExpensesPresenceIfNeeded(widget.trip.id);
    final viewerUserId = widget.viewerUserId?.trim();
    final viewerBillingUnitId =
        ref.watch(viewerBillingUnitIdProvider(widget.trip.id))?.trim();
    final participantGroups =
        ref.watch(tripParticipantGroupsStreamProvider(widget.trip.id)).asData?.value ?? [];
    final groupScope = (
      tripId: widget.trip.id,
      groupId: widget.group.id,
    );
    final groupState = ref.watch(expenseGroupStateStreamProvider(groupScope)).asData?.value ??
        TripExpenseGroupState.defaults;
    final lockRestrictsEditing = groupState.expensesLocked;
    final expensesLocked = groupState.expensesLocked;
    final summary =
        ref.watch(expenseGroupSummaryStreamProvider(groupScope)).asData?.value;
    final postTotalsByCurrency = summary?.postTotalsByCurrency ?? const {};
    final myTotalsByCurrency = viewerBillingUnitId != null
        ? summary?.paidByTotalsByCurrency[viewerBillingUnitId] ?? const {}
        : const <String, double>{};
    final Map<String, double>? myCostByCurrency = viewerBillingUnitId != null
        ? () {
            final groupParts = {for (final g in participantGroups) g.id: g.parts};
            final result = <String, double>{};
            for (final expense in widget.groupExpenses) {
              if (expense.operationType == ExpenseOperationType.settlement) {
                continue;
              }
              if (!expense.participantIds.contains(viewerBillingUnitId)) continue;
              final double share;
              if (expense.splitMode == ExpenseSplitMode.customAmounts) {
                share = expense.participantShares[viewerBillingUnitId] ?? 0.0;
              } else {
                final totalParts = expense.participantIds
                    .fold<double>(0, (s, id) => s + (groupParts[id] ?? 1.0));
                final myParts = groupParts[viewerBillingUnitId] ?? 1.0;
                share = totalParts > 0
                    ? expense.amount * myParts / totalParts
                    : 0.0;
              }
              result[expense.currency] =
                  (result[expense.currency] ?? 0.0) + share;
            }
            return result;
          }()
        : null;
    final canMarkReimbursement =
        widget.group.isVisibleTo(widget.currentUserMemberId);
    final scope = participantScopeUnitIdsForGroup(
      widget.group,
      widget.participants,
      participantGroups,
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
    final effectiveCanEditPost = canEditPost;
    final effectiveCanDeletePost = canDeletePost;
    final effectiveCanEditExpense = canEditExpense && !lockRestrictsEditing;
    final effectiveCanDeleteExpense = canDeleteExpense && !lockRestrictsEditing;
    final canLockPost = widget.isAdminOrAbove;
    final showPostMenu = canLockPost ||
        effectiveCanEditPost ||
        effectiveCanDeletePost;
    final visibleOperations = _showAllOperations
        ? widget.groupExpenses
        : widget.groupExpenses
            .where(
              (expense) =>
                  viewerBillingUnitId != null &&
                  expense.involvesMember(viewerBillingUnitId),
            )
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ExpenseViewSegmented(
                activeView: _activeView,
                onChanged: (next) {
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
                  if (action == _ExpensePostMenuAction.lock) {
                    await _setExpensesUiLocked(!expensesLocked);
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
                  if (canLockPost) {
                    items.add(
                      PopupMenuItem<_ExpensePostMenuAction>(
                        value: _ExpensePostMenuAction.lock,
                        child: Row(
                          children: [
                            Icon(
                              expensesLocked
                                  ? Icons.lock_open_outlined
                                  : Icons.lock_outline,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              expensesLocked
                                  ? l10n.expensesUnlockPostMenu
                                  : l10n.expensesLockPostMenu,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (effectiveCanDeletePost && !widget.group.isDefault) {
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
            expensesLocked: expensesLocked,
            isAdmin: widget.isAdminOrAbove,
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ExpenseHeroCard(
                postTotalsByCurrency: postTotalsByCurrency,
                myTotalsByCurrency: myTotalsByCurrency,
                myCostByCurrency: myCostByCurrency,
              ),
              if (widget.groupExpenses.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.expensesOperationsFilterHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NeonPalette.onSurfaceVariant,
                              height: 1.35,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildTousMoiSegmentedFilter(
                      context,
                      showAll: _showAllOperations,
                      onShowAllChanged: (showAll) {
                        setState(() => _showAllOperations = showAll);
                      },
                    ),
                  ],
                ),
              ],
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
              else if (visibleOperations.isEmpty)
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
                        l10n.expensesNoMyOperationInPost,
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
                  visibleOperations,
                  widget.trip.id,
                  scope,
                  widget.memberLabels,
                  viewerBillingUnitId: viewerBillingUnitId,
                  groupParts: {for (final g in participantGroups) g.id: g.parts},
                  currentUserMemberId: widget.currentUserMemberId,
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

Widget _buildTousMoiFilterSegment(
  BuildContext context,
  String label,
  bool selected,
  VoidCallback onTap,
) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? NeonPalette.accentSoft : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? NeonPalette.accent : NeonPalette.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
      ),
    ),
  );
}

Widget _buildTousMoiSegmentedFilter(
  BuildContext context, {
  required bool showAll,
  required ValueChanged<bool> onShowAllChanged,
}) {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  return Container(
    height: 30,
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTousMoiFilterSegment(
          context,
          l10n.commonAll,
          showAll,
          () => onShowAllChanged(true),
        ),
        _buildTousMoiFilterSegment(
          context,
          l10n.commonMe,
          !showAll,
          () => onShowAllChanged(false),
        ),
      ],
    ),
  );
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

enum _ExpensePostMenuAction { edit, lock, delete }

class _ExpenseViewSegmented extends StatelessWidget {
  const _ExpenseViewSegmented({
    required this.activeView,
    required this.onChanged,
  });

  final _ExpensePostView activeView;
  final ValueChanged<_ExpensePostView> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget segment({
      required _ExpensePostView value,
      required IconData icon,
      required String label,
    }) {
      final on = activeView == value;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(value),
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              height: 40,
              decoration: BoxDecoration(
                color: on ? NeonPalette.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: on
                    ? [
                        BoxShadow(
                          color: NeonPalette.accent.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: on ? Colors.white : NeonPalette.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: on ? Colors.white : NeonPalette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NeonPalette.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: NeonPalette.divider, width: 1.5),
      ),
      child: Row(
        children: [
          segment(
            value: _ExpensePostView.operations,
            icon: Icons.receipt_long_outlined,
            label: l10n.tripSectionExpenses,
          ),
          segment(
            value: _ExpensePostView.settlement,
            icon: Icons.balance_outlined,
            label: l10n.expensesBalancesTab,
          ),
        ],
      ),
    );
  }
}

class _ExpenseHeroCard extends StatelessWidget {
  const _ExpenseHeroCard({
    required this.postTotalsByCurrency,
    required this.myTotalsByCurrency,
    this.myCostByCurrency,
  });

  final Map<String, double> postTotalsByCurrency;
  final Map<String, double> myTotalsByCurrency;
  final Map<String, double>? myCostByCurrency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final primary = resolvePrimaryExpenseCurrency(postTotalsByCurrency);
    final postTotal = postTotalsByCurrency[primary] ?? 0.0;
    final mySpend = myTotalsByCurrency[primary] ?? 0.0;
    final myCost = myCostByCurrency?[primary] ?? 0.0;
    final net = mySpend - myCost;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            NeonPalette.accent,
            Color.lerp(NeonPalette.accent, NeonPalette.primary, 0.55)!,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.expensesPostTotal,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            formatExpenseMoney(primary, postTotal, locale: locale),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.expensesMyCost,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      formatExpenseMoney(primary, myCost, locale: locale),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      l10n.expensesMyTotalSpend,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      formatExpenseMoney(primary, mySpend, locale: locale),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (myCostByCurrency != null && net.abs() >= 0.5) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    net > 0 ? Icons.trending_up : Icons.trending_down,
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    net > 0
                        ? l10n.expensesNetOwedToYou(
                            formatExpenseMoney(primary, net.abs(), locale: locale),
                          )
                        : l10n.expensesNetYouOwe(
                            formatExpenseMoney(primary, net.abs(), locale: locale),
                          ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
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

  bool _isViewerUnit(String participantId, String? viewerBillingUnitId) {
    final me = viewerBillingUnitId?.trim();
    return me != null && me.isNotEmpty && participantId == me;
  }

  String _formatSignedBalance(String currency, double amount) {
    const threshold = 0.5;
    final effectiveAmount = amount.abs() < threshold ? 0.0 : amount;
    if (effectiveAmount > 0) {
      return '+${_formatMoney(currency, effectiveAmount)}';
    }
    return _formatMoney(currency, effectiveAmount);
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
    final tripStates =
        ref.watch(tripExpensesStatesStreamProvider(widget.tripId)).asData?.value ??
            TripExpensesStates.defaults;

    final viewerBillingUnitId =
        ref.watch(viewerBillingUnitIdProvider(widget.tripId))?.trim();

    final balances = balancesAsync.asData?.value ?? const [];
    final allSuggestions = suggestionsAsync.asData?.value ?? const [];
    final visibleSuggestions = _showAllPost
        ? allSuggestions
        : allSuggestions.where((s) {
            if (viewerBillingUnitId == null || viewerBillingUnitId.isEmpty) {
              return false;
            }
            return s.fromParticipantId == viewerBillingUnitId ||
                s.toParticipantId == viewerBillingUnitId;
          }).toList();

    final allSettlements = widget.groupExpenses
        .where((e) => e.operationType == ExpenseOperationType.settlement)
        .toList();
    final visibleSettlements = _showAllPost
        ? allSettlements
        : allSettlements.where((e) {
            if (viewerBillingUnitId == null || viewerBillingUnitId.isEmpty) {
              return false;
            }
            return e.involvesMember(viewerBillingUnitId);
          }).toList();

    final hasNonSettlementExpenses = widget.groupExpenses
        .any((e) => e.operationType != ExpenseOperationType.settlement);
    final hasBalances = hasNonSettlementExpenses || balances.any((b) => b.nets.isNotEmpty);
    final waitingForData = balancesAsync.isLoading || suggestionsAsync.isLoading;
    final canMark = widget.canMarkReimbursement && widget.expensesLocked;
    final sectionLabelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.3,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.expensesLocked)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: pz.warningContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: pz.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_open_outlined,
                  size: 18,
                  color: pz.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.expensesLockPostBar,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: NeonPalette.deep,
                          height: 1.4,
                          fontSize: 12,
                        ),
                  ),
                ),
              ],
            ),
          ),
        if (widget.isAdmin)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Tooltip(
                  message: tripStates.expensesNotificationsEnabled
                      ? l10n.expensesTooltipDisableExpenseNotifications
                      : l10n.expensesTooltipEnableExpenseNotifications,
                  child: StatePillToggle(
                    offIcon: Icons.notifications_off_outlined,
                    onIcon: Icons.notifications_active_outlined,
                    on: tripStates.expensesNotificationsEnabled,
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
            ),
          ),
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
            _SettlementBalanceCard(
              title: l10n.expensesBalancesCardTitle(balance.currency),
              subtitle: l10n.expensesBalancesNetHint,
              children: [
                for (final memberId in (balance.nets.isNotEmpty
                    ? (balance.nets.keys.toList()..sort())
                    : (widget.memberLabels.keys.toList()..sort())))
                  _SettlementBalanceRow(
                    name: _participantLabel(memberId),
                    showMeSuffix: _isViewerUnit(memberId, viewerBillingUnitId),
                    initial: avatarInitialFromDisplayLabel(
                      _participantLabel(memberId),
                    ),
                    amountLabel: _formatSignedBalance(
                      balance.currency,
                      balance.nets[memberId] ?? 0.0,
                    ),
                    amount: balance.nets[memberId] ?? 0.0,
                  ),
              ],
            ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      l10n.expensesSuggestedReimbursements.toUpperCase(),
                      style: sectionLabelStyle,
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              _buildTousMoiSegmentedFilter(
                context,
                showAll: _showAllPost,
                onShowAllChanged: (showAll) {
                  setState(() => _showAllPost = showAll);
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            l10n.expensesSuggestedReimbursementsHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 11.5,
                  height: 1.4,
                ),
          ),
        ),
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
            return _SettlementReimburseCard(
              fromName: _participantLabel(suggestion.fromParticipantId),
              toName: _participantLabel(suggestion.toParticipantId),
              fromInitial: avatarInitialFromDisplayLabel(
                _participantLabel(suggestion.fromParticipantId),
              ),
              toInitial: avatarInitialFromDisplayLabel(
                _participantLabel(suggestion.toParticipantId),
              ),
              amountLabel: _formatMoney(suggestion.currency, suggestion.amount),
              payEnabled: canMark,
              busy: _busySuggestionKey ==
                  '${suggestion.fromParticipantId}|${suggestion.toParticipantId}|${suggestion.currency}|${suggestion.amount}',
              onPay: () => _markPaid(suggestion),
            );
          }),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
          child: Text(
            l10n.expensesSettledReimbursements.toUpperCase(),
            style: sectionLabelStyle,
          ),
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
            return _SettlementReimburseCard(
              fromName: _participantLabel(settlement.paidBy),
              toName: _participantLabel(toId),
              fromInitial: avatarInitialFromDisplayLabel(
                _participantLabel(settlement.paidBy),
              ),
              toInitial: avatarInitialFromDisplayLabel(_participantLabel(toId)),
              amountLabel: _formatMoney(settlement.currency, settlement.amount),
              payEnabled: canMark,
              isRecorded: true,
              busy: _busySuggestionKey == settlement.id,
              onPay: () => _unmarkPaid(settlement),
            );
          }),
      ],
    );
  }
}

class _SettlementBalanceCard extends StatelessWidget {
  const _SettlementBalanceCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: NeonPalette.deep,
                        fontSize: 13,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettlementBalanceRow extends StatelessWidget {
  const _SettlementBalanceRow({
    required this.name,
    required this.showMeSuffix,
    required this.initial,
    required this.amountLabel,
    required this.amount,
  });

  final String name;
  final bool showMeSuffix;
  final String initial;
  final String amountLabel;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pz = context.planerzColors;
    const threshold = 0.5;
    final effectiveAmount = amount.abs() < threshold ? 0.0 : amount;
    final isCreditor = effectiveAmount > 0;
    final isDebtor = effectiveAmount < 0;
    final amountColor = isCreditor
        ? pz.success
        : isDebtor
            ? NeonPalette.accent
            : cs.onSurfaceVariant;
    final avatarBg = Color.alphaBlend(
      NeonPalette.primary.withValues(alpha: 0.16),
      cs.surface,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: avatarBg,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: TextStyle(
                color: NeonPalette.primary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: showMeSuffix
                ? Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: name,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: NeonPalette.deep,
                              ),
                        ),
                        TextSpan(
                          text:
                              ' · ${AppLocalizations.of(context)!.commonMe}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                              ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: NeonPalette.deep,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          Text(
            amountLabel,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: amountColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

class _SettlementReimburseCard extends StatelessWidget {
  const _SettlementReimburseCard({
    required this.fromName,
    required this.toName,
    required this.fromInitial,
    required this.toInitial,
    required this.amountLabel,
    required this.payEnabled,
    required this.busy,
    required this.onPay,
    this.isRecorded = false,
  });

  final String fromName;
  final String toName;
  final String fromInitial;
  final String toInitial;
  final String amountLabel;
  final bool payEnabled;
  final bool busy;
  final VoidCallback onPay;
  final bool isRecorded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final pz = context.planerzColors;
    final lockedSuggested = !isRecorded && !payEnabled;
    final tappable = payEnabled && !busy;

    final Color buttonBg;
    final Color buttonFg;
    final IconData? buttonIcon;
    final BoxBorder? buttonBorder;
    final String buttonLabel;

    if (isRecorded) {
      buttonBg = Color.alphaBlend(pz.success.withValues(alpha: 0.12), cs.surface);
      buttonFg = pz.success;
      buttonIcon = Icons.check_circle;
      buttonBorder = Border.all(
        color: Color.lerp(cs.outlineVariant, pz.success, 0.32)!,
      );
      buttonLabel = l10n.expensesPaidButton;
    } else if (lockedSuggested) {
      buttonBg = Color.alphaBlend(
        NeonPalette.outline.withValues(alpha: 0.16),
        NeonPalette.surface,
      );
      buttonFg = NeonPalette.onSurfaceVariant;
      buttonIcon = Icons.lock;
      buttonBorder = null;
      buttonLabel = l10n.expensesPaidButton;
    } else {
      buttonBg = pz.success;
      buttonFg = Colors.white;
      buttonIcon = null;
      buttonBorder = null;
      buttonLabel = l10n.expensesPaidButton;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _SettlementFlowParticipant(
                  name: fromName,
                  initial: fromInitial,
                  tint: NeonPalette.accent,
                  background: Color.alphaBlend(
                    NeonPalette.accent.withValues(alpha: 0.18),
                    cs.surface,
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        amountLabel,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: NeonPalette.deep,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                      ),
                      Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
                _SettlementFlowParticipant(
                  name: toName,
                  initial: toInitial,
                  tint: pz.success,
                  background: Color.alphaBlend(
                    pz.success.withValues(alpha: 0.20),
                    cs.surface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: lockedSuggested
                ? l10n.expensesLockToMarkPaidTooltip
                : isRecorded
                    ? l10n.expensesUnmarkReimbursementPaid
                    : l10n.expensesMarkReimbursementPaid,
            child: Material(
              color: buttonBg,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                onTap: tappable ? onPay : null,
                borderRadius: BorderRadius.circular(999),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: buttonBorder,
                  ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: busy
                      ? SizedBox(
                          width: 52,
                          height: 16,
                          child: Center(
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: buttonFg,
                              ),
                            ),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (buttonIcon != null) ...[
                              Icon(buttonIcon, size: 14, color: buttonFg),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              buttonLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: buttonFg,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5,
                                  ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}

class _SettlementFlowParticipant extends StatelessWidget {
  const _SettlementFlowParticipant({
    required this.name,
    required this.initial,
    required this.tint,
    required this.background,
  });

  final String name;
  final String initial;
  final Color tint;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: TextStyle(
                color: tint,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 10.5,
                ),
          ),
        ],
      ),
    );
  }
}

/// Operations under each post: newest days first, with a date header per calendar day.
List<Widget> _buildExpensesGroupedByDate(
  BuildContext context,
  List<TripExpense> expenses,
  String tripId,
  List<String> participantScopeMemberIds,
  Map<String, String> memberLabels, {
  required String? viewerBillingUnitId,
  required Map<String, double> groupParts,
  required String? currentUserMemberId,
  required bool canEditExpense,
  required bool canDeleteExpense,
}) {
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
  final locale = Localizations.localeOf(context).toString();

  final widgets = <Widget>[];
  for (var i = 0; i < days.length; i++) {
    final day = days[i];
    final dayExpenses = byDay[day]!;

    widgets.add(
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 14, bottom: 8),
        child: Text(
          DateFormat.yMMMEd(locale).format(day),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: NeonPalette.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );

    for (final e in dayExpenses) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ExpenseCard(
            tripId: tripId,
            expense: e,
            participantScopeMemberIds: participantScopeMemberIds,
            memberLabels: memberLabels,
            viewerBillingUnitId: viewerBillingUnitId,
            groupParts: groupParts,
            currentUserMemberId: currentUserMemberId,
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
    required this.viewerBillingUnitId,
    required this.groupParts,
    required this.currentUserMemberId,
    required this.canEditExpense,
    required this.canDeleteExpense,
  });

  final String tripId;
  final TripExpense expense;
  final List<String> participantScopeMemberIds;
  final Map<String, String> memberLabels;
  final String? viewerBillingUnitId;
  final Map<String, double> groupParts;
  final String? currentUserMemberId;
  final bool canEditExpense;
  final bool canDeleteExpense;

  Future<void> _openDetails(BuildContext context) async {
    if (expense.operationType == ExpenseOperationType.settlement) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ExpenseDetailsPage(
          tripId: tripId,
          expense: expense,
          participantScopeMemberIds: participantScopeMemberIds,
          memberLabels: memberLabels,
          currentUserMemberId: currentUserMemberId,
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
    final locale = Localizations.localeOf(context).toString();
    final isSettlement = e.operationType == ExpenseOperationType.settlement;
    final paidByLabel =
        memberLabels[e.paidBy] ?? l10n.tripParticipantsTraveler;
    final title = isSettlement
        ? l10n.expensesSettlementType
        : (e.title.isEmpty ? l10n.activitiesUntitled : e.title);

    final splitKey =
        e.splitMode == ExpenseSplitMode.customAmounts ? 'custom' : 'equal';
    final share = isSettlement
        ? 0.0
        : expenseShareForUnit(
            amount: e.amount,
            unitId: viewerBillingUnitId ?? '',
            participantIds: e.participantIds,
            groupParts: groupParts,
            splitModeKey: splitKey,
            participantShares: e.participantShares,
          );
    final delta = isSettlement
        ? null
        : viewerExpenseDelta(
            viewerBillingUnitId: viewerBillingUnitId,
            paidBy: e.paidBy,
            participantIds: e.participantIds,
            amount: e.amount,
            share: share,
          );

    return Material(
      color: NeonPalette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isSettlement ? null : () => _openDetails(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NeonPalette.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isSettlement)
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: NeonPalette.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    expenseIconForExpense(e.icon),
                    color: NeonPalette.accent,
                    size: 22,
                  ),
                )
              else
                Icon(Icons.sync_alt, color: NeonPalette.secondary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          isSettlement
                              ? (e.participantIds.isNotEmpty
                                  ? l10n.expensesReimbursementFromTo(
                                      paidByLabel,
                                      memberLabels[e.participantIds.first] ??
                                          l10n.tripParticipantsTraveler,
                                    )
                                  : l10n.expensesSettlementType)
                              : l10n.expensesPaidByWithLabel(paidByLabel),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: NeonPalette.onSurfaceVariant,
                              ),
                        ),
                        if (!isSettlement) ...[
                          const Text('·', style: TextStyle(color: NeonPalette.outline)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                e.splitMode == ExpenseSplitMode.customAmounts
                                    ? Icons.tune
                                    : Icons.safety_divider,
                                size: 13,
                                color: NeonPalette.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                e.splitMode == ExpenseSplitMode.customAmounts
                                    ? l10n.expensesSplitCustomAmounts
                                    : l10n.expensesSplitModeEqualShort,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: NeonPalette.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatExpenseMoney(e.currency, e.amount, locale: locale),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                  if (!isSettlement && delta != null && delta.abs() >= 0.01) ...[
                    const SizedBox(height: 2),
                    Text(
                      delta > 0
                          ? '+${formatExpenseMoney(e.currency, delta, locale: locale)}'
                          : l10n.expensesListYouOwe(
                              formatExpenseMoney(e.currency, -delta, locale: locale),
                            ),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: delta > 0 ? NeonPalette.success : NeonPalette.accent,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
