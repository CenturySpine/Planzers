import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/app_version_provider.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/features/about/presentation/about_page.dart';
import 'package:planerz/features/account/presentation/account_menu_button.dart';
import 'package:planerz/features/administration/data/maintenance_repository.dart';
import 'package:planerz/features/administration/presentation/admin_announcements_bell_button.dart';
import 'package:planerz/features/legal/presentation/legal_information_page.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/trips/presentation/join_trip_by_code_dialog.dart';
import 'package:planerz/features/trips/presentation/trip_create_page.dart';
import 'package:planerz/features/trips/presentation/trip_date_format.dart';
import 'package:planerz/l10n/app_localizations.dart';

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
  bool _isFabMenuOpen = false;
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final legalLinkColor = NeonPalette.onSurfaceVariant;
    final tripsAsync = ref.watch(tripsStreamProvider);
    final unreadByTripAsync = ref.watch(myTripUnreadTotalsProvider);
    final isApplicationOwner =
        ref.watch(isApplicationOwnerProvider).asData?.value ?? false;
    final showNonMemberTrips =
        ref.watch(applicationOwnerShowNonMemberTripsProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: NeonPalette.scaffoldBackground,
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.white)),
            Positioned.fill(
              top: 0,
              child: Image.asset(
                'assets/images/app_background.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            const Positioned.fill(child: _TripsBackgroundVeil()),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _TripsBrandHeader(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: _TripsPagePill(label: l10n.tripsMyTrips),
                ),
                if (isApplicationOwner)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _TripsFilterRow(
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
                Expanded(
                  child: tripsAsync.when(
                    data: (trips) {
                      final grouped = _groupTripsByTimeline(trips);
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
                                      context.push('/trips/$tripId/overview'),
                                ),
                                _TripsTimelineList(
                                  category: _TripTimelineCategory.ongoing,
                                  trips:
                                      grouped[_TripTimelineCategory.ongoing] ??
                                          const [],
                                  emptyMessage: l10n.tripsEmptyOngoing,
                                  onOpenTrip: (tripId) =>
                                      context.push('/trips/$tripId/overview'),
                                ),
                                _TripsTimelineList(
                                  category: _TripTimelineCategory.upcoming,
                                  trips:
                                      grouped[_TripTimelineCategory.upcoming] ??
                                          const [],
                                  emptyMessage: l10n.tripsEmptyUpcoming,
                                  onOpenTrip: (tripId) =>
                                      context.push('/trips/$tripId/overview'),
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
                        onPressed: () => context.push(AboutPage.routePath),
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
            if (_isFabMenuOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _isFabMenuOpen = false),
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                      child: ColoredBox(
                        color: NeonPalette.deep.withValues(alpha: 0.30),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 16,
              bottom: _speedDialBottomOffset,
              child: SafeArea(
                top: false,
                child: _TripsSpeedDial(
                isOpen: _isFabMenuOpen,
                joinLabel: l10n.tripsJoinWithInviteTooltip,
                createLabel: l10n.tripsNewTripTooltip,
                onToggle: () => setState(() => _isFabMenuOpen = !_isFabMenuOpen),
                onJoin: () {
                  setState(() => _isFabMenuOpen = false);
                  _openJoinByInviteCodeDialog(context);
                },
                onCreate: () {
                  setState(() => _isFabMenuOpen = false);
                  context.push(TripCreatePage.routePath);
                },
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

    _tabController =
        TabController(length: 3, vsync: this, initialIndex: 2);
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
    const countStyle = TextStyle(
      fontSize: 11,
      height: 1.0,
      fontWeight: FontWeight.w500,
    );
    return Tab(
      height: 44,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(label),
              if (unreadCount > 0) ...[
                const SizedBox(width: 6),
                Badge.count(
                  count: unreadCount,
                  backgroundColor: NeonPalette.accent,
                  child: const SizedBox(width: 10, height: 10),
                ),
              ],
            ],
          ),
          const SizedBox(height: 1),
          Text(
            '($tripCount)',
            style: countStyle.copyWith(
              color: NeonPalette.onSurfaceVariant.withValues(
                alpha: 0.7,
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

class _TripsBackgroundVeil extends StatelessWidget {
  const _TripsBackgroundVeil();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x8CFFFFFF),
            Color(0x4DFFFFFF),
            Color(0x8CFFFFFF),
          ],
          stops: [0.0, 0.30, 1.0],
        ),
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

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.9, -0.4),
          end: Alignment(1.0, 1.0),
          colors: [
            NeonPalette.deep,
            NeonPalette.primary,
            Color(0xFF5B6FC9),
          ],
          stops: [0.0, 0.72, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 66,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const _BrandAppIcon(),
                      const SizedBox(width: 11),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PLANERZ',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                          if (version != null || isPreview)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (version != null)
                                    Text(
                                      version,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.4,
                                        color: Colors.white.withValues(
                                          alpha: 0.6,
                                        ),
                                        height: 1,
                                      ),
                                    ),
                                  if (isPreview) ...[
                                    if (version != null)
                                      const SizedBox(width: 8),
                                    const Icon(
                                      Icons.science_outlined,
                                      size: 14,
                                      color: NeonPalette.accent,
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'preview',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.3,
                                        color: NeonPalette.accent,
                                        height: 1,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Theme(
                  data: Theme.of(context).copyWith(
                    iconTheme: const IconThemeData(color: Colors.white),
                  ),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.14),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child: AdminAnnouncementsBellButton(brandedHeader: true),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 10),
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                  ),
                  child: const AccountMenuButton(brandedHeader: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandAppIcon extends StatelessWidget {
  const _BrandAppIcon();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: NeonPalette.deep.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/images/app_icon.png',
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _TripsPagePill extends StatelessWidget {
  const _TripsPagePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NeonPalette.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: NeonPalette.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(
                width: 28,
                height: 28,
                child: Icon(
                  Icons.explore_outlined,
                  size: 18,
                  color: NeonPalette.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: NeonPalette.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripsFilterRow extends StatelessWidget {
  const _TripsFilterRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

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
              const Icon(
                Icons.groups_outlined,
                size: 18,
                color: NeonPalette.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: NeonPalette.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ),
              _TripsCompactSwitch(
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

class _TripsCompactSwitch extends StatelessWidget {
  const _TripsCompactSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 38,
        height: 22,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9999),
          color: value
              ? NeonPalette.primary
              : NeonPalette.onSurfaceVariant.withValues(alpha: 0.4),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
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
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            border: const Border(
              bottom: BorderSide(color: NeonPalette.divider),
            ),
          ),
          child: TabBar(
            controller: controller,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            dividerHeight: 0,
            labelColor: NeonPalette.primary,
            unselectedLabelColor: NeonPalette.onSurfaceVariant,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(
                color: NeonPalette.primary,
                width: 2,
              ),
              insets: EdgeInsets.symmetric(horizontal: 16),
            ),
            tabs: tabs,
          ),
        ),
      ),
    );
  }
}

class _TripsSpeedDial extends StatelessWidget {
  const _TripsSpeedDial({
    required this.isOpen,
    required this.joinLabel,
    required this.createLabel,
    required this.onToggle,
    required this.onJoin,
    required this.onCreate,
  });

  final bool isOpen;
  final String joinLabel;
  final String createLabel;
  final VoidCallback onToggle;
  final VoidCallback onJoin;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isOpen) ...[
          _SpeedDialAction(
            label: joinLabel,
            icon: Icons.vpn_key_outlined,
            isPrimary: false,
            onPressed: onJoin,
          ),
          const SizedBox(height: 12),
          _SpeedDialAction(
            label: createLabel,
            icon: Icons.add,
            isPrimary: true,
            onPressed: onCreate,
          ),
          const SizedBox(height: 14),
        ],
        Material(
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          color: isOpen
              ? NeonPalette.deep
              : NeonPalette.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedRotation(
              turns: isOpen ? 0.25 : 0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              child: SizedBox(
                width: 60,
                height: 60,
                child: Icon(
                  isOpen ? Icons.close : Icons.add,
                  size: 26,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeedDialAction extends StatelessWidget {
  const _SpeedDialAction({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final joinBorderColor = Color.lerp(
      NeonPalette.accent,
      NeonPalette.divider,
      0.68,
    )!;

    return Material(
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      color: isPrimary ? NeonPalette.primary : NeonPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isPrimary
            ? BorderSide.none
            : BorderSide(color: joinBorderColor, width: 1.5),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 0, 22, 0),
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: isPrimary ? 22 : 21,
                  color:
                      isPrimary ? Colors.white : NeonPalette.accent,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color:
                        isPrimary ? Colors.white : NeonPalette.accent,
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
              color: NeonPalette.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 110),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        final dateLine = formatTripDateRange(
          context,
          trip.startDate,
          trip.endDate,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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

  Color get _accentColor => switch (category) {
        _TripTimelineCategory.upcoming => NeonPalette.secondary,
        _TripTimelineCategory.ongoing => NeonPalette.primary,
        _TripTimelineCategory.past => NeonPalette.outline,
      };

  Color get _titleColor => category == _TripTimelineCategory.past
      ? NeonPalette.text700
      : NeonPalette.primary;

  double get _cardOpacity =>
      category == _TripTimelineCategory.past ? 0.92 : 1.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countersAsync = ref.watch(tripNotificationCountersProvider(trip.id));
    final unreadCount = countersAsync.asData?.value?.tripShellUnreadTotal ?? 0;

    return Opacity(
      opacity: _cardOpacity,
      child: Material(
        color: NeonPalette.surface,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: NeonPalette.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              height: 20 / 15,
                              fontWeight: FontWeight.w700,
                              color: _titleColor,
                            ),
                          ),
                          if (dateLine.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              dateLine,
                              style: const TextStyle(
                                fontSize: 12,
                                color: NeonPalette.deep,
                              ),
                            ),
                          ],
                          if (trip.destination.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              trip.destination,
                              style: const TextStyle(
                                fontSize: 12,
                                color: NeonPalette.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(context)!.tripsMemberCount(
                              trip.participantCount ??
                                  trip.memberUserIds.length,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: NeonPalette.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (unreadCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Badge.count(
                          count: unreadCount,
                          backgroundColor: NeonPalette.accent,
                          child: const Icon(
                            Icons.notifications_none_outlined,
                            color: NeonPalette.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  color: _accentColor,
                ),
              ),
            ],
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              NeonPalette.primary,
              NeonPalette.secondary,
            ],
          ),
        ),
        child: cleanUrl.isNotEmpty
            ? Image.network(
                cleanUrl,
                fit: BoxFit.cover,
                width: 64,
                height: 64,
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
