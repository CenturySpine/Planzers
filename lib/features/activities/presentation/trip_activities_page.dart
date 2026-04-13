import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/activities/data/activities_repository.dart';
import 'package:planzers/features/activities/data/trip_activity.dart';
import 'package:planzers/features/activities/presentation/trip_activity_detail_page.dart';
import 'package:planzers/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';

class TripActivitiesPage extends ConsumerWidget {
  const TripActivitiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = TripScope.of(context);
    final activitiesAsync = ref.watch(tripActivitiesStreamProvider(trip.id));

    return Scaffold(
      body: activitiesAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Activites',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Proposez des sorties : sport, shopping, visites, restaurants. '
                  'Chaque activite peut inclure un lien (apercu comme sur l\'apercu du voyage), '
                  'une adresse pour le trajet depuis le logement, et des commentaires.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            );
          }

          final sortedItems = [...items]
            ..sort((a, b) {
              if (a.done != b.done) {
                return a.done ? 1 : -1;
              }
              return b.createdAt.compareTo(a.createdAt);
            });

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: sortedItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final a = sortedItems[index];
              return _ActivityListTile(
                tripId: trip.id,
                activity: a,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Erreur: $e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'trip_activities_add',
        tooltip: 'Proposer',
        onPressed: () => _openAddActivitySheet(context, ref, trip.id),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ActivityListTile extends ConsumerWidget {
  const _ActivityListTile({
    required this.tripId,
    required this.activity,
  });

  final String tripId;
  final TripActivity activity;

  Future<void> _openDetail(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => TripActivityDetailPage(
          tripId: tripId,
          activityId: activity.id,
        ),
      ),
    );
  }

  Future<void> _setDone(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    try {
      await ref.read(activitiesRepositoryProvider).setActivityDone(
            tripId: tripId,
            activityId: activity.id,
            done: value,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label =
        activity.label.trim().isEmpty ? 'Sans titre' : activity.label.trim();

    return Card(
      color: activity.done ? const Color(0xFFDFF5E1) : null,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: activity.done,
              onChanged: (v) {
                if (v != null) _setDone(context, ref, v);
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openDetail(context),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        activity.category.categoryIcon,
                        size: 28,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      LinkPreviewThumbnail(preview: activity.linkPreview),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                const SnackBar(content: Text('Activite ajoutee')),
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
      return 'Lien invalide (ex: https://...)';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Le lien doit commencer par http(s)://';
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
        SnackBar(content: Text('Erreur: $e')),
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
              'Nouvelle activite',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Categorie',
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
                    label: Text(c.categoryLabelFr),
                    selected: _category == c,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _labelController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Libelle',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Libelle obligatoire';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _linkController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Lien (site, billetterie, ...)',
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
              decoration: const InputDecoration(
                labelText: 'Adresse du lieu (trajet depuis le voyage)',
                hintText: 'Pour calculer distance et duree en voiture',
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _commentsController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Commentaires',
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
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
