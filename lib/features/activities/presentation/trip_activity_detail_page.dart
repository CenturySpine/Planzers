import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/activities/data/activities_repository.dart';
import 'package:planzers/features/activities/data/trip_activity.dart';
import 'package:planzers/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planzers/features/trips/presentation/open_address_in_google_maps.dart';

extension TripActivityCategoryPresentation on TripActivityCategory {
  IconData get categoryIcon => switch (this) {
        TripActivityCategory.sport => Icons.sports_soccer_outlined,
        TripActivityCategory.shopping => Icons.shopping_bag_outlined,
        TripActivityCategory.visit => Icons.museum_outlined,
        TripActivityCategory.restaurant => Icons.restaurant_outlined,
      };

  String get categoryLabelFr => switch (this) {
        TripActivityCategory.sport => 'Sport',
        TripActivityCategory.shopping => 'Shopping',
        TripActivityCategory.visit => 'Visite',
        TripActivityCategory.restaurant => 'Restaurant',
      };
}

class TripActivityDetailPage extends ConsumerStatefulWidget {
  const TripActivityDetailPage({
    super.key,
    required this.tripId,
    required this.activityId,
  });

  final String tripId;
  final String activityId;

  @override
  ConsumerState<TripActivityDetailPage> createState() =>
      _TripActivityDetailPageState();
}

class _TripActivityDetailPageState extends ConsumerState<TripActivityDetailPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _linkController;
  late final TextEditingController _addressController;
  late final TextEditingController _commentsController;
  TripActivityCategory _category = TripActivityCategory.visit;
  bool _editing = false;
  bool _saving = false;
  bool _deleting = false;
  TripActivity? _lastSyncedActivity;

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

  bool _sameEditableFields(TripActivity? prev, TripActivity next) {
    if (prev == null) return false;
    return prev.label == next.label &&
        prev.linkUrl == next.linkUrl &&
        prev.address == next.address &&
        prev.freeComments == next.freeComments &&
        prev.category == next.category &&
        prev.done == next.done;
  }

  void _syncControllersWhenIdle(TripActivity activity) {
    if (_editing || _saving) return;
    if (_sameEditableFields(_lastSyncedActivity, activity)) return;
    _lastSyncedActivity = activity;
    _labelController.text = activity.label;
    _linkController.text = activity.linkUrl;
    _addressController.text = activity.address;
    _commentsController.text = activity.freeComments;
    _category = activity.category;
  }

  void _applyActivity(TripActivity activity) {
    _labelController.text = activity.label;
    _linkController.text = activity.linkUrl;
    _addressController.text = activity.address;
    _commentsController.text = activity.freeComments;
    _category = activity.category;
    _lastSyncedActivity = activity;
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

  Future<void> _save() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _saving = true);
    try {
      await ref.read(activitiesRepositoryProvider).updateActivity(
            tripId: widget.tripId,
            activityId: widget.activityId,
            label: _labelController.text,
            category: _category,
            linkUrl: _linkController.text,
            address: _addressController.text,
            freeComments: _commentsController.text,
          );
      if (!mounted) return;
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activite mise a jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancelEdit(TripActivity activity) {
    _applyActivity(activity);
    setState(() => _editing = false);
  }

  Future<void> _confirmAndDelete(TripActivity activity) async {
    if (_deleting) return;
    final label =
        activity.label.trim().isEmpty ? 'Sans titre' : activity.label.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette activite ?'),
        content: Text('« $label » sera supprimee.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = true);
    try {
      await ref.read(activitiesRepositoryProvider).deleteActivity(
            tripId: widget.tripId,
            activityId: widget.activityId,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Activite supprimee')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final docRef = FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId.trim())
        .collection('activities')
        .doc(widget.activityId.trim());

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final doc = snapshot.data;
        if (doc == null || !doc.exists) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Activite introuvable.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final activity = TripActivity.fromDoc(doc);
        _syncControllersWhenIdle(activity);

        final createdBy = activity.createdBy.trim();
        final canEdit =
            myUid != null && myUid.isNotEmpty && createdBy == myUid;

        return Scaffold(
          appBar: AppBar(
            title: Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        activity.category.categoryIcon,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  TextSpan(
                    text: activity.label.trim().isEmpty
                        ? 'Sans titre'
                        : activity.label.trim(),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (canEdit && !_editing) ...[
                IconButton(
                  tooltip: 'Modifier',
                  onPressed: _deleting
                      ? null
                      : () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  onPressed: _deleting
                      ? null
                      : () => _confirmAndDelete(activity),
                  icon: _deleting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                ),
              ],
              if (canEdit && _editing) ...[
                IconButton(
                  tooltip: 'Annuler',
                  onPressed: _saving ? null : () => _cancelEdit(activity),
                  icon: const Icon(Icons.close),
                ),
                IconButton(
                  tooltip: 'Enregistrer',
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                ),
              ],
            ],
          ),
          body: _editing
              ? _EditBody(
                  formKey: _formKey,
                  labelController: _labelController,
                  linkController: _linkController,
                  addressController: _addressController,
                  commentsController: _commentsController,
                  category: _category,
                  onCategoryChanged: _saving
                      ? null
                      : (c) => setState(() => _category = c),
                  activity: activity,
                  validateOptionalUrl: _validateOptionalUrl,
                )
              : _ReadBody(
                  tripId: widget.tripId,
                  activity: activity,
                ),
        );
      },
    );
  }
}

class _ReadBody extends ConsumerWidget {
  const _ReadBody({
    required this.tripId,
    required this.activity,
  });

  final String tripId;
  final TripActivity activity;

  Future<void> _toggleDone(WidgetRef ref, BuildContext context, bool value) async {
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CheckboxListTile(
          value: activity.done,
          onChanged: (v) {
            if (v != null) _toggleDone(ref, context, v);
          },
          title: const Text('Faite'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        if (activity.linkUrl.trim().isNotEmpty) ...[
          LinkPreviewCardFromFirestore(
            url: activity.linkUrl.trim(),
            preview: activity.linkPreview,
          ),
          const SizedBox(height: 16),
        ],
        if (activity.address.trim().isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adresse du lieu',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          activity.address.trim(),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ouvrir la localisation',
                        onPressed: () => openAddressInGoogleMaps(
                              context,
                              activity.address,
                            ),
                        icon: const Icon(Icons.location_on_outlined),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        visualDensity: VisualDensity.compact,
                        splashRadius: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.directions_car_outlined,
                        size: 22,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Depuis le logement (voiture)',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _activityDrivingRouteBodyText(activity),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Commentaires',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  activity.freeComments.trim().isEmpty
                      ? '—'
                      : activity.freeComments.trim(),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EditBody extends StatefulWidget {
  const _EditBody({
    required this.formKey,
    required this.labelController,
    required this.linkController,
    required this.addressController,
    required this.commentsController,
    required this.category,
    required this.onCategoryChanged,
    required this.activity,
    required this.validateOptionalUrl,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController labelController;
  final TextEditingController linkController;
  final TextEditingController addressController;
  final TextEditingController commentsController;
  final TripActivityCategory category;
  final void Function(TripActivityCategory)? onCategoryChanged;
  final TripActivity activity;
  final String? Function(String?) validateOptionalUrl;

  @override
  State<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends State<_EditBody> {
  @override
  void initState() {
    super.initState();
    widget.linkController.addListener(_onLinkChanged);
  }

  @override
  void dispose() {
    widget.linkController.removeListener(_onLinkChanged);
    super.dispose();
  }

  void _onLinkChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final linkTrimmed = widget.linkController.text.trim();
    final savedLink = widget.activity.linkUrl.trim();
    final showLivePreview =
        linkTrimmed.isNotEmpty && linkTrimmed == savedLink;

    return Form(
      key: widget.formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                  selected: widget.category == c,
                  onSelected: widget.onCategoryChanged == null
                      ? null
                      : (_) => widget.onCategoryChanged!(c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: widget.labelController,
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
            controller: widget.linkController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Lien (site, billetterie, ...)',
              hintText: 'https://...',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            validator: widget.validateOptionalUrl,
          ),
          if (linkTrimmed.isNotEmpty && !showLivePreview) ...[
            const SizedBox(height: 8),
            Text(
              'L\'apercu du lien sera mis a jour apres enregistrement.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (showLivePreview) ...[
            const SizedBox(height: 12),
            LinkPreviewCardFromFirestore(
              url: linkTrimmed,
              preview: widget.activity.linkPreview,
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: widget.addressController,
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
            controller: widget.commentsController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Commentaires',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            minLines: 2,
            maxLines: 6,
          ),
        ],
      ),
    );
  }
}

String _activityDrivingRouteBodyText(TripActivity activity) {
  final route = activity.tripDrivingRoute;

  if (route == null) {
    return 'Calcul en cours depuis l\'adresse du voyage.';
  }
  switch (route.status) {
    case 'ok':
      final dist = route.distanceText?.trim();
      final dur = route.durationText?.trim();
      if ((dist != null && dist.isNotEmpty) ||
          (dur != null && dur.isNotEmpty)) {
        return [
          if (dist != null && dist.isNotEmpty) 'Distance : $dist',
          if (dur != null && dur.isNotEmpty) 'Duree : $dur',
        ].join('\n');
      }
      return 'Trajet calcule.';
    case 'missing_trip_address':
      return 'Adresse du voyage manquante : renseignez-la dans l\'apercu du voyage.';
    case 'no_result':
      return 'Aucun trajet trouve${route.detail != null && route.detail!.isNotEmpty ? ' (${route.detail})' : ''}.';
    case 'error':
      return 'Impossible de calculer le trajet${route.errorMessage != null && route.errorMessage!.isNotEmpty ? ' : ${route.errorMessage}' : ''}.';
    default:
      return 'Statut : ${route.status}';
  }
}
