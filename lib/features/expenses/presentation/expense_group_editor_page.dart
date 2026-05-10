import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/expenses/data/expense_group.dart';
import 'package:planerz/features/expenses/data/expenses_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

const double _kGroupVisibilityColumnWidth = 48;

/// Create a new expense post or edit title + who can see it.
class ExpenseGroupEditorPage extends ConsumerStatefulWidget {
  const ExpenseGroupEditorPage({
    super.key,
    required this.tripId,
    required this.memberIds,
    required this.memberPublicLabels,
    this.existing,
  });

  final String tripId;
  final List<String> memberIds;
  final Map<String, String> memberPublicLabels;
  final TripExpenseGroup? existing;

  @override
  ConsumerState<ExpenseGroupEditorPage> createState() =>
      _ExpenseGroupEditorPageState();
}

class _ExpenseGroupEditorPageState extends ConsumerState<ExpenseGroupEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late Set<String> _visibleToIds;
  bool _saving = false;

  List<String> get _cleanMembers => widget.memberIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList();

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final members = _cleanMembers.toSet();
    final ex = widget.existing;
    _titleController = TextEditingController(text: ex?.title ?? '');
    if (ex == null) {
      final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
      if (myUid != null &&
          myUid.isNotEmpty &&
          members.contains(myUid)) {
        _visibleToIds = {myUid};
      } else {
        _visibleToIds = {};
      }
    } else {
      final raw = ex.visibleToMemberIds.toSet();
      _visibleToIds = raw.isEmpty ? {...members} : raw.intersection(members);
      if (_visibleToIds.isEmpty && members.isNotEmpty) {
        _visibleToIds = {...members};
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_visibleToIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.expenseGroupSelectAtLeastOne),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(expensesRepositoryProvider);
      if (_isEdit) {
        await repo.updateExpenseGroup(
          tripId: widget.tripId,
          groupId: widget.existing!.id,
          title: _titleController.text,
          visibleToMemberIds: _visibleToIds.toList(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.expenseGroupUpdated)),
        );
      } else {
        await repo.addExpenseGroup(
          tripId: widget.tripId,
          title: _titleController.text,
          visibleToMemberIds: _visibleToIds.toList(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.expenseGroupCreated)),
        );
      }
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
    final members = _cleanMembers;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.expenseGroupEditTitle : l10n.expenseGroupNewTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.expenseGroupNameLabel,
                  hintText: l10n.expenseGroupNameHint,
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.commonRequired : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.expenseGroupWhoSees,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (members.isEmpty)
                Text(
                  l10n.tripParticipantsEmpty,
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
                    final docsById = <String, Map<String, dynamic>>{};
                    for (final doc in snapshot.data?.docs ?? const []) {
                      docsById[doc.id] = doc.data();
                    }
                    final labels = <String, String>{};
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    for (final id in members) {
                      labels[id] = resolveTripMemberDisplayLabel(
                        memberId: id,
                        userData: docsById[id],
                        tripMemberPublicLabels: widget.memberPublicLabels,
                        currentUserId: uid,
                        emptyFallback: l10n.tripParticipantsTraveler,
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                            child: Row(
                              children: [
                                Expanded(child: Text(l10n.tripParticipantsTraveler)),
                                SizedBox(
                                  width: _kGroupVisibilityColumnWidth,
                                  child: Center(
                                    child: Tooltip(
                                      message: l10n.expenseGroupCanSee,
                                      child: Icon(
                                        Icons.visibility_outlined,
                                        size: 18,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          ...members.map((id) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 2,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      labels[id] ?? id,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(
                                    width: _kGroupVisibilityColumnWidth,
                                    child: Center(
                                      child: Checkbox(
                                        value: _visibleToIds.contains(id),
                                        onChanged: (checked) {
                                          setState(() {
                                            if (checked == true) {
                                              _visibleToIds.add(id);
                                            } else {
                                              _visibleToIds.remove(id);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ||
                        members.isEmpty ||
                        _visibleToIds.isEmpty
                    ? null
                    : _save,
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _isEdit ? l10n.commonSave : l10n.expenseGroupCreateAction,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
