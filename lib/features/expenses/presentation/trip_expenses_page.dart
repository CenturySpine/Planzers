import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/expenses/data/expense.dart';
import 'package:planerz/features/expenses/data/expense_group.dart';
import 'package:planerz/features/expenses/data/expenses_repository.dart';
import 'package:planerz/features/expenses/data/settled_transfer.dart';
import 'package:planerz/features/expenses/domain/expense_settlement.dart';
import 'package:planerz/features/expenses/presentation/expense_group_editor_sheet.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Trip members who may appear as payers/participants for this expense post.
List<String> participantScopeMemberIdsForGroup(
  TripExpenseGroup group,
  List<String> tripMemberIds,
) {
  final clean = tripMemberIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList();
  if (group.visibleToMemberIds.isEmpty) {
    return [];
  }
  final allowed = group.visibleToMemberIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  return clean.where((id) => allowed.contains(id)).toList()..sort();
}

/// Settled transfers involving [viewerUserId], or all if viewer is null/blank.
List<SettledTransfer> settledTransfersVisibleToViewer(
  List<SettledTransfer> groupSettled,
  String? viewerUserId,
) {
  final v = viewerUserId?.trim();
  final filtered = v == null || v.isEmpty
      ? groupSettled.toList()
      : groupSettled
          .where((t) {
            final from = t.fromUserId.trim();
            final to = t.toUserId.trim();
            return from == v || to == v;
          })
          .toList();
  filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return filtered;
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
    final trip = TripScope.of(context);
    final groupsAsync = ref.watch(tripExpenseGroupsStreamProvider(trip.id));
    final expensesAsync = ref.watch(tripExpensesStreamProvider(trip.id));
    final settledTransfersAsync =
        ref.watch(tripSettledTransfersStreamProvider(trip.id));
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final canCreateExpense = groupsAsync.maybeWhen(
      data: (groups) {
        final visibleGroups = groups
            .where((group) => group.isVisibleTo(viewerId))
            .toList();
        return visibleGroups.any(
          (group) => canCreateExpenseForTrip(
            trip: trip,
            userId: viewerId,
            expensePostVisibleToMemberIds: group.visibleToMemberIds,
          ),
        );
      },
      orElse: () => false,
    );

    return Scaffold(
      body: groupsAsync.when(
        data: (groups) => expensesAsync.when(
          data: (expenses) => settledTransfersAsync.when(
            data: (settledTransfers) {
              return _TripExpensesBody(
                trip: trip,
                memberIds: trip.memberIds,
                memberPublicLabels: trip.memberPublicLabels,
                groups: groups,
                expenses: expenses,
                settledTransfers: settledTransfers,
                activeGroupId: _activeGroupId,
                onActiveGroupChanged: (groupId) {
                  if (_activeGroupId == groupId) return;
                  setState(() => _activeGroupId = groupId);
                },
                onCreateExpensePost: canCreateExpensePostForTrip(
                  trip: trip,
                  userId: viewerId,
                )
                    ? () => _openExpenseGroupEditor(
                          context,
                          ref,
                          trip.id,
                          trip.memberIds,
                          trip.memberPublicLabels,
                          existing: null,
                        )
                    : null,
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
      floatingActionButton: canCreateExpense
          ? FloatingActionButton(
              heroTag: 'trip_expenses_add',
              tooltip: AppLocalizations.of(context)!.expensesAddExpenseTooltip,
              onPressed: () => _openAddExpenseSheetFromFab(
                context,
                ref,
                trip.id,
                trip.memberIds,
                trip.memberPublicLabels,
                _activeGroupId,
              ),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  static Future<void> _openExpenseGroupEditor(
    BuildContext context,
    WidgetRef ref,
    String tripId,
    List<String> memberIds,
    Map<String, String> memberPublicLabels, {
    required TripExpenseGroup? existing,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ExpenseGroupEditorSheet(
        tripId: tripId,
        memberIds: memberIds,
        memberPublicLabels: memberPublicLabels,
        existing: existing,
        onDone: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  static Future<void> _openAddExpenseSheetFromFab(
    BuildContext context,
    WidgetRef ref,
    String tripId,
    List<String> memberIds,
    Map<String, String> memberPublicLabels,
    String? preferredGroupId,
  ) async {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final groups =
        await ref.read(expensesRepositoryProvider).watchTripExpenseGroups(tripId).first;
    final visible = groups.where((g) => g.isVisibleTo(viewerId)).toList();
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
    await _openAddExpenseSheet(
      context,
      tripId,
      memberIds,
      memberPublicLabels,
      groupId: group.id,
      participantScopeMemberIds:
          participantScopeMemberIdsForGroup(group, memberIds),
    );
  }

  static Future<void> _openAddExpenseSheet(
    BuildContext context,
    String tripId,
    List<String> memberIds,
    Map<String, String> memberPublicLabels, {
    required String groupId,
    required List<String> participantScopeMemberIds,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _AddExpenseSheet(
          tripId: tripId,
          groupId: groupId,
          participantScopeMemberIds: participantScopeMemberIds,
          memberPublicLabels: memberPublicLabels,
          onSubmit: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

class _TripExpensesBody extends StatelessWidget {
  const _TripExpensesBody({
    required this.trip,
    required this.memberIds,
    required this.memberPublicLabels,
    required this.groups,
    required this.expenses,
    required this.settledTransfers,
    required this.activeGroupId,
    required this.onActiveGroupChanged,
    required this.onCreateExpensePost,
  });

  final Trip trip;
  final List<String> memberIds;
  final Map<String, String> memberPublicLabels;
  final List<TripExpenseGroup> groups;
  final List<TripExpense> expenses;
  final List<SettledTransfer> settledTransfers;
  final String? activeGroupId;
  final ValueChanged<String> onActiveGroupChanged;
  final VoidCallback? onCreateExpensePost;

  @override
  Widget build(BuildContext context) {
    final cleanMemberIds =
        memberIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toList();

    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final visibleGroups = groups.where((g) => g.isVisibleTo(viewerId)).toList()
      ..sort((a, b) {
        // Keep the main/default post first, then place newly created posts to the right.
        if (a.isDefault != b.isDefault) {
          return a.isDefault ? -1 : 1;
        }
        final createdAtOrder = a.createdAt.compareTo(b.createdAt);
        if (createdAtOrder != 0) return createdAtOrder;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    if (cleanMemberIds.isEmpty) {
      return _buildScrollView(
        context,
        const {},
        visibleGroups,
        viewerId,
        memberPublicLabels,
        trip,
        onCreateExpensePost,
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: cleanMemberIds)
          .snapshots(),
      builder: (context, snapshot) {
        final labels = tripMemberLabelsFromUserQuerySnapshot(
          snapshot.data,
          cleanMemberIds,
          tripMemberPublicLabels: memberPublicLabels,
          currentUserId: FirebaseAuth.instance.currentUser?.uid,
          emptyFallback: AppLocalizations.of(context)!.tripParticipantsTraveler,
        );

        return _buildScrollView(
          context,
          labels,
          visibleGroups,
          viewerId,
          memberPublicLabels,
          trip,
          onCreateExpensePost,
        );
      },
    );
  }

  Widget _buildScrollView(
    BuildContext context,
    Map<String, String> labels,
    List<TripExpenseGroup> visibleGroups,
    String? viewerId,
    Map<String, String> memberPublicLabels,
    Trip trip,
    VoidCallback? onCreateExpensePost,
  ) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, cs.inverseSurface],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  l10n.expensesPostsTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: cs.onInverseSurface,
                      ),
                ),
              ),
              if (onCreateExpensePost != null)
                IconButton(
                  tooltip: l10n.expenseGroupNewTitle,
                  icon: Icon(
                    Icons.create_new_folder_outlined,
                    color: cs.onInverseSurface,
                  ),
                  onPressed: onCreateExpensePost,
                )
              else
                // Même emprise qu’un IconButton (hauteur du cartouche inchangée).
                const SizedBox(
                  width: kMinInteractiveDimension,
                  height: kMinInteractiveDimension,
                ),
            ],
          ),
        ),
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
                 allTripExpenses: expenses,
                 groupExpenses: expenses
                      .where((e) => e.groupId == visibleGroups.single.id)
                      .toList(),
                 groupSettledTransfers: settledTransfers
                     .where((t) => t.groupId == visibleGroups.single.id)
                     .toList(),
                  memberIds: memberIds,
                  memberPublicLabels: memberPublicLabels,
                 memberLabels: labels,
                viewerUserId: viewerId,
              ),
            ),
          )
        else
          Expanded(
            child: _ExpensePostsTabbedView(
              trip: trip,
              groups: visibleGroups,
               expenses: expenses,
               settledTransfers: settledTransfers,
                memberIds: memberIds,
              memberPublicLabels: memberPublicLabels,
              memberLabels: labels,
              viewerUserId: viewerId,
              initialGroupId: activeGroupId,
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
    required this.settledTransfers,
    required this.memberIds,
    required this.memberPublicLabels,
    required this.memberLabels,
    required this.viewerUserId,
    required this.initialGroupId,
    required this.onActiveGroupChanged,
  });

  final Trip trip;
  final List<TripExpenseGroup> groups;
  final List<TripExpense> expenses;
  final List<SettledTransfer> settledTransfers;
  final List<String> memberIds;
  final Map<String, String> memberPublicLabels;
  final Map<String, String> memberLabels;
  final String? viewerUserId;
  final String? initialGroupId;
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
                      allTripExpenses: widget.expenses,
                      groupExpenses:
                          widget.expenses.where((e) => e.groupId == group.id).toList(),
                      groupSettledTransfers: widget.settledTransfers
                          .where((t) => t.groupId == group.id)
                          .toList(),
                      memberIds: widget.memberIds,
                     memberPublicLabels: widget.memberPublicLabels,
                     memberLabels: widget.memberLabels,
                    viewerUserId: widget.viewerUserId,
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
    required this.allTripExpenses,
    required this.groupExpenses,
    required this.groupSettledTransfers,
    required this.memberIds,
    required this.memberPublicLabels,
    required this.memberLabels,
    required this.viewerUserId,
  });

  final Trip trip;
  final TripExpenseGroup group;
  final List<TripExpense> allTripExpenses;
  final List<TripExpense> groupExpenses;
  final List<SettledTransfer> groupSettledTransfers;
  final List<String> memberIds;
  final Map<String, String> memberPublicLabels;
  final Map<String, String> memberLabels;
  final String? viewerUserId;

  @override
  ConsumerState<_ExpensePostPanel> createState() => _ExpensePostPanelState();
}

class _ExpensePostPanelState extends ConsumerState<_ExpensePostPanel> {
  bool _deletingPost = false;
  bool _savingSettledTransfer = false;
  _ExpensePostView _activeView = _ExpensePostView.operations;

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
    final viewerUserId = widget.viewerUserId?.trim();
    final settlement = computeViewerSettlement(
      widget.groupExpenses,
      viewerUserId,
      settledTransfers: widget.groupSettledTransfers
          .map((transfer) => transfer.toSuggestedTransfer()),
    );
    final tripTotalsByCurrency = _sumByCurrency(widget.allTripExpenses);
    final myTotalsByCurrency = _sumByCurrency(
      widget.allTripExpenses.where(
        (expense) {
          final paidBy = expense.paidBy.trim();
          return viewerUserId != null && paidBy == viewerUserId;
        },
      ),
    );
    final scope = participantScopeMemberIdsForGroup(
      widget.group,
      widget.memberIds,
    );

    final canEditPost = canEditExpensePostForTrip(
      trip: widget.trip,
      userId: viewerUserId,
      expensePostVisibleToMemberIds: widget.group.visibleToMemberIds,
    );
    final canDeletePost = canDeleteExpensePostForTrip(
      trip: widget.trip,
      userId: viewerUserId,
      expensePostVisibleToMemberIds: widget.group.visibleToMemberIds,
    );
    final canEditExpense = canEditExpenseForTrip(
      trip: widget.trip,
      userId: viewerUserId,
      expensePostVisibleToMemberIds: widget.group.visibleToMemberIds,
    );
    final canDeleteExpense = canDeleteExpenseForTrip(
      trip: widget.trip,
      userId: viewerUserId,
      expensePostVisibleToMemberIds: widget.group.visibleToMemberIds,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              SegmentedButton<_ExpensePostView>(
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
                  setState(() => _activeView = selection.first);
                },
              ),
              if (canEditPost || canDeletePost)
                Positioned(
                  right: -6,
                  child: PopupMenuButton<_ExpensePostMenuAction>(
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
                          ref,
                          widget.trip.id,
                          widget.memberIds,
                          widget.memberPublicLabels,
                          existing: widget.group,
                        );
                        return;
                      }
                      await _confirmDeletePost();
                    },
                    itemBuilder: (context) {
                      final items = <PopupMenuEntry<_ExpensePostMenuAction>>[];
                      if (canEditPost) {
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
                      if (canDeletePost) {
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
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_activeView == _ExpensePostView.settlement)
          _SettlementSection(
            balancesByCurrency: settlement.balancesByCurrency,
            pendingTransfers: settlement.suggestedTransfers,
            settledTransfers: settledTransfersVisibleToViewer(
              widget.groupSettledTransfers,
              viewerUserId,
            ),
            memberLabels: widget.memberLabels,
            viewerUserId: viewerUserId,
            markingInProgress: _savingSettledTransfer,
            onMarkTransferDone: (transfer) async {
              if (_savingSettledTransfer) return;
              setState(() => _savingSettledTransfer = true);
              try {
                await ref.read(expensesRepositoryProvider).markTransferAsSettled(
                      tripId: widget.trip.id,
                      groupId: widget.group.id,
                      transfer: transfer,
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
                if (mounted) {
                  setState(() => _savingSettledTransfer = false);
                }
              }
            },
            onUnmarkSettled: (settled) async {
              if (_savingSettledTransfer) return;
              setState(() => _savingSettledTransfer = true);
              try {
                await ref.read(expensesRepositoryProvider).deleteSettledTransfer(
                      tripId: widget.trip.id,
                      settledTransferId: settled.id,
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
                if (mounted) {
                  setState(() => _savingSettledTransfer = false);
                }
              }
            },
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ExpenseTotalsHeader(
                myTotalsByCurrency: myTotalsByCurrency,
                tripTotalsByCurrency: tripTotalsByCurrency,
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
                  canEditExpense: canEditExpense,
                  canDeleteExpense: canDeleteExpense,
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

Map<String, double> _sumByCurrency(Iterable<TripExpense> expenses) {
  final totals = <String, double>{};
  for (final expense in expenses) {
    final currency = expense.currency.trim().toUpperCase();
    if (currency.isEmpty) continue;
    totals.update(
      currency,
      (value) => value + expense.amount,
      ifAbsent: () => expense.amount,
    );
  }
  return totals;
}

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

/// Remboursement suggéré : formulation à la 1ʳᵉ personne si [viewerUserId] est concerné.
String _formatSuggestedTransferLine({
  required SuggestedTransfer transfer,
  required Map<String, String> memberLabels,
  required String? viewerUserId,
  required AppLocalizations l10n,
}) {
  final v = viewerUserId?.trim();
  final fromId = transfer.fromUserId.trim();
  final toId = transfer.toUserId.trim();
  final fromL = memberLabels[fromId] ?? l10n.tripParticipantsTraveler;
  final toL = memberLabels[toId] ?? l10n.tripParticipantsTraveler;
  final amt = _formatMoney(transfer.currency, transfer.amount);

  if (v != null && v.isNotEmpty) {
    if (fromId == v) {
      return l10n.expensesYouOwe(amt, toL);
    }
    if (toId == v) {
      return l10n.expensesOwesYou(fromL, amt);
    }
  }
  return l10n.expensesGivesTo(fromL, amt, toL);
}

enum _ExpenseDetailsMenuAction { edit, delete }
enum _ExpensePostMenuAction { edit, delete }

class _ExpenseTotalsHeader extends StatelessWidget {
  const _ExpenseTotalsHeader({
    required this.myTotalsByCurrency,
    required this.tripTotalsByCurrency,
  });

  final Map<String, double> myTotalsByCurrency;
  final Map<String, double> tripTotalsByCurrency;

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
          Container(
            width: 1,
            height: 36,
            color: cs.outlineVariant,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(l10n.expensesTripTotalCost, style: labelStyle),
                const SizedBox(height: 3),
                Text(
                  _formatTotalsByCurrency(tripTotalsByCurrency),
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

class _SettlementSection extends StatelessWidget {
  const _SettlementSection({
    required this.balancesByCurrency,
    required this.pendingTransfers,
    required this.settledTransfers,
    required this.memberLabels,
    required this.viewerUserId,
    required this.markingInProgress,
    required this.onMarkTransferDone,
    required this.onUnmarkSettled,
  });

  final BalancesByCurrency balancesByCurrency;
  final List<SuggestedTransfer> pendingTransfers;
  final List<SettledTransfer> settledTransfers;
  final Map<String, String> memberLabels;
  final String? viewerUserId;
  final bool markingInProgress;
  final Future<void> Function(SuggestedTransfer transfer) onMarkTransferDone;
  final Future<void> Function(SettledTransfer settled) onUnmarkSettled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final pz = context.planerzColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.balance_outlined,
          label: l10n.expensesBalancesByCurrency,
          iconColor: cs.secondary,
        ),
        const SizedBox(height: 8),
        if (balancesByCurrency.isEmpty)
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
          ...balancesByCurrency.entries.map((currencyEntry) {
            final currency = currencyEntry.key;
            final perUser = currencyEntry.value;
            if (perUser.isEmpty) {
              return const SizedBox.shrink();
            }
            final sortedIds = perUser.keys.toList()..sort();
            return Padding(
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
                      currency,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                            letterSpacing: 1.1,
                          ),
                    ),
                    const SizedBox(height: 6),
                    ...sortedIds.map((uid) {
                      final bal = perUser[uid] ?? 0;
                      final label =
                          memberLabels[uid] ?? l10n.tripParticipantsTraveler;
                      final isCreditor = bal > 0.009;
                      final isDebtor = bal < -0.009;

                      final chipBg = isCreditor
                          ? pz.successContainer
                          : isDebtor
                              ? cs.errorContainer
                              : cs.surfaceContainerHighest;
                      final chipFg = isCreditor
                          ? pz.success
                          : isDebtor
                              ? cs.error
                              : cs.onSurfaceVariant;
                      final prefix = isCreditor
                          ? l10n.expensesToReceive
                          : isDebtor
                              ? l10n.expensesToPay
                              : l10n.expensesBalanced;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: chipBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$prefix · ${_formatMoney(currency, bal.abs())}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: chipFg,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 4),
        _SectionHeader(
          icon: Icons.sync_alt,
          label: l10n.expensesSuggestedReimbursements,
          iconColor: cs.primary,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.expensesSuggestedReimbursementsHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        if (pendingTransfers.isEmpty && settledTransfers.isEmpty)
          Text(
            balancesByCurrency.isEmpty
                ? l10n.expensesNoCalculationYet
                : l10n.expensesYouOweNothing,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          )
        else ...[
          ...pendingTransfers.map((t) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Semantics(
                label: l10n.expensesMarkReimbursementDoneSemantics,
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: false,
                  onChanged: markingInProgress
                      ? null
                      : (value) async {
                          if (value != true) return;
                          await onMarkTransferDone(t);
                        },
                  title: Text(
                    _formatSuggestedTransferLine(
                      transfer: t,
                      memberLabels: memberLabels,
                      viewerUserId: viewerUserId,
                      l10n: l10n,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            );
          }),
          ...settledTransfers.map((s) {
            final t = s.toSuggestedTransfer();
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Semantics(
                label: l10n.expensesUnmarkReimbursementSemantics,
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: true,
                  onChanged: markingInProgress
                      ? null
                      : (value) async {
                          if (value != false) return;
                          await onUnmarkSettled(s);
                        },
                  title: Text(
                    _formatSuggestedTransferLine(
                      transfer: t,
                      memberLabels: memberLabels,
                      viewerUserId: viewerUserId,
                      l10n: l10n,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
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
    final cs = Theme.of(context).colorScheme;
    final paidByLabel =
        memberLabels[e.paidBy] ?? AppLocalizations.of(context)!.tripParticipantsTraveler;

    return Card(
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetails(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.title.isEmpty
                            ? AppLocalizations.of(context)!.activitiesUntitled
                            : e.title,
                        style: Theme.of(context).textTheme.bodyLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocalizations.of(context)!.expensesPaidByWithLabel(
                          paidByLabel,
                        ),
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
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatMoney(e.currency, e.amount),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: cs.onPrimaryContainer,
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
                      initialValue: _paidBy != null && members.contains(_paidBy)
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

class _AddExpenseSheet extends ConsumerStatefulWidget {
  const _AddExpenseSheet({
    required this.tripId,
    required this.groupId,
    required this.participantScopeMemberIds,
    required this.memberPublicLabels,
    required this.onSubmit,
  });

  final String tripId;
  final String groupId;
  final List<String> participantScopeMemberIds;
  final Map<String, String> memberPublicLabels;
  final VoidCallback onSubmit;

  @override
  ConsumerState<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<_AddExpenseSheet> {
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
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final members = _scopeMemberIds;
    _paidBy = (myUid != null && members.contains(myUid))
        ? myUid
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
      widget.onSubmit();
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.add_card_outlined,
                    size: 20,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.expensesNewExpenseTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
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
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where(FieldPath.documentId, whereIn: members)
                    .snapshots(),
                builder: (context, snapshot) {
                  final labels = tripMemberLabelsFromUserQuerySnapshot(
                    snapshot.data,
                    members,
                    tripMemberPublicLabels: widget.memberPublicLabels,
                    currentUserId: FirebaseAuth.instance.currentUser?.uid,
                    emptyFallback: l10n.tripParticipantsTraveler,
                  );
                  return Column(
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
                                      labels[id] ?? id,
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
                                  suffixIcon:
                                      Icon(Icons.calendar_today_outlined),
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
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(
                                  labels[id] ?? id,
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
                  );
                },
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
    );
  }
}
