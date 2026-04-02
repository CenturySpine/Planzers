import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';

class TripDetailsPage extends ConsumerStatefulWidget {
  const TripDetailsPage({
    super.key,
    required this.trip,
  });

  final Trip trip;

  @override
  ConsumerState<TripDetailsPage> createState() => _TripDetailsPageState();
}

class _TripDetailsPageState extends ConsumerState<TripDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  late Trip _trip;
  late final TextEditingController _titleController;
  late final TextEditingController _destinationController;
  late final TextEditingController _linkController;
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _titleController = TextEditingController(text: _trip.title);
    _destinationController = TextEditingController(text: _trip.destination);
    _linkController = TextEditingController(text: _trip.linkUrl);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _destinationController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _titleController.text = _trip.title;
      _destinationController.text = _trip.destination;
      _linkController.text = _trip.linkUrl;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _titleController.text = _trip.title;
      _destinationController.text = _trip.destination;
      _linkController.text = _trip.linkUrl;
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _isSaving = true);
    try {
      final title = _titleController.text.trim();
      final destination = _destinationController.text.trim();
      final linkUrl = _linkController.text.trim();

      await ref.read(tripsRepositoryProvider).updateTrip(
            tripId: _trip.id,
            title: title,
            destination: destination,
            linkUrl: linkUrl,
          );

      if (!mounted) return;
      setState(() {
        _trip = Trip(
          id: _trip.id,
          title: title,
          destination: destination,
          linkUrl: linkUrl,
          ownerId: _trip.ownerId,
          memberIds: _trip.memberIds,
          createdAt: _trip.createdAt,
        );
        _isEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voyage mis a jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur modification: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleForAppBar = _trip.title.isEmpty ? 'Voyage' : _trip.title;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final canEdit = (myUid != null && myUid == _trip.ownerId);
    final tripDocStream =
        FirebaseFirestore.instance.collection('trips').doc(_trip.id).snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(titleForAppBar),
        actions: [
          if (_isEditing) ...[
            IconButton(
              tooltip: 'Annuler',
              onPressed: _isSaving ? null : _cancelEditing,
              icon: const Icon(Icons.close),
            ),
            IconButton(
              tooltip: 'Enregistrer',
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
            ),
          ] else if (canEdit) ...[
            IconButton(
              tooltip: 'Modifier',
              onPressed: _startEditing,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: tripDocStream,
        builder: (context, snapshot) {
          final liveData = snapshot.data?.data();
          final liveLinkUrl = (liveData?['linkUrl'] as String?) ?? _trip.linkUrl;
          final livePreview =
              (liveData?['linkPreview'] as Map<String, dynamic>?) ?? const {};

          final linkUrlForUi = _isEditing ? _linkController.text.trim() : liveLinkUrl.trim();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_isEditing) ...[
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _titleController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Titre',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Titre obligatoire';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _destinationController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Destination',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Destination obligatoire';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _linkController,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Lien (Airbnb, Booking, site, ...)',
                          hintText: 'https://...',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                        validator: (value) {
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
                        },
                        onFieldSubmitted: (_) => _save(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Text(
                  _trip.title.isEmpty ? 'Sans titre' : _trip.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _trip.destination.isEmpty
                      ? 'Destination inconnue'
                      : _trip.destination,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
              ],
              if (linkUrlForUi.isNotEmpty) ...[
                _LinkPreviewCardFromFirestore(
                  url: linkUrlForUi,
                  preview: livePreview,
                ),
                const SizedBox(height: 16),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(label: 'ID', value: _trip.id),
                      const SizedBox(height: 12),
                      _InfoRow(label: 'Proprietaire', value: _trip.ownerId),
                      const SizedBox(height: 12),
                      _InfoRow(
                        label: 'Membres',
                        value: '${_trip.memberIds.length}',
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        label: 'Cree le',
                        value: _trip.createdAt.toLocal().toString(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _LinkPreviewCardFromFirestore extends StatelessWidget {
  const _LinkPreviewCardFromFirestore({
    required this.url,
    required this.preview,
  });

  final String url;
  final Map<String, dynamic> preview;

  @override
  Widget build(BuildContext context) {
    final status = (preview['status'] as String?) ?? '';
    final title = (preview['title'] as String?) ?? '';
    final description = (preview['description'] as String?) ?? '';
    final siteName = (preview['siteName'] as String?) ?? '';
    final imageUrl = (preview['imageUrl'] as String?) ?? '';

    final hasPreview = title.trim().isNotEmpty ||
        description.trim().isNotEmpty ||
        imageUrl.trim().isNotEmpty ||
        siteName.trim().isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lien', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(url),
            const SizedBox(height: 12),
            if (status == 'loading') ...[
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
            ] else if (!hasPreview) ...[
              Text(
                'Apercu indisponible pour ce lien.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imageUrl.trim().isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: kIsWeb
                            ? WebHtmlElementStrategy.prefer
                            : WebHtmlElementStrategy.never,
                        errorBuilder: (_, __, ___) => Container(
                          width: 96,
                          height: 96,
                          color: Colors.black12,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (siteName.trim().isNotEmpty) ...[
                          Text(
                            siteName,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (title.trim().isNotEmpty) ...[
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                        if (description.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

