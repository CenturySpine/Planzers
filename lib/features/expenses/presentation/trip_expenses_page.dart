import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
import 'package:planzers/features/expenses/data/expense.dart';
import 'package:planzers/features/expenses/data/expense_group.dart';
import 'package:planzers/features/expenses/data/expenses_repository.dart';
import 'package:planzers/features/expenses/domain/expense_settlement.dart';
import 'package:planzers/features/expenses/presentation/expense_group_editor_sheet.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';

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

    return Scaffold(
      body: groupsAsync.when(
        data: (groups) => expensesAsync.when(
          data: (expenses) {
            return _TripExpensesBody(
              tripId: trip.id,
              memberIds: trip.memberIds,
              memberPublicLabels: trip.memberPublicLabels,
              groups: groups,
              expenses: expenses,
              activeGroupId: _activeGroupId,
              onActiveGroupChanged: (groupId) {
                if (_activeGroupId == groupId) return;
                setState(() => _activeGroupId = groupId);
              },
              onCreateExpensePost: () => _openExpenseGroupEditor(
                context,
                ref,
                trip.id,
                trip.memberIds,
                trip.memberPublicLabels,
                existing: null,
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Erreur: $e', textAlign: TextAlign.center),
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Erreur: $e', textAlign: TextAlign.center),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'trip_expenses_add',
        tooltip: 'Ajouter une dépense',
        onPressed: () => _openAddExpenseSheetFromFab(
          context,
          ref,
          trip.id,
          trip.memberIds,
          trip.memberPublicLabels,
          _activeGroupId,
        ),
        child: const Icon(Icons.add),
      ),
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
        const SnackBar(
          content: Text(
            'Crée d’abord un poste de dépenses (icône dossier dans l’en-tête).',
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
    required this.tripId,
    required this.memberIds,
    required this.memberPublicLabels,
    required this.groups,
    required this.expenses,
    required this.activeGroupId,
    required this.onActiveGroupChanged,
    required this.onCreateExpensePost,
  });

  final String tripId;
  final List<String> memberIds;
  final Map<String, String> memberPublicLabels;
  final List<TripExpenseGroup> groups;
  final List<TripExpense> expenses;
  final String? activeGroupId;
  final ValueChanged<String> onActiveGroupChanged;
  final VoidCallback onCreateExpensePost;

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
          emptyFallback: 'Voyageur',
        );

        return _buildScrollView(
          context,
          labels,
          visibleGroups,
          viewerId,
          memberPublicLabels,
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
    VoidCallback onCreateExpensePost,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Postes de dépenses',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Nouveau poste',
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: onCreateExpensePost,
              ),
            ],
          ),
        ),
        if (visibleGroups.isEmpty)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              child: Text(
                'Aucun poste de dépenses pour l’instant. Utilise l’icône dossier en haut pour en créer un.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          )
        else if (visibleGroups.length == 1)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              child: _ExpensePostPanel(
                tripId: tripId,
                group: visibleGroups.single,
                groupExpenses: expenses
                    .where((e) => e.groupId == visibleGroups.single.id)
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
              tripId: tripId,
              groups: visibleGroups,
              expenses: expenses,
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
    required this.tripId,
    required this.groups,
    required this.expenses,
    required this.memberIds,
    required this.memberPublicLabels,
    required this.memberLabels,
    required this.viewerUserId,
    required this.initialGroupId,
    required this.onActiveGroupChanged,
  });

  final String tripId;
  final List<TripExpenseGroup> groups;
  final List<TripExpense> expenses;
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
              Tab(text: group.title.isEmpty ? 'Sans titre' : group.title),
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
                    tripId: widget.tripId,
                    group: group,
                    groupExpenses:
                        widget.expenses.where((e) => e.groupId == group.id).toList(),
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
    required this.tripId,
    required this.group,
    required this.groupExpenses,
    required this.memberIds,
    required this.memberPublicLabels,
    required this.memberLabels,
    required this.viewerUserId,
  });

  final String tripId;
  final TripExpenseGroup group;
  final List<TripExpense> groupExpenses;
  final List<String> memberIds;
  final Map<String, String> memberPublicLabels;
  final Map<String, String> memberLabels;
  final String? viewerUserId;

  @override
  ConsumerState<_ExpensePostPanel> createState() => _ExpensePostPanelState();
}

class _ExpensePostPanelState extends ConsumerState<_ExpensePostPanel> {
  bool _deletingPost = false;

  Future<void> _confirmDeletePost() async {
    if (_deletingPost) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce poste ?'),
        content: Text(
          'Le poste « ${widget.group.title.isEmpty ? 'Sans titre' : widget.group.title} » '
          'et toutes ses opérations seront supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deletingPost = true);
    try {
      await ref.read(expensesRepositoryProvider).deleteExpenseGroup(
            tripId: widget.tripId,
            groupId: widget.group.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poste supprimé')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _deletingPost = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settlement =
        computeViewerSettlement(widget.groupExpenses, widget.viewerUserId);
    final scope = participantScopeMemberIdsForGroup(
      widget.group,
      widget.memberIds,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Modifier le poste',
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                iconSize: 20,
                onPressed: () async {
                  await _TripExpensesPageState._openExpenseGroupEditor(
                    context,
                    ref,
                    widget.tripId,
                    widget.memberIds,
                    widget.memberPublicLabels,
                    existing: widget.group,
                  );
                },
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Supprimer le poste',
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                iconSize: 20,
                onPressed: _confirmDeletePost,
                icon: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
        _SettlementSection(
          balancesByCurrency: settlement.balancesByCurrency,
          transfers: settlement.suggestedTransfers,
          memberLabels: widget.memberLabels,
          viewerUserId: widget.viewerUserId,
        ),
        const SizedBox(height: 12),
        Text(
          'Opérations',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (widget.groupExpenses.isEmpty)
          Text(
            'Aucune opération dans ce poste.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          )
        else
          ..._buildExpensesGroupedByDate(
            context,
            widget.groupExpenses,
            widget.tripId,
            scope,
            widget.memberLabels,
          ),
        const SizedBox(height: 8),
      ],
    );
  }
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
}) {
  final v = viewerUserId?.trim();
  final fromId = transfer.fromUserId.trim();
  final toId = transfer.toUserId.trim();
  final fromL = memberLabels[fromId] ?? 'Voyageur';
  final toL = memberLabels[toId] ?? 'Voyageur';
  final amt = _formatMoney(transfer.currency, transfer.amount);

  if (v != null && v.isNotEmpty) {
    if (fromId == v) {
      return 'Tu dois $amt à $toL';
    }
    if (toId == v) {
      return '$fromL te doit $amt';
    }
  }
  return '$fromL donne $amt à $toL';
}

enum _ExpenseDetailsMenuAction { edit, delete }

class _SettlementSection extends StatelessWidget {
  const _SettlementSection({
    required this.balancesByCurrency,
    required this.transfers,
    required this.memberLabels,
    required this.viewerUserId,
  });

  final BalancesByCurrency balancesByCurrency;
  final List<SuggestedTransfer> transfers;
  final Map<String, String> memberLabels;
  final String? viewerUserId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.balance_outlined, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Soldes (par devise)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (balancesByCurrency.isEmpty)
                  Text(
                    'Ajoute des dépenses pour voir la répartition.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currency,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          ...sortedIds.map((uid) {
                            final bal = perUser[uid] ?? 0;
                            final label = memberLabels[uid] ?? 'Voyageur';
                            final isCreditor = bal > 0.009;
                            final isDebtor = bal < -0.009;
                            final tone = isCreditor
                                ? colorScheme.primary
                                : isDebtor
                                    ? colorScheme.error
                                    : colorScheme.onSurfaceVariant;
                            final prefix = isCreditor
                                ? 'À recevoir'
                                : isDebtor
                                    ? 'À payer'
                                    : 'Équilibré';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(child: Text(label)),
                                  Text(
                                    '$prefix · ${_formatMoney(currency, bal.abs())}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: tone,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sync_alt, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Remboursements suggérés',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Nombre minimal de virements pour équilibrer les comptes (par devise).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                if (transfers.isEmpty)
                  Text(
                    balancesByCurrency.isEmpty
                        ? 'Pas encore de calcul.'
                        : 'Tu ne dois rien à personne 😎',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  )
                else
                  ...transfers.map((t) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_forward, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _formatSuggestedTransferLine(
                                transfer: t,
                                memberLabels: memberLabels,
                                viewerUserId: viewerUserId,
                              ),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
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

  final widgets = <Widget>[];
  for (var i = 0; i < days.length; i++) {
    final day = days[i];
    final dayExpenses = byDay[day]!;

    widgets.add(
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 12, bottom: 4),
        child: Text(
          DateFormat.yMMMEd('fr_FR').format(day),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
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
  });

  final String tripId;
  final TripExpense expense;
  final List<String> participantScopeMemberIds;
  final Map<String, String> memberLabels;

  Future<void> _openDetails(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ExpenseDetailsPage(
          tripId: tripId,
          expense: expense,
          participantScopeMemberIds: participantScopeMemberIds,
          memberLabels: memberLabels,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final paidByLabel = memberLabels[e.paidBy] ?? 'Voyageur';

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetails(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.title.isEmpty ? 'Sans titre' : e.title,
                      style: Theme.of(context).textTheme.bodyLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Payé par $paidByLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatMoney(e.currency, e.amount),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
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
  });

  final String tripId;
  final TripExpense expense;
  final List<String> participantScopeMemberIds;
  final Map<String, String> memberLabels;

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
      locale: 'fr_FR',
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
        '—',
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
      locale: const Locale('fr', 'FR'),
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
        title: const Text('Supprimer cette dépense ?'),
        content: Text('« ${widget.expense.title} » sera supprimée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
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
        const SnackBar(content: Text('Dépense supprimée')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
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
        const SnackBar(content: Text('Choisis qui a payé')),
      );
      return;
    }
    final scopeSet = widget.participantScopeMemberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (scopeSet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun voyageur autorisé dans ce poste.'),
        ),
      );
      return;
    }
    if (!scopeSet.contains(paidBy.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payeur invalide pour ce poste')),
      );
      return;
    }
    if (_participantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coche au moins un participant')),
      );
      return;
    }
    if (_participantIds.any((id) => !scopeSet.contains(id))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Participant hors périmètre du poste')),
      );
      return;
    }

    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Montant invalide')),
      );
      return;
    }

    Map<String, double>? customShares;
    if (_splitMode == ExpenseSplitMode.customAmounts) {
      customShares = _parseCustomSharesForSave();
      if (customShares == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pour « Montants », chaque part doit être valide et la somme doit égaler le total.',
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
        const SnackBar(content: Text('Dépense mise à jour')),
      );
      setState(() => _editing = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.participantScopeMemberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail de la dépense'),
        actions: [
          PopupMenuButton<_ExpenseDetailsMenuAction>(
            enabled: !_saving && !_deleting,
            onSelected: (action) async {
              if (action == _ExpenseDetailsMenuAction.edit) {
                setState(() => _editing = true);
                return;
              }
              await _confirmDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem<_ExpenseDetailsMenuAction>(
                value: _ExpenseDetailsMenuAction.edit,
                child: Text('Modifier'),
              ),
              PopupMenuItem<_ExpenseDetailsMenuAction>(
                value: _ExpenseDetailsMenuAction.delete,
                child: Text('Supprimer'),
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
              if (members.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Aucun voyageur n’est autorisé dans ce poste : modifie le poste ou le voyage pour pouvoir ajuster le partage.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                readOnly: !_editing,
                decoration: const InputDecoration(
                  labelText: 'Libellé',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obligatoire' : null,
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
                      decoration: const InputDecoration(
                        labelText: 'Montant',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim().replaceAll(',', '.');
                        final n = double.tryParse(t);
                        if (n == null || n <= 0) return 'Montant invalide';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey<String>(_currency),
                      initialValue: _currency,
                      decoration: const InputDecoration(
                        labelText: 'Devise',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'EUR',
                          child: Text('Euro (EUR)'),
                        ),
                        DropdownMenuItem(
                          value: 'USD',
                          child: Text('Dollar (USD)'),
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
                      decoration: const InputDecoration(
                        labelText: 'Payé par',
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
                        decoration: const InputDecoration(
                          labelText: 'Date de la dépense',
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
                      'Partage du montant',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (_editing)
                    DropdownButton<ExpenseSplitMode>(
                      value: _splitMode,
                      underline: const SizedBox.shrink(),
                      alignment: AlignmentDirectional.centerEnd,
                      items: const [
                        DropdownMenuItem(
                          value: ExpenseSplitMode.equal,
                          child: Text('Équitablement'),
                        ),
                        DropdownMenuItem(
                          value: ExpenseSplitMode.customAmounts,
                          child: Text('Montants'),
                        ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) _onSplitModeChanged(mode);
                      },
                    )
                  else
                    Text(
                      _splitMode == ExpenseSplitMode.equal
                          ? 'Équitablement'
                          : 'Montants',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
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
                      : const Text('Enregistrer les modifications'),
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
      locale: const Locale('fr', 'FR'),
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
        const SnackBar(content: Text('Choisis qui a payé')),
      );
      return;
    }

    if (_participantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coche au moins un participant')),
      );
      return;
    }

    final amountText = _amountController.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Montant invalide')),
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
        const SnackBar(content: Text('Dépense enregistrée')),
      );
      widget.onSubmit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = _scopeMemberIds;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nouvelle dépense',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (members.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Aucun voyageur autorisé dans ce poste pour partager une dépense.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            if (members.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Libellé',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Obligatoire';
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
                      decoration: const InputDecoration(
                        labelText: 'Montant',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim().replaceAll(',', '.');
                        final n = double.tryParse(t);
                        if (n == null || n <= 0) return 'Montant invalide';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey<String>(_currency),
                      initialValue: _currency,
                      decoration: const InputDecoration(
                        labelText: 'Devise',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'EUR', child: Text('Euro (EUR)')),
                        DropdownMenuItem(
                          value: 'USD',
                          child: Text('Dollar (USD)'),
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
                    emptyFallback: 'Voyageur',
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
                              decoration: const InputDecoration(
                                labelText: 'Payé par',
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
                                decoration: const InputDecoration(
                                  labelText: 'Date de la dépense',
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
                        'Partage du montant',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
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
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
