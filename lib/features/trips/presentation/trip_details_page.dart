import 'package:flutter/material.dart';
import 'package:planzers/features/trips/data/trip.dart';

class TripDetailsPage extends StatelessWidget {
  const TripDetailsPage({
    super.key,
    required this.trip,
  });

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(trip.title.isEmpty ? 'Voyage' : trip.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            trip.title.isEmpty ? 'Sans titre' : trip.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            trip.destination.isEmpty ? 'Destination inconnue' : trip.destination,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: 'ID', value: trip.id),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'Proprietaire', value: trip.ownerId),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: 'Membres',
                    value: '${trip.memberIds.length}',
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: 'Cree le',
                    value: trip.createdAt.toLocal().toString(),
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

