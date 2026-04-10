import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
import 'package:planzers/features/expenses/data/expense.dart';
import 'package:planzers/features/expenses/data/expenses_repository.dart';
import 'package:planzers/features/expenses/domain/expense_settlement.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';

class TripExpensesPage extends ConsumerWidget {
  const TripExpensesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = TripScope.of(context);
    final expensesAsync = ref.watch(tripExpensesStreamProvider(trip.id));

    return Scaffold(
      body: expensesAsync.when(
        data: (expenses) {
          return _TripExpensesBody(
            tripId: trip.id,
            memberIds: trip.memberIds,
            memberPublicLabels: trip.memberPublicLabels,
            expenses: expenses,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddExpenseSheet(
              context,
              ref,
              trip.id,
              trip.memberIds,
              trip.memberPublicLabels,
            ),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une dépense'),
      ),
    );
  }

  static Future<void> _openAddExpenseSheet(
    BuildContext context,
    WidgetRef ref,
    String tripId,
    List<String> memberIds,
    Map<String, String> memberPublicLabels,
  ) async {
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
          memberIds: memberIds,
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
    required this.expenses,
  });

  final String tripId;
  final List<String> memberIds;
  final Map<String, String> memberPublicLabels;
  final List<TripExpense> expenses;

  @override
  Widget build(BuildContext context) {
    final cleanMemberIds = memberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();

    final balances = computeBalances(expenses);
    final transfers = suggestTransfers(balances);

    if (cleanMemberIds.isEmpty) {
      return _buildScrollView(context, const {}, balances, transfers);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: cleanMemberIds)
          .snapshots(),
      builder: (context, snapshot) {
        final labels = _labelsFromUserSnapshot(
          snapshot.data,
          cleanMemberIds,
          memberPublicLabels: memberPublicLabels,
          currentUserId: FirebaseAuth.instance.currentUser?.uid,
        );

        return _buildScrollView(context, labels, balances, transfers);
      },
    );
  }

  Widget _buildScrollView(
    BuildContext context,
    Map<String, String> labels,
    BalancesByCurrency balances,
    List<SuggestedTransfer> transfers,
  ) {
    return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Dépenses',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: _SettlementSection(
                  balancesByCurrency: balances,
                  transfers: transfers,
                  memberLabels: labels,
                ),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.only(top: 8),
              sliver: SliverToBoxAdapter(child: Divider(height: 1)),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Opérations',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            if (expenses.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Aucune dépense pour le moment. Utilise le bouton ci-dessous pour en ajouter une.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: expenses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final expense = expenses[index];
                    return _ExpenseCard(
                      tripId: tripId,
                      expense: expense,
                      memberIds: memberIds,
                      memberLabels: labels,
                    );
                  },
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 88)),
          ],
        );
  }
}

Map<String, String> _labelsFromUserSnapshot(
  QuerySnapshot<Map<String, dynamic>>? snapshot,
  List<String> memberIds, {
  String? currentUserId,
  Map<String, String> memberPublicLabels = const {},
}) {
  final docsById = <String, Map<String, dynamic>>{};
  for (final doc in snapshot?.docs ?? const []) {
    docsById[doc.id] = doc.data();
  }

  final labels = <String, String>{};
  for (final memberId in memberIds) {
    labels[memberId] = resolveTripMemberDisplayLabel(
      memberId: memberId,
      userData: docsById[memberId],
      tripMemberPublicLabels: memberPublicLabels,
      currentUserId: currentUserId,
      emptyFallback: 'Voyageur',
    );
  }
  return labels;
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

class _SettlementSection extends StatelessWidget {
  const _SettlementSection({
    required this.balancesByCurrency,
    required this.transfers,
    required this.memberLabels,
  });

  final BalancesByCurrency balancesByCurrency;
  final List<SuggestedTransfer> transfers;
  final Map<String, String> memberLabels;

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
                        : 'Tout est équilibré.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  )
                else
                  ...transfers.map((t) {
                    final fromL = memberLabels[t.fromUserId] ?? 'Voyageur';
                    final toL = memberLabels[t.toUserId] ?? 'Voyageur';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_forward, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$fromL donne ${_formatMoney(t.currency, t.amount)} à $toL',
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

class _ExpenseCard extends ConsumerStatefulWidget {
  const _ExpenseCard({
    required this.tripId,
    required this.expense,
    required this.memberIds,
    required this.memberLabels,
  });

  final String tripId;
  final TripExpense expense;
  final List<String> memberIds;
  final Map<String, String> memberLabels;

  @override
  ConsumerState<_ExpenseCard> createState() => _ExpenseCardState();
}

class _ExpenseCardState extends ConsumerState<_ExpenseCard> {
  bool _deleting = false;

  Future<void> _openDetails() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ExpenseDetailsPage(
          tripId: widget.tripId,
          expense: widget.expense,
          memberIds: widget.memberIds,
          memberLabels: widget.memberLabels,
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dépense supprimée')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    final paidByLabel = widget.memberLabels[e.paidBy] ?? 'Voyageur';
    final participantLabels = e.participantIds
        .map((id) => widget.memberLabels[id] ?? 'Voyageur')
        .join(', ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openDetails,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title.isEmpty ? 'Sans titre' : e.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatMoney(e.currency, e.amount),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    onPressed: _deleting ? null : _confirmDelete,
                    icon: _deleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Date : ${_formatExpenseDate(e.expenseDate)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Payé par $paidByLabel',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Partagée entre : $participantLabels',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    required this.memberIds,
    required this.memberLabels,
  });

  final String tripId;
  final TripExpense expense;
  final List<String> memberIds;
  final Map<String, String> memberLabels;

  @override
  ConsumerState<_ExpenseDetailsPage> createState() => _ExpenseDetailsPageState();
}

class _ExpenseDetailsPageState extends ConsumerState<_ExpenseDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late String _currency;
  late String? _paidBy;
  late Set<String> _participantIds;
  late DateTime _expenseDate;
  bool _editing = false;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.expense.title);
    _amountController = TextEditingController(
      text: widget.expense.amount.toStringAsFixed(2),
    );
    _currency = widget.expense.currency;
    _paidBy = widget.expense.paidBy;
    _participantIds = widget.expense.participantIds.toSet();
    _expenseDate = DateTime(
      widget.expense.expenseDate.year,
      widget.expense.expenseDate.month,
      widget.expense.expenseDate.day,
    );
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
    if (_participantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coche au moins un participant')),
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
    final members = widget.memberIds
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
              if (!_editing)
                Text(
                  'Lecture seule. Ouvre le menu en haut à droite pour modifier ou supprimer.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              if (!_editing) const SizedBox(height: 12),
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
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                readOnly: !_editing,
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(_currency),
                initialValue: _currency,
                decoration: const InputDecoration(
                  labelText: 'Devise',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'EUR', child: Text('Euro (EUR)')),
                  DropdownMenuItem(value: 'USD', child: Text('Dollar (USD)')),
                ],
                onChanged: !_editing
                    ? null
                    : (v) {
                  if (v != null) setState(() => _currency = v);
                },
              ),
              const SizedBox(height: 12),
              InkWell(
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(_paidBy ?? ''),
                initialValue:
                    _paidBy != null && members.contains(_paidBy) ? _paidBy : null,
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
                onChanged: _editing ? (v) => setState(() => _paidBy = v) : null,
              ),
              const SizedBox(height: 16),
              Text(
                'Partagée entre',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ...members.map((id) {
                return CheckboxListTile(
                  value: _participantIds.contains(id),
                  onChanged: _editing
                      ? (checked) {
                          setState(() {
                            if (checked == true) {
                              _participantIds.add(id);
                            } else {
                              _participantIds.remove(id);
                            }
                          });
                        }
                      : null,
                  title: Text(
                    widget.memberLabels[id] ?? id,
                    overflow: TextOverflow.ellipsis,
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }),
              const SizedBox(height: 24),
              if (_editing)
                FilledButton(
                  onPressed: _saving ? null : _save,
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
    required this.memberIds,
    required this.memberPublicLabels,
    required this.onSubmit,
  });

  final String tripId;
  final List<String> memberIds;
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

  List<String> get _cleanMemberIds => widget.memberIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final members = _cleanMemberIds;
    _paidBy = (myUid != null && members.contains(myUid)) ? myUid : (members.isNotEmpty ? members.first : null);
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
    final members = _cleanMemberIds;

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
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey<String>(_currency),
              initialValue: _currency,
              decoration: const InputDecoration(
                labelText: 'Devise',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'EUR', child: Text('Euro (EUR)')),
                DropdownMenuItem(value: 'USD', child: Text('Dollar (USD)')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _currency = v);
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickExpenseDate,
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
            const SizedBox(height: 12),
            if (members.isEmpty)
              Text(
                'Aucun voyageur sur ce voyage.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              )
            else
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where(FieldPath.documentId, whereIn: members)
                    .snapshots(),
                builder: (context, snapshot) {
                  final labels = _labelsFromUserSnapshot(
                    snapshot.data,
                    members,
                    memberPublicLabels: widget.memberPublicLabels,
                    currentUserId: FirebaseAuth.instance.currentUser?.uid,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>(_paidBy ?? ''),
                        initialValue: _paidBy != null &&
                                members.contains(_paidBy)
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
                      const SizedBox(height: 16),
                      Text(
                        'Partagée entre',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ...members.map((id) {
                        return CheckboxListTile(
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
                          title: Text(
                            labels[id] ?? id,
                            overflow: TextOverflow.ellipsis,
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      }),
                    ],
                  );
                },
              ),
            const SizedBox(height: 24),
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
