import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/app_version_provider.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/presentation/planerz_brand_mark.dart';
import 'package:planerz/features/account/presentation/account_menu_button.dart';
import 'package:planerz/features/administration/data/maintenance_repository.dart';
import 'package:planerz/features/administration/presentation/admin_announcements_bell_button.dart';
import 'package:planerz/features/legal/presentation/legal_information_page.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_archive_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/trips/presentation/join_trip_by_code_dialog.dart';
import 'package:planerz/features/trips/presentation/trip_create_page.dart';
import 'package:planerz/features/trips/presentation/trip_date_format.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class TripsPage extends ConsumerStatefulWidget {
  const TripsPage({super.key});

  @override
  ConsumerState<TripsPage> createState() => _TripsPageState();
}

enum _TripTimelineCategory { past, ongoing, upcoming }

class _TripsPageState extends ConsumerState<TripsPage>
    with SingleTickerProviderStateMixin {
  static const double _legalLinkFontSize = 12;
  static const double _speedDialBottomOffset = 36;
  TabController? _tabController;
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTimelineTabChanged);
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final legalLinkColor = AppTokens.onSurfaceVariant;
    final tripsAsync = ref.watch(tripsStreamProvider);
    final unreadByTripAsync = ref.watch(myTripUnreadTotalsProvider);
    final isApplicationOwner =
        ref.watch(isApplicationOwnerProvider).asData?.value ?? false;
    final showNonMemberTrips =
        ref.watch(applicationOwnerShowNonMemberTripsProvider);
    final showArchivedTrips = ref.watch(showArchivedTripsProvider);
    final myArchivedTripIds =
        ref.watch(myArchivedTripIdsProvider).asData?.value ?? const <String>{};

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppTokens.scaffoldBackground,
        body: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _TripsBrandHeader(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text(
                    l10n.tripsMyTrips,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (isApplicationOwner)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                    child: _TripsFilterRow(
                      icon: Icons.groups_outlined,
                      label: l10n.tripsApplicationOwnerShowNonMemberTrips,
                      value: showNonMemberTrips,
                      onChanged: (value) {
                        ref
                            .read(
                              applicationOwnerShowNonMemberTripsProvider
                                  .notifier,
                            )
                            .setShowNonMemberTrips(value);
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
                  child: _TripsFilterRow(
                    icon: Icons.archive_outlined,
                    label: l10n.tripsShowArchivedTrips,
                    value: showArchivedTrips,
                    onChanged: (value) {
                      ref
                          .read(showArchivedTripsProvider.notifier)
                          .setShowArchivedTrips(value);
                    },
                  ),
                ),
                Expanded(
                  child: tripsAsync.when(
                    data: (trips) {
                      final visibleTrips = showArchivedTrips
                          ? trips
                          : trips
                              .where((trip) =>
                                  !myArchivedTripIds.contains(trip.id))
                              .toList();
                      final grouped = _groupTripsByTimeline(visibleTrips);
                      _ensureTimelineTabController(grouped);
                      final tabController = _tabController!;
                      final unreadByTrip = unreadByTripAsync.asData?.value ??
                          const <String, int>{};
                      final pastUnread = _sumUnreadForTrips(
                        grouped[_TripTimelineCategory.past] ?? const [],
                        unreadByTrip,
                      );
                      final ongoingUnread = _sumUnreadForTrips(
                        grouped[_TripTimelineCategory.ongoing] ?? const [],
                        unreadByTrip,
                      );
                      final upcomingUnread = _sumUnreadForTrips(
                        grouped[_TripTimelineCategory.upcoming] ?? const [],
                        unreadByTrip,
                      );

                      return Column(
                        children: [
                          _TripsTimelineTabBar(
                            controller: tabController,
                            tabs: [
                              _buildTimelineTab(
                                context,
                                label: l10n.tripsTimelinePast,
                                tripCount: grouped[_TripTimelineCategory.past]
                                        ?.length ??
                                    0,
                                unreadCount: pastUnread,
                              ),
                              _buildTimelineTab(
                                context,
                                label: l10n.tripsTimelineOngoing,
                                tripCount:
                                    grouped[_TripTimelineCategory.ongoing]
                                            ?.length ??
                                        0,
                                unreadCount: ongoingUnread,
                              ),
                              _buildTimelineTab(
                                context,
                                label: l10n.tripsTimelineUpcoming,
                                tripCount:
                                    grouped[_TripTimelineCategory.upcoming]
                                            ?.length ??
                                        0,
                                unreadCount: upcomingUnread,
                              ),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              controller: tabController,
                              children: [
                                _TripsTimelineList(
                                  category: _TripTimelineCategory.past,
                                  trips: grouped[_TripTimelineCategory.past] ??
                                      const [],
                                  emptyMessage: l10n.tripsEmptyPast,
                                  onOpenTrip: (tripId) =>
                                      context.go('/trips/$tripId/overview'),
                                ),
                                _TripsTimelineList(
                                  category: _TripTimelineCategory.ongoing,
                                  trips:
                                      grouped[_TripTimelineCategory.ongoing] ??
                                          const [],
                                  emptyMessage: l10n.tripsEmptyOngoing,
                                  onOpenTrip: (tripId) =>
                                      context.go('/trips/$tripId/overview'),
                                ),
                                _TripsTimelineList(
                                  category: _TripTimelineCategory.upcoming,
                                  trips:
                                      grouped[_TripTimelineCategory.upcoming] ??
                                          const [],
                                  emptyMessage: l10n.tripsEmptyUpcoming,
                                  onOpenTrip: (tripId) =>
                                      context.go('/trips/$tripId/overview'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.tripsFirestoreError(error.toString()),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () =>
                            context.push(LegalInformationPage.routePath),
                        style: TextButton.styleFrom(
                          foregroundColor: legalLinkColor,
                          textStyle: const TextStyle(
                            fontSize: _legalLinkFontSize,
                            fontWeight: FontWeight.w400,
                          ),
                          overlayColor: Colors.transparent,
                          minimumSize: Size.zero,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(l10n.legalInfoTitle),
                      ),
                      _FooterSeparator(color: legalLinkColor),
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse('https://centuryspine.org'),
                          mode: LaunchMode.externalApplication,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: legalLinkColor,
                          textStyle: const TextStyle(
                            fontSize: _legalLinkFontSize,
                            fontWeight: FontWeight.w400,
                          ),
                          overlayColor: Colors.transparent,
                          minimumSize: Size.zero,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(l10n.aboutTitle),
                      ),
                      _FooterSeparator(color: legalLinkColor),
                      Text(
                        l10n.appCopyright,
                        style: TextStyle(
                          fontSize: _legalLinkFontSize,
                          fontWeight: FontWeight.w400,
                          color: legalLinkColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: _speedDialBottomOffset,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'trips_join_fab',
                      tooltip: l10n.tripsJoinWithInviteTooltip,
                      backgroundColor: AppTokens.surface,
                      foregroundColor: AppTokens.primaryDark,
                      onPressed: () => _openJoinByInviteCodeDialog(context),
                      child: const Icon(Icons.vpn_key_outlined, size: 20),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.extended(
                      heroTag: 'trips_create_fab',
                      onPressed: () => context.push(TripCreatePage.routePath),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(l10n.tripsNewTripTooltip),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _ensureTimelineTabController(
      Map<_TripTimelineCategory, List<Trip>> grouped) {
    if (_tabController != null) return;

    final lastIndex = ref.read(tripsListLastTimelineIndexProvider);
    final initialIndex = lastIndex ?? _defaultTimelineIndex(grouped);

    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIndex,
    )..addListener(_onTimelineTabChanged);
  }

  /// Startup-only default: ongoing trips take priority over upcoming ones,
  /// which take priority over past ones. Only used when the trip list has
  /// no remembered tab from earlier in this app session.
  int _defaultTimelineIndex(Map<_TripTimelineCategory, List<Trip>> grouped) {
    if ((grouped[_TripTimelineCategory.ongoing] ?? const []).isNotEmpty) {
      return 1;
    }
    return 2;
  }

  void _onTimelineTabChanged() {
    final controller = _tabController;
    if (controller == null || controller.indexIsChanging) return;
    ref
        .read(tripsListLastTimelineIndexProvider.notifier)
        .setIndex(controller.index);
  }

  Map<_TripTimelineCategory, List<Trip>> _groupTripsByTimeline(
      List<Trip> trips) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final grouped = <_TripTimelineCategory, List<Trip>>{
      _TripTimelineCategory.past: [],
      _TripTimelineCategory.ongoing: [],
      _TripTimelineCategory.upcoming: [],
    };

    for (final trip in trips) {
      final category = _timelineCategoryForTrip(trip, today);
      grouped[category]!.add(trip);
    }

    grouped[_TripTimelineCategory.past]!.sort(_comparePastTrips);
    grouped[_TripTimelineCategory.ongoing]!.sort(_compareOngoingTrips);
    grouped[_TripTimelineCategory.upcoming]!.sort(_compareUpcomingTrips);
    return grouped;
  }

  _TripTimelineCategory _timelineCategoryForTrip(Trip trip, DateTime today) {
    final start = trip.startDate != null
        ? DateTime(
            trip.startDate!.year, trip.startDate!.month, trip.startDate!.day)
        : null;
    final end = trip.endDate != null
        ? DateTime(trip.endDate!.year, trip.endDate!.month, trip.endDate!.day)
        : null;

    if (start == null && end == null) {
      return _TripTimelineCategory.ongoing;
    }
    if (end != null && end.isBefore(today)) {
      return _TripTimelineCategory.past;
    }
    if (start != null && start.isAfter(today)) {
      return _TripTimelineCategory.upcoming;
    }
    return _TripTimelineCategory.ongoing;
  }

  int _comparePastTrips(Trip a, Trip b) {
    final aEnd = a.endDate ?? a.startDate ?? a.createdAt;
    final bEnd = b.endDate ?? b.startDate ?? b.createdAt;
    return bEnd.compareTo(aEnd);
  }

  int _compareOngoingTrips(Trip a, Trip b) {
    final aStart = a.startDate ?? a.createdAt;
    final bStart = b.startDate ?? b.createdAt;
    return bStart.compareTo(aStart);
  }

  int _compareUpcomingTrips(Trip a, Trip b) {
    final aStart = a.startDate ?? a.endDate ?? a.createdAt;
    final bStart = b.startDate ?? b.endDate ?? b.createdAt;
    return aStart.compareTo(bStart);
  }

  int _sumUnreadForTrips(List<Trip> trips, Map<String, int> unreadByTrip) {
    return trips.fold<int>(
      0,
      (sum, trip) => sum + (unreadByTrip[trip.id] ?? 0),
    );
  }

  Tab _buildTimelineTab(
    BuildContext context, {
    required String label,
    required int tripCount,
    required int unreadCount,
  }) {
    return Tab(
      height: 42,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: unreadCount > 0
                  ? AppTokens.accent
                  : AppTokens.surfaceMuted,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              unreadCount > 0 ? '$unreadCount' : '$tripCount',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTokens.deep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openJoinByInviteCodeDialog(BuildContext parentContext) async {
    await showJoinTripByCodeDialog(parentContext: parentContext);
  }

}

class _FooterSeparator extends StatelessWidget {
  const _FooterSeparator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '|',
      style: TextStyle(
        fontSize: _TripsPageState._legalLinkFontSize,
        fontWeight: FontWeight.w400,
        color: color,
      ),
    );
  }
}

class _TripsBrandHeader extends ConsumerWidget {
  const _TripsBrandHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).asData?.value;
    final isPreview =
        ref.watch(firebaseTargetProvider) == FirebaseTarget.preview;
    const previewInk = Color(0xFF8A5A00);

    return Material(
      color: AppTokens.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTokens.divider)),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  const PlanerzBrandLockup(),
                  if (version != null || isPreview) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isPreview
                            ? AppTokens.accentSoft
                            : AppTokens.surfaceMuted,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isPreview) ...[
                            const Icon(Icons.science_outlined,
                                size: 12, color: previewInk),
                            const SizedBox(width: 3),
                          ],
                          Text(
                            [
                              if (version != null) version,
                              if (isPreview) 'preview',
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isPreview
                                  ? previewInk
                                  : AppTokens.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  const AdminAnnouncementsBellButton(),
                  const SizedBox(width: 4),
                  const AccountMenuButton(brandedHeader: true),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TripsFilterRow extends StatelessWidget {
  const _TripsFilterRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: AppTokens.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripsTimelineTabBar extends StatelessWidget {
  const _TripsTimelineTabBar({
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<Tab> tabs;

  @override
  Widget build(BuildContext context) {
    return TabBar(controller: controller, tabs: tabs);
  }
}

class _TripsTimelineList extends StatelessWidget {
  const _TripsTimelineList({
    required this.category,
    required this.trips,
    required this.emptyMessage,
    required this.onOpenTrip,
  });

  final _TripTimelineCategory category;
  final List<Trip> trips;
  final String emptyMessage;
  final ValueChanged<String> onOpenTrip;

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTokens.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 140),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        final dateLine = formatTripDateRangeCompact(
          context,
          trip.startDate,
          trip.endDate,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _TripCard(
            trip: trip,
            category: category,
            dateLine: dateLine,
            onTap: () => onOpenTrip(trip.id),
          ),
        );
      },
    );
  }
}

class _TripCard extends ConsumerWidget {
  const _TripCard({
    required this.trip,
    required this.category,
    required this.dateLine,
    required this.onTap,
  });

  final Trip trip;
  final _TripTimelineCategory category;
  final String dateLine;
  final VoidCallback onTap;

  bool get _isPast => category == _TripTimelineCategory.past;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countersAsync = ref.watch(tripNotificationCountersProvider(trip.id));
    final unreadCount = countersAsync.asData?.value?.tripShellUnreadTotal ?? 0;
    final l10n = AppLocalizations.of(context)!;
    final metaStyle = Theme.of(context).textTheme.bodySmall;

    Widget meta(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              Icon(icon, size: 14, color: AppTokens.outline),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle,
                ),
              ),
            ],
          ),
        );

    return Opacity(
      opacity: _isPast ? 0.8 : 1.0,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _TripCardLeadingImage(
                  imageUrl: trip.bannerImageUrl?.isNotEmpty == true
                      ? trip.bannerImageUrl
                      : (trip.linkPreview['imageUrl'] as String?)?.trim(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (dateLine.isNotEmpty)
                        meta(Icons.calendar_today_rounded, dateLine),
                      if (trip.destination.trim().isNotEmpty)
                        meta(Icons.place_outlined, trip.destination),
                      meta(
                        Icons.group_outlined,
                        l10n.tripsMemberCount(
                          trip.participantCount ?? trip.memberUserIds.length,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unreadCount > 0)
                  Badge.count(count: unreadCount)
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTokens.outline,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TripCardLeadingImage extends StatelessWidget {
  const _TripCardLeadingImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final cleanUrl = (imageUrl ?? '').trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 60,
        height: 60,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTokens.primary,
              AppTokens.secondary,
            ],
          ),
        ),
        child: cleanUrl.isNotEmpty
            ? Image.network(
                cleanUrl,
                fit: BoxFit.cover,
                width: 60,
                height: 60,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.landscape_outlined,
                    color: Colors.white,
                    size: 26,
                  );
                },
              )
            : const Icon(
                Icons.landscape_outlined,
                color: Colors.white,
                size: 26,
              ),
      ),
    );
  }
}
