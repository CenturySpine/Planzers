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

    int unreadForLabel(String label) => switch (label) {
          'Messagerie' => unreadMessages,
          'Planning' => unreadActivities,
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

              return Scaffold(
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
                                    d.label == 'Planning',
                              ),
                              selectedIcon: _buildNavIcon(
                                icon: d.selectedIcon,
                                unreadCount: unreadForLabel(d.label),
                                showBadge: d.label == 'Messagerie' ||
                                    d.label == 'Planning',
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
                        },
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

/// Material 3–style bottom destinations equally distributed across width.
/// The Planning tab (center) is rendered as a floating FAB-style button that
/// visually rises above the bar surface.
class _TripMobileScrollableNavBar extends StatelessWidget {
  const _TripMobileScrollableNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.unreadByTabLabel,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_TripNavDestination> destinations;
  final Map<String, int> unreadByTabLabel;

  static const double _barHeight = 62;
  static const double _planningButtonSize = 56;
  // Target visual pixels the Planning button floats above the bar's visible top edge.
  static const double _planningFloat = 8;
  // Index of the Planning tab inside [destinations].
  static const int _planningIdx = 2;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = NavigationBarTheme.of(context).backgroundColor ??
        colorScheme.surfaceContainer;
    final planningSelected = selectedIndex == _planningIdx;
    final planningDest = destinations[_planningIdx];
    final planningUnread = unreadByTabLabel['Planning'] ?? 0;
    // Flutter web does not relay OS window insets to MediaQuery.padding, so
    // padding.bottom is 0 on all web variants. Computing the overflow from the
    // inset keeps the visual float consistent across native and web.
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final planningOverflow = _planningFloat + bottomInset;

    return SizedBox(
      height: _barHeight + planningOverflow,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // ── Bar surface ──────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Material(
              color: bg,
              elevation: 3,
              shadowColor: Colors.transparent,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: _barHeight,
                  child: Row(
                    children: [
                      for (var index = 0;
                          index < destinations.length;
                          index++)
                        Expanded(
                          child: index == _planningIdx
                              // Centre slot: just the selection dot, taps handled
                              // by the floating button above.
                              ? GestureDetector(
                                  onTap: () => onDestinationSelected(index),
                                  behavior: HitTestBehavior.opaque,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(
                                            milliseconds: 200),
                                        curve: Curves.easeOutCubic,
                                        width: 6,
                                        height: 6,
                                        margin: const EdgeInsets.only(
                                            bottom: 4),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: planningSelected
                                              ? colorScheme.primary
                                              : Colors.transparent,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Builder(
                                  builder: (context) {
                                    final d = destinations[index];
                                    final selected = selectedIndex == index;
                                    return GestureDetector(
                                      onTap: () =>
                                          onDestinationSelected(index),
                                      behavior: HitTestBehavior.opaque,
                                      child: Column(
                                        children: [
                                          AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            curve: Curves.easeOutCubic,
                                            height: 3,
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? colorScheme.primary
                                                  : Colors.transparent,
                                              borderRadius:
                                                  const BorderRadius.only(
                                                bottomLeft:
                                                    Radius.circular(2),
                                                bottomRight:
                                                    Radius.circular(2),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                _buildNavIcon(
                                                  icon: selected
                                                      ? d.selectedIcon
                                                      : d.icon,
                                                  unreadCount:
                                                      unreadByTabLabel[
                                                              d.label] ??
                                                          0,
                                                  showBadge:
                                                      d.label == 'Messagerie',
                                                  color: selected
                                                      ? colorScheme.primary
                                                      : colorScheme
                                                          .onSurfaceVariant,
                                                ),
                                              ],
                                            ),
                                          ),
                                          AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            curve: Curves.easeOutCubic,
                                            width: 6,
                                            height: 6,
                                            margin: const EdgeInsets.only(
                                                bottom: 4),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: selected
                                                  ? colorScheme.primary
                                                  : Colors.transparent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Planning floating button ──────────────────────────────────────
          Positioned(
            top: 0,
            child: GestureDetector(
              onTap: () => onDestinationSelected(_planningIdx),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: _planningButtonSize,
                height: _planningButtonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x28000000),
                      blurRadius: 6,
                      spreadRadius: 0,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      planningSelected
                          ? planningDest.selectedIcon
                          : planningDest.icon,
                      color: colorScheme.onPrimary,
                      size: 26,
                    ),
                    if (planningUnread > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.error,
                            border: Border.all(
                              color: colorScheme.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
