import 'package:firebase_auth/firebase_auth.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/account/presentation/account_app_bar_actions.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';
import 'package:planerz/features/trips/data/trip_announcements_repository.dart';
import 'package:planerz/features/trips/data/traveler_modules_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/trips/presentation/ridgegear_module_card.dart';
import 'package:planerz/features/trips/presentation/trip_overview_ui.dart';
import 'package:planerz/features/trips/presentation/trip_date_format.dart';
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
      icon: PhosphorIconsRegular.squaresFour,
      selectedIcon: PhosphorIconsFill.squaresFour,
    ),
    _TripNavDestination(
      branchIndex: 1,
      label: 'Messagerie',
      icon: PhosphorIconsRegular.chatCircleDots,
      selectedIcon: PhosphorIconsFill.chatCircleDots,
    ),
    _TripNavDestination(
      branchIndex: 6,
      label: 'Planning',
      icon: PhosphorIconsRegular.calendarCheck,
      selectedIcon: PhosphorIconsFill.calendarCheck,
    ),
    _TripNavDestination(
      branchIndex: 2,
      label: 'Dépenses',
      icon: PhosphorIconsRegular.wallet,
      selectedIcon: PhosphorIconsFill.wallet,
    ),
    _TripNavDestination(
      branchIndex: 7,
      label: 'Courses',
      icon: PhosphorIconsRegular.shoppingCartSimple,
      selectedIcon: PhosphorIconsFill.shoppingCartSimple,
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

  @override
  void didUpdateWidget(covariant TripShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Branch pages stay mounted (StatefulShellRoute.indexedStack) — switching
    // back to Aperçu never triggers a fresh build, so the Ridgegear weight
    // provider would keep serving its cached value forever. The provider
    // can't be pushed to by the external API, so re-fetch it by hand every
    // time the traveler lands back on the overview tab.
    final justArrivedOnOverview = oldWidget.navigationShell.currentIndex != 0 &&
        widget.navigationShell.currentIndex == 0;
    if (!justArrivedOnOverview) return;
    final projectId = ref
        .read(myTravelerModulesStreamProvider(widget.tripId))
        .asData
        ?.value
        .ridgegear
        .projectId;
    if (projectId != null && projectId.isNotEmpty) {
      ref.invalidate(ridgegearProjectWeightProvider(projectId));
    }
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
    final announcementsAsync =
        ref.watch(tripAnnouncementsStreamProvider(tripId));
    final announcementsLastReadAtAsync = ref.watch(
      tripChannelLastReadAtProvider(
        (tripId: tripId, channel: TripNotificationChannel.announcements),
      ),
    );
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
    var unreadAnnouncements = 0;
    final messages = messagesAsync.asData?.value;
    final activities = activitiesAsync.asData?.value;
    final announcements = announcementsAsync.asData?.value;
    final lastReadAt = lastReadAtAsync.asData?.value?.toUtc();
    final announcementsLastReadAt =
        announcementsLastReadAtAsync.asData?.value?.toUtc();
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
    if (counters != null &&
        counters.hasChannel(TripNotificationChannel.announcements)) {
      unreadAnnouncements =
          counters.unreadFor(TripNotificationChannel.announcements);
    } else if (myUid != null && myUid.isNotEmpty && announcements != null) {
      unreadAnnouncements = announcements.where((announcement) {
        if (announcement.authorId == myUid) return false;
        if (announcementsLastReadAt == null) return true;
        return announcement.createdAt
            .toUtc()
            .isAfter(announcementsLastReadAt);
      }).length;
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
                  // Branch pages use nested Scaffolds with FABs; extendBody would
                  // let the body draw behind the bottom nav and hide those FABs.
                  extendBody: false,
                  appBar: AppBar(
                  automaticallyImplyLeading: false,
                  title: GestureDetector(
                    onTap: isOnTripOverview ? null : _goToOverview,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          titleForAppBar,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (trip.startDate != null || trip.endDate != null)
                          Text(
                            trip.isDayTrip
                                ? formatTripSingleDayDate(
                                    context, trip.startDate)
                                : formatTripDateRangeCompact(
                                    context, trip.startDate, trip.endDate),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  leading: IconButton(
                    icon: const Icon(PhosphorIconsRegular.arrowLeft),
                    onPressed: () => isOnTripOverview
                        ? context.go('/trips')
                        : context.go('/trips/$tripId/overview'),
                    tooltip: isOnTripOverview
                        ? l10n.tripsMyTrips
                        : l10n.tripTabOverview,
                  ),
                  actions: [
                    TripOverviewAnnouncementsAppBarAction(
                      tooltip: l10n.tripOverviewTopTabAnnouncements,
                      hasUnread: unreadAnnouncements > 0,
                      onTap: () =>
                          context.push('/trips/$tripId/announcements'),
                    ),
                    const AccountAppBarActions(),
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

/// Bottom navigation: four standard tabs around a Planning "capsule" that is
/// always tinted (and filled when selected) so the core feature stands out
/// without leaving the bar's standard layout.
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
  static const Duration _tabDuration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final tabDuration = disableAnimations ? Duration.zero : _tabDuration;

    return Material(
      color: AppTokens.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTokens.divider)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: AppTokens.bottomNavBarHeight,
            child: Row(
              children: [
                for (var index = 0; index < destinations.length; index++)
                  Expanded(
                    flex: index == _planningIdx ? 15 : 10,
                    child: index == _planningIdx
                        ? _TripPlanningCapsule(
                            selected: selectedIndex == index,
                            icon: selectedIndex == index
                                ? destinations[index].selectedIcon
                                : destinations[index].icon,
                            label: localizedLabel(destinations[index].label),
                            unreadCount:
                                unreadByTabLabel[destinations[index].label] ??
                                    0,
                            onTap: () => onDestinationSelected(index),
                            duration: tabDuration,
                          )
                        : _TripBottomNavTab(
                            destination: destinations[index],
                            selected: selectedIndex == index,
                            label: localizedLabel(destinations[index].label),
                            unreadCount:
                                unreadByTabLabel[destinations[index].label] ??
                                    0,
                            showBadge:
                                destinations[index].label == 'Messagerie' ||
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
    required this.onTap,
    required this.tabDuration,
  });

  final _TripNavDestination destination;
  final bool selected;
  final String label;
  final int unreadCount;
  final bool showBadge;
  final VoidCallback onTap;
  final Duration tabDuration;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppTokens.primaryDark : AppTokens.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: tabDuration,
              curve: _TripMobileScrollableNavBar._tabCurve,
              width: 52,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? AppTokens.primaryTint : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: _buildNavIcon(
                icon: selected ? destination.selectedIcon : destination.icon,
                unreadCount: unreadCount,
                showBadge: showBadge,
                color: color,
                size: AppTokens.bottomNavTabIconSize,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                height: 1.1,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripPlanningCapsule extends StatelessWidget {
  const _TripPlanningCapsule({
    required this.selected,
    required this.icon,
    required this.label,
    required this.unreadCount,
    required this.onTap,
    required this.duration,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final int unreadCount;
  final VoidCallback onTap;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppTokens.primaryDark;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: duration,
            curve: _TripMobileScrollableNavBar._tabCurve,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? AppTokens.primary : AppTokens.primarySoft,
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              boxShadow: selected ? [AppTokens.ctaShadow] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  isLabelVisible: unreadCount > 0,
                  smallSize: 8,
                  child: Icon(icon, size: 22, color: fg),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
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
    final l10n = AppLocalizations.of(context)!;
    return _TripSectionPlaceholder(
      title: l10n.tripCarsTitle,
      icon: PhosphorIconsRegular.car,
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
      icon: PhosphorIconsRegular.forkKnife,
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
