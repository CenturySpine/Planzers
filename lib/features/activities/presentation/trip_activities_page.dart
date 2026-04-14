import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/app/theme/planzers_colors.dart';
import 'package:planzers/core/notifications/notification_center_repository.dart';
import 'package:planzers/core/notifications/notification_channel.dart';
import 'package:planzers/features/activities/data/activities_repository.dart';
import 'package:planzers/features/activities/data/trip_activity.dart';
import 'package:planzers/features/activities/presentation/trip_activity_detail_page.dart';
import 'package:planzers/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';

class TripActivitiesPage extends ConsumerStatefulWidget {
  const TripActivitiesPage({super.key});

  @override
  ConsumerState<TripActivitiesPage> createState() => _TripActivitiesPageState();
}

class _TripActivitiesPageState extends ConsumerState<TripActivitiesPage> {
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
      unawaited(
        _notificationCenter.clearOpenChannel(
              tripId: tripId,
            ),
      );
    }
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
    final trip = TripScope.of(context);
    _syncPresenceIfNeeded(trip.id);
    final activitiesAsync = ref.watch(tripActivitiesStreamProvider(trip.id));

    return Scaffold(
      body: activitiesAsync.when(
        data: (items) {
          _markActivitiesAsReadIfNeeded(tripId: trip.id, items: items);
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
                  'Proposez des sorties : sport, randonnees, shopping, visites, restaurants. '
                  'Chaque activite peut inclure un lien (apercu comme sur l\'apercu du voyage), '
                  'une adresse pour le trajet depuis le logement, et des commentaires.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            );
          }

          final listEntries = _buildActivitiesEntries(items);

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: listEntries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = listEntries[index];
              if (entry.dayLabel != null) {
                return _ActivityDayPill(label: entry.dayLabel!);
              }
              return _ActivityListTile(
                tripId: trip.id,
                activity: entry.activity!,
                tripMemberPublicLabels: trip.memberPublicLabels,
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

class _ActivityListTile extends StatelessWidget {
  const _ActivityListTile({
    required this.tripId,
    required this.activity,
    required this.tripMemberPublicLabels,
  });

  final String tripId;
  final TripActivity activity;
  final Map<String, String> tripMemberPublicLabels;

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

  @override
  Widget build(BuildContext context) {
    final label =
        activity.label.trim().isEmpty ? 'Sans titre' : activity.label.trim();

    return Card(
      color: activity.done ? context.planzersColors.successContainer : null,
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
                      'Proposé par ${_creatorLabel(activity)}',
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

  String _creatorLabel(TripActivity activity) {
    final id = activity.createdBy.trim();
    if (id.isEmpty) return 'inconnu';
    return tripMemberPublicLabels[id]?.trim().isNotEmpty == true
        ? tripMemberPublicLabels[id]!.trim()
        : id;
  }
}

List<_ActivitiesListEntry> _buildActivitiesEntries(List<TripActivity> items) {
  final toPlan = items
      .where((a) => !a.done && a.plannedAt == null)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final dated = items
      .where((a) => a.done || a.plannedAt != null)
      .toList()
    ..sort((a, b) {
      final aDate = _activityDateForGrouping(a);
      final bDate = _activityDateForGrouping(b);
      final byDay = bDate.compareTo(aDate);
      if (byDay != 0) return byDay;
      return b.createdAt.compareTo(a.createdAt);
    });

  final entries = <_ActivitiesListEntry>[];

  if (toPlan.isNotEmpty) {
    entries.add(const _ActivitiesListEntry.separator('A planifier'));
    entries.addAll(toPlan.map(_ActivitiesListEntry.activity));
  }

  DateTime? previousDay;
  for (final activity in dated) {
    final date = _activityDateForGrouping(activity).toLocal();
    final day = DateTime(date.year, date.month, date.day);
    if (previousDay == null || previousDay != day) {
      entries.add(_ActivitiesListEntry.separator(_dayLabelFor(day)));
      previousDay = day;
    }
    entries.add(_ActivitiesListEntry.activity(activity));
  }
  return entries;
}

DateTime _activityDateForGrouping(TripActivity activity) {
  return activity.plannedAt ?? activity.doneAt ?? activity.createdAt;
}

String _dayLabelFor(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == today) return "Aujourd'hui";
  if (day == yesterday) return 'Hier';
  return DateFormat('d MMM yyyy', 'fr_FR').format(day);
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
  bool _isLocked = false;
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
            isLocked: _isLocked,
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
                    onSelected:
                        _saving ? null : (_) => setState(() => _category = c),
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
            SwitchListTile(
              value: _isLocked,
              onChanged: _saving ? null : (value) => setState(() => _isLocked = value),
              title: const Text('Activite verrouillee'),
              subtitle: const Text(
                'Si activee, seuls les admins peuvent modifier cette activite.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
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
