import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/account/presentation/account_app_bar_actions.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Width at which we show a [NavigationRail] instead of a bottom nav bar.
const double _kTripShellWideBreakpoint = 720;

Widget _buildNavIcon({
  required IconData icon,
  required int unreadCount,
  required bool showBadge,
  Color? color,
  double size = 28,
}) {
  final iconWidget = Icon(icon, color: color, size: size);
  if (!showBadge || unreadCount <= 0) return iconWidget;
  return Badge.count(count: unreadCount, child: iconWidget);
}

class TripShellPage extends ConsumerStatefulWidget {
  const TripShellPage({
    super.key,
    required this.tripId,
    required this.navigationShell,
  });

  final String tripId;
  final StatefulNavigationShell navigationShell;

  static const List<_TripNavDestination> _destinations = [
    _TripNavDestination(
      branchIndex: 0,
      label: 'Aperçu',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _TripNavDestination(
      branchIndex: 1,
      label: 'Messagerie',
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
    ),
    _TripNavDestination(
      branchIndex: 6,
      label: 'Planning',
      icon: Icons.event_available_outlined,
      selectedIcon: Icons.event_available,
    ),
    _TripNavDestination(
      branchIndex: 2,
      label: 'Dépenses',
      icon: Icons.payments_outlined,
      selectedIcon: Icons.payments,
    ),
    _TripNavDestination(
      branchIndex: 7,
      label: 'Courses',
      icon: Icons.shopping_cart_outlined,
      selectedIcon: Icons.shopping_cart,
    ),
  ];

  @override
  ConsumerState<TripShellPage> createState() => _TripShellPageState();
}

class _TripShellPageState extends ConsumerState<TripShellPage> {
  String? _lastPrecachingBannerUrl;
  void _goToOverview() {
    widget.navigationShell.goBranch(0);
  }

  void _precacheTripBannerIfNeeded(String? rawUrl) {
    final cleanUrl = (rawUrl ?? '').trim();
    if (cleanUrl.isEmpty || cleanUrl == _lastPrecachingBannerUrl) return;
    _lastPrecachingBannerUrl = cleanUrl;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(NetworkImage(cleanUrl), context).catchError((Object _) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tripId = widget.tripId;
    final navigationShell = widget.navigationShell;
    final tripAsync = ref.watch(tripStreamProvider(tripId));
    final countersAsync = ref.watch(tripNotificationCountersProvider(tripId));
    final messagesAsync = ref.watch(tripMessagesStreamProvider(tripId));
    final activitiesAsync = ref.watch(tripActivitiesStreamProvider(tripId));
    final lastReadAtAsync = ref.watch(
      tripChannelLastReadAtProvider(
        (tripId: tripId, channel: TripNotificationChannel.messages),
      ),
    );
    final activitiesLastReadAtAsync = ref.watch(
      tripChannelLastReadAtProvider(
        (tripId: tripId, channel: TripNotificationChannel.activities),
      ),
    );
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim();

    var unreadMessages = 0;
    var unreadActivities = 0;
    var unreadExpenses = 0;
    final messages = messagesAsync.asData?.value;
    final activities = activitiesAsync.asData?.value;
    final lastReadAt = lastReadAtAsync.asData?.value?.toUtc();
    final activitiesLastReadAt =
        activitiesLastReadAtAsync.asData?.value?.toUtc();
    final counters = countersAsync.asData?.value;
    if (counters != null &&
        counters.hasChannel(TripNotificationChannel.messages)) {
      unreadMessages = counters.unreadFor(TripNotificationChannel.messages);
    } else if (myUid != null && myUid.isNotEmpty && messages != null) {
      unreadMessages = messages.where((message) {
        if (message.authorId == myUid) return false;
        if (lastReadAt == null) return true;
        return message.createdAt.toUtc().isAfter(lastReadAt);
      }).length;
    }
    if (counters != null &&
        counters.hasChannel(TripNotificationChannel.activities)) {
      unreadActivities = counters.unreadFor(TripNotificationChannel.activities);
    } else if (myUid != null && myUid.isNotEmpty && activities != null) {
      unreadActivities = activities.where((activity) {
        if (activity.createdBy == myUid) return false;
        if (activitiesLastReadAt == null) return true;
        return activity.createdAt.toUtc().isAfter(activitiesLastReadAt);
      }).length;
    }
    if (counters != null &&
        counters.hasChannel(TripNotificationChannel.expenses)) {
      unreadExpenses = counters.unreadFor(TripNotificationChannel.expenses);
    }

    int unreadForLabel(String label) => switch (label) {
          'Messagerie' => unreadMessages,
          'Planning' => unreadActivities,
          'Dépenses' => unreadExpenses,
          _ => 0,
        };

    String localizedNavLabel(String label) => switch (label) {
          'Aperçu' => l10n.tripTabOverview,
          'Messagerie' => l10n.tripTabMessages,
          'Planning' => l10n.tripTabActivities,
          'Dépenses' => l10n.tripTabExpenses,
          'Repas' => l10n.tripTabMeals,
          'Courses' => l10n.tripTabShopping,
          _ => label,
        };

    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go('/trips');
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final titleForAppBar =
            trip.title.isEmpty ? l10n.tripLabelGeneric : trip.title;
        _precacheTripBannerIfNeeded(trip.bannerImageUrl);

        return TripScope(
          trip: trip,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useRail = constraints.maxWidth >= _kTripShellWideBreakpoint;
              final railExtended = constraints.maxWidth >= 900;
              final selectedDestinationIndex = TripShellPage._destinations.indexWhere(
                (destination) =>
                    destination.branchIndex == navigationShell.currentIndex,
              );
              final displayedSelectedIndex =
                  selectedDestinationIndex >= 0 ? selectedDestinationIndex : 0;
              final currentPath = GoRouterState.of(context).uri.path;
              final isOnTripOverview = currentPath.endsWith('/overview');

              return Theme(
                data: Theme.of(context).copyWith(
                  bottomNavigationBarTheme:
                      Theme.of(context).bottomNavigationBarTheme.copyWith(
                            backgroundColor: Colors.transparent,
                            elevation: 0,
                          ),
                ),
                child: Scaffold(
                  extendBody: !useRail,
                  appBar: AppBar(
                  automaticallyImplyLeading: false,
                  title: GestureDetector(
                    onTap: isOnTripOverview ? null : _goToOverview,
                    behavior: HitTestBehavior.opaque,
                    child: Text(titleForAppBar),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => isOnTripOverview
                        ? context.go('/trips')
                        : context.go('/trips/$tripId/overview'),
                    tooltip: isOnTripOverview
                        ? l10n.tripsMyTrips
                        : l10n.tripTabOverview,
                  ),
                  actions: const [
                    AccountAppBarActions(),
                  ],
                ),
                body: Row(
                  children: [
                    if (useRail)
                      NavigationRail(
                        selectedIndex: displayedSelectedIndex,
                        onDestinationSelected: (index) {
                          navigationShell.goBranch(
                            TripShellPage._destinations[index].branchIndex,
                          );
                        },
                        extended: railExtended,
                        // With extended: true, Flutter only allows none/null here;
                        // labels still show next to icons via [NavigationRailDestination.label].
                        labelType: railExtended
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.selected,
                        destinations: [
                          for (final d in TripShellPage._destinations)
                            NavigationRailDestination(
                              icon: _buildNavIcon(
                                icon: d.icon,
                                unreadCount: unreadForLabel(d.label),
                                showBadge: d.label == 'Messagerie' ||
                                    d.label == 'Planning' ||
                                    d.label == 'Dépenses',
                              ),
                              selectedIcon: _buildNavIcon(
                                icon: d.selectedIcon,
                                unreadCount: unreadForLabel(d.label),
                                showBadge: d.label == 'Messagerie' ||
                                    d.label == 'Planning' ||
                                    d.label == 'Dépenses',
                              ),
                              label: Text(localizedNavLabel(d.label)),
                            ),
                        ],
                      ),
                    Expanded(child: navigationShell),
                  ],
                ),
                bottomNavigationBar: useRail
                    ? null
                    : _TripMobileScrollableNavBar(
                        selectedIndex: displayedSelectedIndex,
                        onDestinationSelected: (index) {
                          navigationShell.goBranch(
                            TripShellPage._destinations[index].branchIndex,
                          );
                        },
                        destinations: TripShellPage._destinations,
                        unreadByTabLabel: {
                          'Messagerie': unreadMessages,
                          'Planning': unreadActivities,
                          'Dépenses': unreadExpenses,
                        },
                        localizedLabel: localizedNavLabel,
                      ),
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
        appBar: AppBar(title: Text(l10n.tripLabelGeneric)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.commonErrorWithDetails(error.toString()),
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
    required this.branchIndex,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final int branchIndex;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Néon bottom navigation: five destinations with a raised Planning FAB.
class _TripMobileScrollableNavBar extends StatelessWidget {
  const _TripMobileScrollableNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.unreadByTabLabel,
    required this.localizedLabel,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_TripNavDestination> destinations;
  final Map<String, int> unreadByTabLabel;
  final String Function(String label) localizedLabel;

  static const int _planningIdx = 2;
  static const Curve _tabCurve = Cubic(0.2, 0, 0, 1);
  static const Curve _fabCurve = Cubic(0.2, 0, 0, 1);
  static const Duration _tabDuration = Duration(milliseconds: 150);
  static const Duration _fabDuration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final tabDuration = disableAnimations ? Duration.zero : _tabDuration;
    final fabDuration = disableAnimations ? Duration.zero : _fabDuration;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final planningOverflow = NeonPalette.bottomNavFabOverflow + bottomInset;
    final planningSelected = selectedIndex == _planningIdx;
    final planningDest = destinations[_planningIdx];
    final planningUnread = unreadByTabLabel['Planning'] ?? 0;

    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
      height: NeonPalette.bottomNavBarHeight + planningOverflow,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: NeonPalette.surface,
                boxShadow: NeonPalette.bottomNavElevation,
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: NeonPalette.bottomNavBarHeight,
                  child: Row(
                    children: [
                      for (var index = 0;
                          index < destinations.length;
                          index++)
                        if (index == _planningIdx)
                          Expanded(
                            flex: 11,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.topCenter,
                              children: [
                                Positioned(
                                  top: -NeonPalette.bottomNavFabOverflow,
                                  child: _TripPlanningFab(
                                    selected: planningSelected,
                                    icon: planningSelected
                                        ? planningDest.selectedIcon
                                        : planningDest.icon,
                                    unreadCount: planningUnread,
                                    onTap: () =>
                                        onDestinationSelected(_planningIdx),
                                    fabDuration: fabDuration,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Expanded(
                            flex: 10,
                            child: _TripBottomNavTab(
                              destination: destinations[index],
                              selected: selectedIndex == index,
                              label:
                                  localizedLabel(destinations[index].label),
                              unreadCount: unreadByTabLabel[
                                      destinations[index].label] ??
                                  0,
                              showBadge: destinations[index].label ==
                                      'Messagerie' ||
                                  destinations[index].label == 'Dépenses',
                              expensesAccent:
                                  destinations[index].label == 'Dépenses',
                              onTap: () => onDestinationSelected(index),
                              tabDuration: tabDuration,
                            ),
                          ),
                    ],
                  ),
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

class _TripBottomNavTab extends StatelessWidget {
  const _TripBottomNavTab({
    required this.destination,
    required this.selected,
    required this.label,
    required this.unreadCount,
    required this.showBadge,
    required this.expensesAccent,
    required this.onTap,
    required this.tabDuration,
  });

  final _TripNavDestination destination;
  final bool selected;
  final String label;
  final int unreadCount;
  final bool showBadge;
  final bool expensesAccent;
  final VoidCallback onTap;
  final Duration tabDuration;

  Color get _activeColor =>
      expensesAccent ? NeonPalette.accent : NeonPalette.primary;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? _activeColor : NeonPalette.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (selected)
            Positioned(
              top: NeonPalette.bottomNavIndicatorTop,
              child: AnimatedContainer(
                duration: tabDuration,
                curve: _TripMobileScrollableNavBar._tabCurve,
                width: NeonPalette.bottomNavIndicatorWidth,
                height: NeonPalette.bottomNavIndicatorHeight,
                decoration: BoxDecoration(
                  color: _activeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNavIcon(
                icon: selected ? destination.selectedIcon : destination.icon,
                unreadCount: unreadCount,
                showBadge: showBadge,
                color: color,
                size: NeonPalette.bottomNavTabIconSize,
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: tabDuration,
                curve: _TripMobileScrollableNavBar._tabCurve,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  height: 1,
                  color: color,
                ),
                child: Text(label),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TripPlanningFab extends StatelessWidget {
  const _TripPlanningFab({
    required this.selected,
    required this.icon,
    required this.unreadCount,
    required this.onTap,
    required this.fabDuration,
  });

  final bool selected;
  final IconData icon;
  final int unreadCount;
  final VoidCallback onTap;
  final Duration fabDuration;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: fabDuration,
        curve: _TripMobileScrollableNavBar._fabCurve,
        width: NeonPalette.bottomNavFabSize,
        height: NeonPalette.bottomNavFabSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: NeonPalette.bottomNavFabGradient,
          border: Border.all(
            color: NeonPalette.surface,
            width: NeonPalette.bottomNavFabBorderWidth,
          ),
          boxShadow: selected
              ? NeonPalette.bottomNavFabShadowSelected
              : NeonPalette.bottomNavFabShadow,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: NeonPalette.bottomNavFabIconSize,
            ),
            if (unreadCount > 0)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: NeonPalette.accent,
                    border: Border.all(
                      color: NeonPalette.surface,
                      width: 1.5,
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

class TripCarsPage extends StatelessWidget {
  const TripCarsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _TripSectionPlaceholder(
      title: l10n.tripCarsTitle,
      icon: Icons.directions_car_outlined,
      message: l10n.tripCarsComingSoon,
    );
  }
}

class TripMealsPlaceholderPage extends StatelessWidget {
  const TripMealsPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _TripSectionPlaceholder(
      title: l10n.tripTabMeals,
      icon: Icons.restaurant_outlined,
      message: l10n.tripMealsComingSoon,
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
    final l10n = AppLocalizations.of(context)!;
    final trip = TripScope.of(context);
    final tripLabel = trip.title.isEmpty ? l10n.tripThisTrip : trip.title;

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
