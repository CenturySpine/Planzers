import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/expenses/data/expense.dart';
import 'package:planerz/features/expenses/data/expense_icon_catalog.dart';
import 'package:planerz/features/expenses/data/expenses_repository.dart';
import 'package:planerz/features/expenses/presentation/expense_format.dart';
import 'package:planerz/features/expenses/presentation/expense_icon_picker_sheet.dart';
import 'package:planerz/features/trips/data/participant_group.dart';
import 'package:planerz/features/trips/data/participant_groups_repository.dart';
import 'package:planerz/features/trips/presentation/trip_date_range_picker_sheet.dart';
import 'package:planerz/features/trips/presentation/trip_stay_form_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

Future<DateTime?> _pickExpenseDate(
  BuildContext context, {
  required DateTime initial,
}) async {
  final now = DateTime.now();
  final result = await showTripDateRangePickerSheet(
    context: context,
    style: neonTripDateRangePickerStyle(),
    initialStart: DateUtils.dateOnly(initial),
    initialEnd: DateUtils.dateOnly(initial),
    single: true,
    firstDate: DateTime(2000),
    lastDate: DateTime(now.year + 10, 12, 31),
  );
  return result?.start;
}

// --- Add expense ---

class AddExpensePage extends ConsumerStatefulWidget {
  const AddExpensePage({
    super.key,
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
  ConsumerState<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends ConsumerState<AddExpensePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  String _currency = kDefaultExpenseCurrency;
  String _iconKey = kDefaultExpenseIconKey;
  String? _paidBy;
  final Set<String> _participantIds = {};
  DateTime _expenseDate = DateTime.now();
  ExpenseSplitMode _splitMode = ExpenseSplitMode.equal;
  final Map<String, TextEditingController> _shareControllers = {};
  bool _saving = false;

  List<String> get _scopeMemberIds => widget.participantScopeMemberIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    final members = _scopeMemberIds;
    final myId = widget.currentUserMemberId;
    _paidBy = (myId != null && members.contains(myId))
        ? myId
        : (members.isNotEmpty ? members.first : null);
    _participantIds.addAll(members);
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in _shareControllers.values) {
      c.dispose();
    }
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String _label(String id, AppLocalizations l10n) {
    final base = widget.memberLabels[id] ?? l10n.tripParticipantsTraveler;
    if (widget.currentUserMemberId == id) {
      return '$base · ${l10n.commonMe.toLowerCase()}';
    }
    return base;
  }

  double _parsedTotal() =>
      double.tryParse(_amountController.text.trim().replaceAll(',', '.')) ?? 0;

  void _onSplitModeChanged(
    ExpenseSplitMode mode,
    Map<String, double> groupParts,
  ) {
    setState(() {
      _splitMode = mode;
      if (mode == ExpenseSplitMode.equal) {
        for (final c in _shareControllers.values) {
          c.dispose();
        }
        _shareControllers.clear();
      } else {
        final total = _parsedTotal();
        final ids = _participantIds.toList();
        final shares = weightedExpenseShareDrafts(
          amount: total,
          participantIds: ids,
          groupParts: groupParts,
        );
        for (final id in ids) {
          _shareControllers.putIfAbsent(
            id,
            () => TextEditingController(
              text: (shares[id] ?? 0.0).toStringAsFixed(2),
            ),
          );
        }
      }
    });
  }

  Map<String, double>? _parseCustomShares(double total) {
    final out = <String, double>{};
    for (final id in _participantIds) {
      final t = (_shareControllers[id]?.text ?? '').trim().replaceAll(',', '.');
      final n = double.tryParse(t);
      if (n == null || n < 0) return null;
      out[id] = n;
    }
    final sum = out.values.fold<double>(0, (a, b) => a + b);
    if ((sum - total).abs() > 0.02) return null;
    return out;
  }

  bool _isValid(AppLocalizations l10n) {
    if (_titleController.text.trim().isEmpty) return false;
    final total = _parsedTotal();
    if (total <= 0) return false;
    if (_participantIds.isEmpty) return false;
    if (_splitMode == ExpenseSplitMode.customAmounts) {
      return _parseCustomShares(total) != null;
    }
    return true;
  }

  Future<void> _pickDate() async {
    final picked = await _pickExpenseDate(context, initial: _expenseDate);
    if (picked == null || !mounted) return;
    setState(() => _expenseDate = picked);
  }

  Future<void> _save() async {
    if (_saving || !_isValid(AppLocalizations.of(context)!)) return;
    final l10n = AppLocalizations.of(context)!;
    final paidBy = _paidBy;
    if (paidBy == null || paidBy.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.expensesChoosePayer)),
      );
      return;
    }
    final amount = _parsedTotal();
    Map<String, double>? shares;
    if (_splitMode == ExpenseSplitMode.customAmounts) {
      shares = _parseCustomShares(amount);
      if (shares == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.expensesCustomAmountValidation)),
        );
        return;
      }
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
            icon: _iconKey,
            splitMode: _splitMode,
            participantShares: shares,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.expensesExpenseSaved)),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
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
    final groups =
        ref.watch(tripParticipantGroupsStreamProvider(widget.tripId)).asData?.value ??
            const <ParticipantGroup>[];
    final groupParts = {for (final g in groups) g.id: g.parts};
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      backgroundColor: NeonPalette.scaffoldBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.expensesNewExpenseTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Form(
                key: _formKey,
                child: _ExpenseFormBody(
                  titleController: _titleController,
                  amountController: _amountController,
                  iconKey: _iconKey,
                  currency: _currency,
                  paidBy: _paidBy,
                  expenseDate: _expenseDate,
                  splitMode: _splitMode,
                  participantIds: _participantIds,
                  shareControllers: _shareControllers,
                  members: members,
                  memberLabel: (id) => _label(id, l10n),
                  editing: true,
                  currentUserMemberId: widget.currentUserMemberId,
                  groupParts: groupParts,
                  locale: locale,
                  onIconPick: () async {
                    final picked = await showExpenseIconPickerSheet(
                      context,
                      currentKey: _iconKey,
                      title: l10n.expensesIconExpenseTitle,
                    );
                    if (picked != null) setState(() => _iconKey = picked);
                  },
                  onCurrencyChanged: (v) => setState(() => _currency = v),
                  onPaidByChanged: (v) => setState(() => _paidBy = v),
                  onPickDate: _pickDate,
                  onSplitModeChanged: (mode) =>
                      _onSplitModeChanged(mode, groupParts),
                  onParticipantToggled: (id, on) {
                    setState(() {
                      if (on) {
                        _participantIds.add(id);
                        if (_splitMode == ExpenseSplitMode.customAmounts) {
                          final shares = weightedExpenseShareDrafts(
                            amount: _parsedTotal(),
                            participantIds: _participantIds,
                            groupParts: groupParts,
                          );
                          _shareControllers[id] = TextEditingController(
                            text: (shares[id] ?? 0.0).toStringAsFixed(2),
                          );
                        }
                      } else {
                        _participantIds.remove(id);
                        _shareControllers.remove(id)?.dispose();
                      }
                    });
                  },
                  onShareChanged: () => setState(() {}),
                ),
              ),
            ),
          ),
          _ExpenseFormCta(
            label: l10n.expensesAddExpenseAction,
            icon: Icons.add,
            enabled: _isValid(l10n) && !_saving && members.isNotEmpty,
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

// --- Edit expense ---

enum _ExpenseDetailsMenuAction { edit, delete }

class ExpenseDetailsPage extends ConsumerStatefulWidget {
  const ExpenseDetailsPage({
    super.key,
    required this.tripId,
    required this.expense,
    required this.participantScopeMemberIds,
    required this.memberLabels,
    required this.currentUserMemberId,
    required this.canEditExpense,
    required this.canDeleteExpense,
  });

  final String tripId;
  final TripExpense expense;
  final List<String> participantScopeMemberIds;
  final Map<String, String> memberLabels;
  final String? currentUserMemberId;
  final bool canEditExpense;
  final bool canDeleteExpense;

  @override
  ConsumerState<ExpenseDetailsPage> createState() => _ExpenseDetailsPageState();
}

class _ExpenseDetailsPageState extends ConsumerState<ExpenseDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late String _currency;
  late String _iconKey;
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
    _iconKey = widget.expense.icon;
    final paid = widget.expense.paidBy.trim();
    _paidBy = scope.contains(paid) ? paid : null;
    _participantIds = widget.expense.participantIds
        .where((id) => scope.contains(id.trim()))
        .map((id) => id.trim())
        .toSet();
    if (_participantIds.isEmpty && scope.isNotEmpty) _participantIds = {...scope};
    if (_paidBy == null && scope.isNotEmpty) _paidBy = scope.first;
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
        _shareControllers[id] = TextEditingController(text: v.toStringAsFixed(2));
      }
    }
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in _shareControllers.values) {
      c.dispose();
    }
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String _label(String id, AppLocalizations l10n) {
    final base = widget.memberLabels[id] ?? l10n.tripParticipantsTraveler;
    if (widget.currentUserMemberId == id) {
      return '$base · ${l10n.commonMe.toLowerCase()}';
    }
    return base;
  }

  double _parsedTotal() =>
      double.tryParse(_amountController.text.trim().replaceAll(',', '.')) ??
      widget.expense.amount;

  void _onSplitModeChanged(
    ExpenseSplitMode mode,
    Map<String, double> groupParts,
  ) {
    setState(() {
      _splitMode = mode;
      if (mode == ExpenseSplitMode.equal) {
        for (final c in _shareControllers.values) {
          c.dispose();
        }
        _shareControllers.clear();
      } else {
        final total = _parsedTotal();
        final ids = _participantIds.toList();
        final shares = weightedExpenseShareDrafts(
          amount: total,
          participantIds: ids,
          groupParts: groupParts,
        );
        for (final id in ids) {
          _shareControllers.putIfAbsent(
            id,
            () => TextEditingController(
              text: (shares[id] ?? 0.0).toStringAsFixed(2),
            ),
          );
        }
      }
    });
  }

  Map<String, double>? _parseCustomShares(double total) {
    final out = <String, double>{};
    for (final id in _participantIds) {
      final t = (_shareControllers[id]?.text ?? '').trim().replaceAll(',', '.');
      final n = double.tryParse(t);
      if (n == null || n < 0) return null;
      out[id] = n;
    }
    final sum = out.values.fold<double>(0, (a, b) => a + b);
    if ((sum - total).abs() > 0.02) return null;
    return out;
  }

  bool _isValid(AppLocalizations l10n) {
    if (_titleController.text.trim().isEmpty) return false;
    final total = _parsedTotal();
    if (total <= 0) return false;
    if (_participantIds.isEmpty) return false;
    if (_splitMode == ExpenseSplitMode.customAmounts) {
      return _parseCustomShares(total) != null;
    }
    return true;
  }

  Future<void> _pickDate() async {
    final picked = await _pickExpenseDate(context, initial: _expenseDate);
    if (picked == null || !mounted) return;
    setState(() => _expenseDate = picked);
  }

  Future<void> _confirmDelete() async {
    if (_deleting) return;
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.expensesDeleteExpenseTitle),
        content: Text(l10n.expensesDeleteExpenseBody(
          widget.expense.title.trim().isEmpty
              ? l10n.activitiesUntitled
              : widget.expense.title,
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.commonDelete),
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
        SnackBar(content: Text(l10n.expensesExpenseDeleted)),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_isValid(AppLocalizations.of(context)!)) return;
    final l10n = AppLocalizations.of(context)!;
    final paidBy = _paidBy;
    if (paidBy == null || paidBy.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.expensesChoosePayer)),
      );
      return;
    }
    final amount = _parsedTotal();
    Map<String, double>? shares;
    if (_splitMode == ExpenseSplitMode.customAmounts) {
      shares = _parseCustomShares(amount);
      if (shares == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.expensesCustomAmountValidation)),
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
            icon: _iconKey,
            splitMode: _splitMode,
            participantShares: shares,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.expensesExpenseUpdated)),
      );
      setState(() => _editing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final members = widget.participantScopeMemberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    final groups =
        ref.watch(tripParticipantGroupsStreamProvider(widget.tripId)).asData?.value ??
            const <ParticipantGroup>[];
    final groupParts = {for (final g in groups) g.id: g.parts};
    final locale = Localizations.localeOf(context).toString();
    final canShowMenu = widget.canEditExpense || widget.canDeleteExpense;

    return Scaffold(
      backgroundColor: NeonPalette.scaffoldBackground,
      appBar: AppBar(
        title: Text(
          _editing ? l10n.expensesEditExpenseTitle : l10n.expensesExpenseDetailTitle,
        ),
        actions: [
          if (widget.canDeleteExpense && _editing)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              onPressed: _deleting ? null : _confirmDelete,
            ),
          if (canShowMenu && !_editing)
            PopupMenuButton<_ExpenseDetailsMenuAction>(
              enabled: !_saving && !_deleting,
              onSelected: (action) async {
                if (action == _ExpenseDetailsMenuAction.edit) {
                  if (widget.canEditExpense) setState(() => _editing = true);
                } else if (widget.canDeleteExpense) {
                  await _confirmDelete();
                }
              },
              itemBuilder: (ctx) => [
                if (widget.canEditExpense)
                  PopupMenuItem(
                    value: _ExpenseDetailsMenuAction.edit,
                    child: Text(l10n.commonEdit),
                  ),
                if (widget.canDeleteExpense)
                  PopupMenuItem(
                    value: _ExpenseDetailsMenuAction.delete,
                    child: Text(l10n.commonDelete),
                  ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Form(
                key: _formKey,
                child: _ExpenseFormBody(
                  titleController: _titleController,
                  amountController: _amountController,
                  iconKey: _iconKey,
                  currency: _currency,
                  paidBy: _paidBy,
                  expenseDate: _expenseDate,
                  splitMode: _splitMode,
                  participantIds: _participantIds,
                  shareControllers: _shareControllers,
                  members: members,
                  memberLabel: (id) => _label(id, l10n),
                  editing: _editing,
                  currentUserMemberId: widget.currentUserMemberId,
                  groupParts: groupParts,
                  locale: locale,
                  onIconPick: _editing
                      ? () async {
                          final picked = await showExpenseIconPickerSheet(
                            context,
                            currentKey: _iconKey,
                            title: l10n.expensesIconExpenseTitle,
                          );
                          if (picked != null) setState(() => _iconKey = picked);
                        }
                      : null,
                  onCurrencyChanged:
                      _editing ? (v) => setState(() => _currency = v) : null,
                  onPaidByChanged: _editing ? (v) => setState(() => _paidBy = v) : null,
                  onPickDate: _editing ? _pickDate : null,
                  onSplitModeChanged: _editing
                      ? (mode) => _onSplitModeChanged(mode, groupParts)
                      : null,
                  onParticipantToggled: _editing
                      ? (id, on) {
                          setState(() {
                            if (on) {
                              _participantIds.add(id);
                              if (_splitMode == ExpenseSplitMode.customAmounts) {
                                final shares = weightedExpenseShareDrafts(
                                  amount: _parsedTotal(),
                                  participantIds: _participantIds,
                                  groupParts: groupParts,
                                );
                                _shareControllers[id] = TextEditingController(
                                  text: (shares[id] ?? 0.0).toStringAsFixed(2),
                                );
                              }
                            } else {
                              _participantIds.remove(id);
                              _shareControllers.remove(id)?.dispose();
                            }
                          });
                        }
                      : null,
                  onShareChanged: () => setState(() {}),
                ),
              ),
            ),
          ),
          if (_editing)
            _ExpenseFormCta(
              label: l10n.expensesSaveExpenseChanges,
              icon: Icons.check,
              enabled: _isValid(l10n) && !_saving && members.isNotEmpty,
              loading: _saving,
              onPressed: _save,
            ),
        ],
      ),
    );
  }
}

// --- Shared form widgets ---

class _ExpenseFormBody extends StatelessWidget {
  const _ExpenseFormBody({
    required this.titleController,
    required this.amountController,
    required this.iconKey,
    required this.currency,
    required this.paidBy,
    required this.expenseDate,
    required this.splitMode,
    required this.participantIds,
    required this.shareControllers,
    required this.members,
    required this.memberLabel,
    required this.editing,
    required this.currentUserMemberId,
    required this.groupParts,
    required this.locale,
    required this.onIconPick,
    required this.onCurrencyChanged,
    required this.onPaidByChanged,
    required this.onPickDate,
    required this.onSplitModeChanged,
    required this.onParticipantToggled,
    required this.onShareChanged,
  });

  final TextEditingController titleController;
  final TextEditingController amountController;
  final String iconKey;
  final String currency;
  final String? paidBy;
  final DateTime expenseDate;
  final ExpenseSplitMode splitMode;
  final Set<String> participantIds;
  final Map<String, TextEditingController> shareControllers;
  final List<String> members;
  final String Function(String id) memberLabel;
  final bool editing;
  final String? currentUserMemberId;
  final Map<String, double> groupParts;
  final String locale;
  final Future<void> Function()? onIconPick;
  final ValueChanged<String>? onCurrencyChanged;
  final ValueChanged<String?>? onPaidByChanged;
  final VoidCallback? onPickDate;
  final ValueChanged<ExpenseSplitMode>? onSplitModeChanged;
  final void Function(String id, bool on)? onParticipantToggled;
  final VoidCallback onShareChanged;

  double get _total =>
      double.tryParse(amountController.text.trim().replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final active = members.where(participantIds.contains).toList();
    final totalParts =
        active.fold<double>(0, (s, id) => s + (groupParts[id] ?? 1.0));

    double remain = 0;
    if (splitMode == ExpenseSplitMode.customAmounts) {
      var sum = 0.0;
      for (final id in active) {
        final t = (shareControllers[id]?.text ?? '').trim().replaceAll(',', '.');
        sum += double.tryParse(t) ?? 0;
      }
      remain = _total - sum;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (members.isEmpty)
          Text(
            l10n.expensesNoAllowedTravelerInPostForShare,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconPickButton(
              iconKey: iconKey,
              enabled: editing && onIconPick != null,
              onTap: onIconPick,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel(text: l10n.activitiesLabel, required: true),
                  TextFormField(
                    controller: titleController,
                    readOnly: !editing,
                    decoration: _inputDecoration(hint: l10n.activitiesLabel),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? l10n.commonRequired : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _FieldLabel(text: l10n.expensesAmountLabel, required: true),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: NeonPalette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NeonPalette.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: amountController,
                  readOnly: !editing,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '0,00',
                  ),
                  onChanged: editing ? (_) => onShareChanged() : null,
                ),
              ),
              _CurrencyToggle(
                currency: currency,
                enabled: editing,
                onChanged: onCurrencyChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _PickerTile(
                  enabled: editing,
                  onTap: editing && onPaidByChanged != null
                      ? () => _showPayerSheet(context)
                      : null,
                  label: l10n.expensesPaidByLabel,
                  value: paidBy != null ? memberLabel(paidBy!) : '—',
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: NeonPalette.primarySoft,
                    child: Text(
                      (paidBy != null ? memberLabel(paidBy!) : '?')
                          .characters
                          .first
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: NeonPalette.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickerTile(
                  enabled: editing,
                  onTap: onPickDate,
                  label: l10n.expensesDateLabel,
                  value: formatExpenseDateShort(expenseDate, locale),
                  leading: const Icon(Icons.calendar_today_outlined, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.expensesAmountSplit,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (editing && onSplitModeChanged != null)
              _SplitToggle(
                splitMode: splitMode,
                onChanged: onSplitModeChanged!,
              )
            else
              Text(
                splitMode == ExpenseSplitMode.equal
                    ? l10n.expensesSplitEqual
                    : l10n.expensesSplitCustomAmounts,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: NeonPalette.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...[
          for (final id in members)
            _ParticipantRow(
              id: id,
              label: memberLabel(id),
              selected: participantIds.contains(id),
              editing: editing,
              splitMode: splitMode,
              shareText: splitMode == ExpenseSplitMode.equal
                  ? (participantIds.contains(id) && totalParts > 0
                      ? formatExpenseMoney(
                          currency,
                          _total * (groupParts[id] ?? 1.0) / totalParts,
                          locale: locale,
                        )
                      : '—')
                  : null,
              shareController: shareControllers[id],
              currency: currency,
              onToggle: onParticipantToggled == null
                  ? null
                  : () => onParticipantToggled!(
                        id,
                        !participantIds.contains(id),
                      ),
              onShareChanged: onShareChanged,
            ),
        ],
        const SizedBox(height: 8),
        if (splitMode == ExpenseSplitMode.customAmounts)
          _RemainBanner(remain: remain, currency: currency, locale: locale)
        else if (active.isNotEmpty)
          _EqualSummaryBanner(
            count: active.length,
            amount: formatExpenseMoney(
              currency,
              totalParts > 0 ? _total / totalParts : 0,
              locale: locale,
            ),
          ),
      ],
    );
  }

  Future<void> _showPayerSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final sortedMembers = members.toList()
      ..sort(
        (a, b) => memberLabel(a)
            .toLowerCase()
            .compareTo(memberLabel(b).toLowerCase()),
      );
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.expensesPaidByLabel,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final id in sortedMembers)
              ListTile(
                title: Text(memberLabel(id)),
                onTap: () => Navigator.pop(ctx, id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onPaidByChanged?.call(picked);
  }
}

class _IconPickButton extends StatelessWidget {
  const _IconPickButton({
    required this.iconKey,
    required this.enabled,
    required this.onTap,
  });

  final String iconKey;
  final bool enabled;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: NeonPalette.accentSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                expenseIconForExpense(iconKey),
                size: 28,
                color: NeonPalette.accent,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.expensesChooseIcon,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: NeonPalette.accent,
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, this.required = false});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text.rich(
        TextSpan(
          text: text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: NeonPalette.deep,
              ),
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: NeonPalette.accent),
              ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration({String? hint}) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: NeonPalette.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NeonPalette.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NeonPalette.divider),
      ),
    );

class _CurrencyToggle extends StatelessWidget {
  const _CurrencyToggle({
    required this.currency,
    required this.enabled,
    required this.onChanged,
  });

  final String currency;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget chip(String code, String label) {
      final on = currency == code;
      return Material(
        color: on ? NeonPalette.accent : NeonPalette.segmentTrack,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled && onChanged != null ? () => onChanged!(code) : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: on ? Colors.white : NeonPalette.deep,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('EUR', l10n.expensesCurrencyEuro),
        const SizedBox(width: 6),
        chip('USD', l10n.expensesCurrencyDollar),
      ],
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.value,
    required this.leading,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final String value;
  final Widget leading;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NeonPalette.divider, width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: Center(child: leading),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: NeonPalette.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                            color: NeonPalette.deep,
                          ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                const Icon(Icons.expand_more, color: NeonPalette.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitToggle extends StatelessWidget {
  const _SplitToggle({required this.splitMode, required this.onChanged});

  final ExpenseSplitMode splitMode;
  final ValueChanged<ExpenseSplitMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget btn(ExpenseSplitMode mode, IconData icon, String label) {
      final on = splitMode == mode;
      return Expanded(
        child: Material(
          color: on ? NeonPalette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => onChanged(mode),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: on ? Colors.white : NeonPalette.deep),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: on ? Colors.white : NeonPalette.deep,
                      ),
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
      width: 220,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: NeonPalette.segmentTrack,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          btn(ExpenseSplitMode.equal, Icons.drag_handle, l10n.expensesSplitEqual),
          btn(ExpenseSplitMode.customAmounts, Icons.tune, l10n.expensesSplitCustomAmounts),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.id,
    required this.label,
    required this.selected,
    required this.editing,
    required this.splitMode,
    required this.currency,
    this.shareText,
    this.shareController,
    this.onToggle,
    this.onShareChanged,
  });

  final String id;
  final String label;
  final bool selected;
  final bool editing;
  final ExpenseSplitMode splitMode;
  final String currency;
  final String? shareText;
  final TextEditingController? shareController;
  final VoidCallback? onToggle;
  final VoidCallback? onShareChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? NeonPalette.surface : NeonPalette.segmentTrack.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: editing ? onToggle : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _CheckDot(checked: selected, enabled: editing),
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: NeonPalette.primarySoft,
                  child: Text(
                    label.characters.first.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: NeonPalette.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? NeonPalette.deep : NeonPalette.onSurfaceVariant,
                    ),
                  ),
                ),
                if (splitMode == ExpenseSplitMode.equal)
                  Text(
                    shareText ?? '—',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  )
                else if (selected && shareController != null)
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: shareController,
                      readOnly: !editing,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      textAlign: TextAlign.end,
                      onChanged: editing ? (_) => onShareChanged?.call() : null,
                      decoration: InputDecoration(
                        isDense: true,
                        suffixText: currency == 'USD' ? r'$' : '€',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckDot extends StatelessWidget {
  const _CheckDot({required this.checked, required this.enabled});
  final bool checked;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: checked ? NeonPalette.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked ? NeonPalette.accent : NeonPalette.outline,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }
}

class _RemainBanner extends StatelessWidget {
  const _RemainBanner({
    required this.remain,
    required this.currency,
    required this.locale,
  });

  final double remain;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ok = remain.abs() < 0.005;
    final over = remain < -0.005;
    final bg = ok
        ? Color.lerp(NeonPalette.surface, NeonPalette.success, 0.12)!
        : over
            ? Color.lerp(NeonPalette.surface, NeonPalette.accent, 0.12)!
            : NeonPalette.segmentTrack;
    final fg = ok
        ? NeonPalette.success
        : over
            ? NeonPalette.accent
            : NeonPalette.onSurfaceVariant;
    final icon = ok
        ? Icons.check_circle_outline
        : over
            ? Icons.error_outline
            : Icons.pending_outlined;
    final text = ok
        ? l10n.expensesSplitComplete
        : over
            ? l10n.expensesSplitOver
            : l10n.expensesRemainToSplit;
    final amt = over
        ? formatExpenseMoney(currency, -remain, locale: locale)
        : formatExpenseMoney(currency, remain < 0 ? 0 : remain, locale: locale);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600))),
          Text(
            amt,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _EqualSummaryBanner extends StatelessWidget {
  const _EqualSummaryBanner({required this.count, required this.amount});
  final int count;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NeonPalette.primaryTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NeonPalette.dateBorderSet),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_outlined, size: 18, color: NeonPalette.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.expensesEqualSplitSummary(count, amount),
              style: const TextStyle(
                color: NeonPalette.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseFormCta extends StatelessWidget {
  const _ExpenseFormCta({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: enabled && !loading ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: NeonPalette.accent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}
