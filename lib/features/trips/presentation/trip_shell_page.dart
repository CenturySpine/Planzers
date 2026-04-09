import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/features/account/presentation/account_menu_button.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';

/// Width at which we show a [NavigationRail] instead of a bottom [NavigationBar].
const double _kTripShellWideBreakpoint = 720;

class TripShellPage extends ConsumerWidget {
  const TripShellPage({
    super.key,
    required this.tripId,
    required this.navigationShell,
  });

  final String tripId;
  final StatefulNavigationShell navigationShell;

  static const List<_TripNavDestination> _destinations = [
    _TripNavDestination(
      label: 'Aperçu',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _TripNavDestination(
      label: 'Dépenses',
      icon: Icons.payments_outlined,
      selectedIcon: Icons.payments,
    ),
    _TripNavDestination(
      label: 'Chambres',
      icon: Icons.bed_outlined,
      selectedIcon: Icons.bed,
    ),
    _TripNavDestination(
      label: 'Voitures',
      icon: Icons.directions_car_outlined,
      selectedIcon: Icons.directions_car,
    ),
    _TripNavDestination(
      label: 'Repas',
      icon: Icons.restaurant_outlined,
      selectedIcon: Icons.restaurant,
    ),
    _TripNavDestination(
      label: 'Activités',
      icon: Icons.event_available_outlined,
      selectedIcon: Icons.event_available,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripStreamProvider(tripId));

    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Voyage')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Voyage introuvable ou acces refuse.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final titleForAppBar = trip.title.isEmpty ? 'Voyage' : trip.title;

        return TripScope(
          trip: trip,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useRail =
                  constraints.maxWidth >= _kTripShellWideBreakpoint;
              final railExtended = constraints.maxWidth >= 900;

              return Scaffold(
                appBar: AppBar(
                  title: Text(titleForAppBar),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.go('/trips'),
                    tooltip: 'Mes voyages',
                  ),
                  actions: const [
                    AccountMenuButton(),
                  ],
                ),
                body: Row(
                  children: [
                    if (useRail)
                      NavigationRail(
                        selectedIndex: navigationShell.currentIndex,
                        onDestinationSelected: navigationShell.goBranch,
                        extended: railExtended,
                        // With extended: true, Flutter only allows none/null here;
                        // labels still show next to icons via [NavigationRailDestination.label].
                        labelType: railExtended
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.selected,
                        destinations: [
                          for (final d in _destinations)
                            NavigationRailDestination(
                              icon: Icon(d.icon),
                              selectedIcon: Icon(d.selectedIcon),
                              label: Text(d.label),
                            ),
                        ],
                      ),
                    Expanded(child: navigationShell),
                  ],
                ),
                bottomNavigationBar: useRail
                    ? null
                    : NavigationBar(
                        selectedIndex: navigationShell.currentIndex,
                        onDestinationSelected: navigationShell.goBranch,
                        destinations: [
                          for (final d in _destinations)
                            NavigationDestination(
                              icon: Icon(d.icon),
                              selectedIcon: Icon(d.selectedIcon),
                              label: d.label,
                            ),
                        ],
                      ),
              );
            },
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Voyage')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Erreur: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _TripNavDestination {
  const _TripNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class TripExpensesPage extends StatelessWidget {
  const TripExpensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _TripSectionPlaceholder(
      title: 'Dépenses',
      icon: Icons.payments_outlined,
      message:
          'Suivi des dépenses partagées pour ce voyage. Contenu à venir.',
    );
  }
}

class TripRoomsPage extends StatelessWidget {
  const TripRoomsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _TripSectionPlaceholder(
      title: 'Chambres',
      icon: Icons.bed_outlined,
      message: 'Répartition des chambres et hébergements. Contenu à venir.',
    );
  }
}

class TripCarsPage extends StatelessWidget {
  const TripCarsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _TripSectionPlaceholder(
      title: 'Voitures',
      icon: Icons.directions_car_outlined,
      message: 'Covoiturage et véhicules. Contenu à venir.',
    );
  }
}

class TripMealsPage extends StatelessWidget {
  const TripMealsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _TripSectionPlaceholder(
      title: 'Repas',
      icon: Icons.restaurant_outlined,
      message: 'Planning des repas. Contenu à venir.',
    );
  }
}

class TripActivitiesPage extends StatelessWidget {
  const TripActivitiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _TripSectionPlaceholder(
      title: 'Activités',
      icon: Icons.event_available_outlined,
      message: 'Activités et sorties du voyage. Contenu à venir.',
    );
  }
}

class _TripSectionPlaceholder extends StatelessWidget {
  const _TripSectionPlaceholder({
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final trip = TripScope.of(context);
    final tripLabel = trip.title.isEmpty ? 'Ce voyage' : trip.title;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          title,
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
          message,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}
