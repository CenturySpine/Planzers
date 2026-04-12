import 'package:flutter/material.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';

/// Trip-scoped internal messaging (content to be wired to data layer).
class TripMessagingPage extends StatelessWidget {
  const TripMessagingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final trip = TripScope.of(context);
    final tripLabel = trip.title.isEmpty ? 'Ce voyage' : trip.title;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          Icons.chat_bubble_outline,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Messagerie',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          tripLabel,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        Text(
          'Échanges entre participants du voyage. Contenu à venir.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}
