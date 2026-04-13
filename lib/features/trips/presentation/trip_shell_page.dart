import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/features/account/presentation/account_menu_button.dart';
import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';

/// Backfill [Trip.memberPublicLabels] for the current user (e.g. voyages créés
/// avant le déploiement des fonctions). Au plus un appel par voyage et par
/// lancement d'app, et seulement si l'entrée est encore absente.
final _tripMemberPublicLabelHealScheduled = <String>{};

void _scheduleTripMemberPublicLabelHealIfNeeded(WidgetRef ref, Trip trip) {
  final uid = FirebaseAuth.instance.currentUser?.uid.trim();
  if (uid == null || uid.isEmpty) return;

  final existing = trip.memberPublicLabels[uid]?.trim() ?? '';
  if (existing.isNotEmpty) return;

  final id = trip.id.trim();
  if (id.isEmpty) return;
  if (!_tripMemberPublicLabelHealScheduled.add(id)) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref
        .read(tripsRepositoryProvider)
        .registerMyTripMemberLabel(tripId: id)
        .catchError((Object _) {});
  });
}

/// Width at which we show a [NavigationRail] instead of a bottom nav bar.
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
      label: 'Messagerie',
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
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

        _scheduleTripMemberPublicLabelHealIfNeeded(ref, trip);

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
                    : _TripMobileScrollableNavBar(
                        selectedIndex: navigationShell.currentIndex,
                        onDestinationSelected: navigationShell.goBranch,
                        destinations: _destinations,
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

/// Material 3–style bottom destinations in a horizontal scroll view so many
/// tabs stay usable on narrow phones.
class _TripMobileScrollableNavBar extends StatelessWidget {
  const _TripMobileScrollableNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_TripNavDestination> destinations;

  static const double _barHeight = 80;
  static const double _minItemWidth = 80;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = NavigationBarTheme.of(context).backgroundColor ??
        colorScheme.surfaceContainer;

    return Material(
      color: bg,
      elevation: 3,
      shadowColor: Colors.transparent,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: destinations.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (context, index) {
              final d = destinations[index];
              final selected = selectedIndex == index;
              return SizedBox(
                width: _minItemWidth,
                child: InkWell(
                  onTap: () => onDestinationSelected(index),
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? colorScheme.secondaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          selected ? d.selectedIcon : d.icon,
                          color: selected
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        d.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: selected
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
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
