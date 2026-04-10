import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
import 'package:planzers/features/expenses/data/expense_group.dart';
import 'package:planzers/features/expenses/data/expenses_repository.dart';

const double _kGroupVisibilityColumnWidth = 48;

/// Create a new expense post or edit title + who can see it.
class ExpenseGroupEditorSheet extends ConsumerStatefulWidget {
  const ExpenseGroupEditorSheet({
    super.key,
    required this.tripId,
    required this.memberIds,
    required this.memberPublicLabels,
    this.existing,
    required this.onDone,
  });

  final String tripId;
  final List<String> memberIds;
  final Map<String, String> memberPublicLabels;
  final TripExpenseGroup? existing;
  final VoidCallback onDone;

  @override
  ConsumerState<ExpenseGroupEditorSheet> createState() =>
      _ExpenseGroupEditorSheetState();
}

class _ExpenseGroupEditorSheetState extends ConsumerState<ExpenseGroupEditorSheet> {
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
    final raw = ex?.visibleToMemberIds.toSet() ?? {};
    _visibleToIds = raw.isEmpty ? {...members} : raw.intersection(members);
    if (_visibleToIds.isEmpty && members.isNotEmpty) {
      _visibleToIds = {...members};
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
        const SnackBar(
          content: Text('Coche au moins une personne qui voit ce poste'),
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
          const SnackBar(content: Text('Poste mis à jour')),
        );
      } else {
        await repo.addExpenseGroup(
          tripId: widget.tripId,
          title: _titleController.text,
          visibleToMemberIds: _visibleToIds.toList(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Poste créé')),
        );
      }
      widget.onDone();
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
    final members = _cleanMembers;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEdit ? 'Modifier le poste' : 'Nouveau poste de dépenses',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nom du poste',
                  hintText: 'Ex. Commun, Cadeau, Weekend…',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obligatoire' : null,
              ),
              const SizedBox(height: 16),
              Text(
                'Qui voit ce poste',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
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
                        emptyFallback: 'Voyageur',
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                            child: Row(
                              children: [
                                const Expanded(child: Text('Voyageur')),
                                SizedBox(
                                  width: _kGroupVisibilityColumnWidth,
                                  child: Center(
                                    child: Tooltip(
                                      message: 'Voit le poste',
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
                onPressed: _saving || members.isEmpty ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEdit ? 'Enregistrer' : 'Créer le poste'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
