import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/core/presentation/pz_components.dart';
import 'package:planerz/features/trips/data/trip_lodging.dart';
import 'package:planerz/features/trips/data/trip_lodging_plan.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/features/trips/presentation/open_route_in_map_apps.dart';
import 'package:planerz/features/trips/presentation/trip_overview_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// `Du lun. 12 juil. au mer. 14 juil. · 2 nuits`, or `Toutes les nuits`
/// when the trip has no dates.
String tripLodgingNightsLabel(
  BuildContext context, {
  required DateTime? firstNight,
  required DateTime? checkOutDay,
}) {
  final l10n = AppLocalizations.of(context)!;
  if (firstNight == null || checkOutDay == null) {
    return l10n.tripLodgingEveryNight;
  }
  final format =
      DateFormat('EEE d MMM', Localizations.localeOf(context).toString());
  return l10n.tripLodgingNightsRange(
    format.format(firstNight),
    format.format(checkOutDay),
    checkOutDay.difference(firstNight).inDays,
  );
}

String tripLodgingStageDatesLabel(
  BuildContext context,
  TripLodgingStage stage,
) =>
    tripLodgingNightsLabel(
      context,
      firstNight: stage.firstNight,
      checkOutDay: stage.checkOutDay,
    );

/// Where directions to [lodging] lead: its address, else the place found
/// for its map link.
String tripLodgingDirectionsTarget(TripLodging lodging) {
  final address = lodging.address.trim();
  if (address.isNotEmpty) return address;
  final location = lodging.location;
  if (location != null) return '${location.latitude},${location.longitude}';
  if (lodging.linkPreview['isGoogleMaps'] == true) {
    return ((lodging.linkPreview['description'] as String?) ?? '').trim();
  }
  return '';
}

Future<void> openTripLodgingLink(BuildContext context, String url) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final parsedUrl = Uri.tryParse(url.trim());
  if (parsedUrl == null || !parsedUrl.isAbsolute) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.linkInvalid)));
    return;
  }
  final launched = await launchUrl(
    parsedUrl,
    mode: LaunchMode.platformDefault,
    webOnlyWindowName: '_blank',
  );
  if (!launched) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.linkOpenImpossible)));
  }
}

/// One stage of the trip's lodgings: its nights and where they are spent,
/// or a dashed card while they are not filled in.
class TripLodgingStageCard extends StatelessWidget {
  const TripLodgingStageCard({
    super.key,
    required this.stage,
    this.onTap,
  });

  final TripLodgingStage stage;

  /// Null leaves the card still.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lodging = stage.lodging;
    final datesLabel = tripLodgingStageDatesLabel(context, stage);
    if (lodging == null) {
      return TripOverviewDashedCard(
        onTap: onTap,
        child: Row(
          children: [
            const _TripLodgingIcon(
              icon: PhosphorIconsRegular.bed,
              background: AppTokens.surfaceMuted,
              color: AppTokens.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TripLodgingTexts(
                datesLabel: datesLabel,
                title: l10n.tripLodgingMissing,
                titleColor: AppTokens.onSurfaceVariant,
              ),
            ),
            if (onTap != null)
              const Icon(PhosphorIconsRegular.plus, color: AppTokens.primary),
          ],
        ),
      );
    }

    final directionsTarget = tripLodgingDirectionsTarget(lodging);
    final hasPreview =
        lodging.linkUrl.trim().isNotEmpty && lodging.linkPreview.isNotEmpty;
    return Material(
      color: AppTokens.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTokens.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (hasPreview)
                LinkPreviewThumbnail(preview: lodging.linkPreview, size: 58)
              else
                const _TripLodgingIcon(
                  icon: PhosphorIconsRegular.bed,
                  background: AppTokens.primarySoft,
                  color: AppTokens.primary,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: _TripLodgingTexts(
                  datesLabel: datesLabel,
                  title: lodging.displayTitle,
                  titleColor: AppTokens.deep,
                  subtitle: lodging.address.trim() != lodging.displayTitle
                      ? lodging.address.trim()
                      : '',
                ),
              ),
              if (directionsTarget.isNotEmpty)
                IconButton(
                  tooltip: l10n.tripOverviewOpenLocation,
                  icon: const Icon(PhosphorIconsRegular.signpost),
                  color: AppTokens.secondary,
                  onPressed: () => openRouteInMapAppsSelector(
                    context,
                    destinationAddress: directionsTarget,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripLodgingIcon extends StatelessWidget {
  const _TripLodgingIcon({
    required this.icon,
    required this.background,
    required this.color,
  });

  final IconData icon;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        width: 58,
        height: 58,
        child: Icon(icon, size: 26, color: color),
      ),
    );
  }
}

class _TripLodgingTexts extends StatelessWidget {
  const _TripLodgingTexts({
    required this.datesLabel,
    required this.title,
    required this.titleColor,
    this.subtitle = '',
  });

  final String datesLabel;
  final String title;
  final Color titleColor;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          datesLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTokens.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: titleColor,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppTokens.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The trip's lodging stages one card at a time, swiped or stepped through
/// with the arrows of the header.
class TripLodgingCarousel extends StatefulWidget {
  const TripLodgingCarousel({
    super.key,
    required this.title,
    required this.stages,
    required this.initialIndex,
    required this.onStageTap,
  });

  final String title;
  final List<TripLodgingStage> stages;

  /// Stage shown first, e.g. tonight's.
  final int initialIndex;

  /// Null for a stage to leave still.
  final VoidCallback? Function(TripLodgingStage stage) onStageTap;

  @override
  State<TripLodgingCarousel> createState() => _TripLodgingCarouselState();
}

class _TripLodgingCarouselState extends State<TripLodgingCarousel> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.stages.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.stages.length - 1);
    _controller = PageController(initialPage: _page);
  }

  @override
  void didUpdateWidget(covariant TripLodgingCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final last = widget.stages.length - 1;
    if (last >= 0 && _page > last) {
      _page = last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) _controller.jumpToPage(_page);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final count = widget.stages.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PzSectionHeader(
            title: widget.title,
            trailing: count > 1
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.tripLodgingPrevious,
                        visualDensity: VisualDensity.compact,
                        onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
                        icon: const Icon(PhosphorIconsRegular.caretLeft),
                      ),
                      Text(
                        '${_page + 1} / $count',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.tripLodgingNext,
                        visualDensity: VisualDensity.compact,
                        onPressed:
                            _page < count - 1 ? () => _goTo(_page + 1) : null,
                        icon: const Icon(PhosphorIconsRegular.caretRight),
                      ),
                    ],
                  )
                : null,
          ),
          SizedBox(
            height: 84,
            child: PageView.builder(
              controller: _controller,
              itemCount: count,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, index) {
                final stage = widget.stages[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: TripLodgingStageCard(
                    stage: stage,
                    onTap: widget.onStageTap(stage),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
