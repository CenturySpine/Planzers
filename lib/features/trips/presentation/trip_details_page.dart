import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _titleController = TextEditingController(text: _trip.title);
    _destinationController = TextEditingController(text: _trip.destination);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _titleController.text = _trip.title;
      _destinationController.text = _trip.destination;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _titleController.text = _trip.title;
      _destinationController.text = _trip.destination;
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

      await ref.read(tripsRepositoryProvider).updateTrip(
            tripId: _trip.id,
            title: title,
            destination: destination,
          );

      if (!mounted) return;
      setState(() {
        _trip = Trip(
          id: _trip.id,
          title: title,
          destination: destination,
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
      body: ListView(
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
                    textInputAction: TextInputAction.done,
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
              _trip.destination.isEmpty ? 'Destination inconnue' : _trip.destination,
              style: Theme.of(context).textTheme.titleMedium,
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

