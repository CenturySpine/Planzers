import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/core/geocoding/pasted_coordinates.dart';
import 'package:planerz/core/geocoding/place_geocoding_client.dart';
import 'package:planerz/core/presentation/osm_map.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_journey.dart';
import 'package:planerz/features/activities/presentation/trip_missing_transport.dart';
import 'package:planerz/features/activities/presentation/trip_missing_transport_sheet.dart';
import 'package:planerz/features/activities/presentation/trip_transport_mode_presentation.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// The trip drawn on a map, for the whole trip or one day.
class TripJourneyMapPage extends ConsumerWidget {
  const TripJourneyMapPage({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final activitiesAsync = ref.watch(tripActivitiesStreamProvider(tripId));
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final trip = ref.watch(tripStreamProvider(tripId)).asData?.value;
    final canSuggest =
        trip != null && canSuggestActivityForTrip(trip: trip, userId: myUid);
    final canPlan =
        trip != null && canPlanActivityForTrip(trip: trip, userId: myUid);
    final activities = activitiesAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.activitiesJourneyMapTitle)),
      body: activitiesAsync.hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.commonErrorWithDetails(activitiesAsync.error.toString()),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : activities == null
              ? const Center(child: CircularProgressIndicator())
              : TripJourneyMapView(
                  tripId: tripId,
                  activities: activities,
                  canSuggestActivity: canSuggest,
                  canPlanActivity: canPlan,
                ),
    );
  }
}

/// Planned activities numbered in time order, transports and plain links
/// between places, with a day selector. A long press (or a right click)
/// proposes to add an activity there when [canSuggestActivity]. Links long
/// enough to call for a transport are dashed, with a button to add it when
/// the member can also plan.
class TripJourneyMapView extends ConsumerStatefulWidget {
  const TripJourneyMapView({
    super.key,
    required this.tripId,
    required this.activities,
    required this.canSuggestActivity,
    required this.canPlanActivity,
  });

  final String tripId;
  final List<TripActivity> activities;
  final bool canSuggestActivity;
  final bool canPlanActivity;

  @override
  ConsumerState<TripJourneyMapView> createState() => _TripJourneyMapViewState();
}

class _TripJourneyMapViewState extends ConsumerState<TripJourneyMapView> {
  /// Null shows the whole trip.
  DateTime? _day;

  /// Activities of the marker tapped: the stops of a place, or a transport.
  List<String> _selectedIds = const [];

  /// Point long-pressed to add an activity, with its address once found.
  LatLng? _pending;
  String _pendingAddress = '';
  bool _resolvingAddress = false;
  int _reverseSeq = 0;

  void _clearSelection() {
    _reverseSeq++;
    setState(() {
      _selectedIds = const [];
      _pending = null;
      _resolvingAddress = false;
    });
  }

  void _select(List<String> ids) {
    _reverseSeq++;
    setState(() {
      _selectedIds = ids;
      _pending = null;
      _resolvingAddress = false;
    });
  }

  Future<void> _dropPending(LatLng point) async {
    final seq = ++_reverseSeq;
    setState(() {
      _selectedIds = const [];
      _pending = point;
      _pendingAddress = '';
      _resolvingAddress = true;
    });
    final place = await ref.read(placeGeocodingClientProvider).reverse(
          lat: point.latitude,
          lng: point.longitude,
          languageCode: Localizations.localeOf(context).languageCode,
        );
    if (!mounted || seq != _reverseSeq) return;
    setState(() {
      _pendingAddress = place?.address ?? '';
      _resolvingAddress = false;
    });
  }

  void _addActivityAtPending() {
    final point = _pending;
    if (point == null) return;
    final day = _day;
    final uri = Uri(
      path: '/trips/${widget.tripId}/activities/new',
      queryParameters: {
        'lat': '${point.latitude}',
        'lng': '${point.longitude}',
        if (_pendingAddress.isNotEmpty) 'address': _pendingAddress,
        if (day != null) 'day': DateFormat('yyyy-MM-dd').format(day),
      },
    );
    _clearSelection();
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final activities = widget.activities;
    final canSuggest = widget.canSuggestActivity;
    final days = tripJourneyDays(activities);
    final day = days.contains(_day) ? _day : null;
    final journey = buildTripJourney(activities, day: day);
    final points = journey.points;
    final numbers = {
      for (final stop in journey.stops) stop.activity.id: stop.number,
    };
    final missingByLink = {
      for (final missing in tripMissingTransports(journey))
        _linkKey(missing.from, missing.to): missing,
    };
    final canAddTransport = canSuggest && widget.canPlanActivity;
    final selected = [
      for (final id in _selectedIds)
        ...activities.where((activity) => activity.id == id),
    ];
    final pending = _pending;
    final linkColor = Theme.of(context).colorScheme.outline;
    final transportColor = ActivityFilterGroup.trajets.filterColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _JourneyDayChips(
          days: days,
          selected: day,
          onSelected: (value) {
            _reverseSeq++;
            setState(() {
              _day = value;
              _selectedIds = const [];
              _pending = null;
            });
          },
        ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                // Frames the map again on the places of the chosen day.
                key: ValueKey(day),
                options: MapOptions(
                  initialCenter:
                      points.isEmpty ? osmFranceCenter : points.first,
                  initialZoom: points.isEmpty ? 5 : 14,
                  initialCameraFit: points.toSet().length > 1
                      ? CameraFit.coordinates(
                          coordinates: points,
                          padding: const EdgeInsets.fromLTRB(48, 48, 48, 140),
                          maxZoom: 15,
                        )
                      : null,
                  onTap: (_, __) => _clearSelection(),
                  onLongPress:
                      canSuggest ? (_, point) => _dropPending(point) : null,
                  onSecondaryTap:
                      canSuggest ? (_, point) => _dropPending(point) : null,
                ),
                children: [
                  osmTileLayer(),
                  PolylineLayer(
                    polylines: [
                      for (final leg in journey.legs)
                        if (leg.transport == null)
                          _missingFor(leg, missingByLink) == null
                              ? Polyline(
                                  points: [leg.from, leg.to],
                                  color: linkColor,
                                  strokeWidth: 2,
                                )
                              : Polyline(
                                  points: [leg.from, leg.to],
                                  color: linkColor,
                                  strokeWidth: 3,
                                  pattern: StrokePattern.dashed(
                                    segments: const [8, 6],
                                  ),
                                ),
                      for (final leg in journey.legs)
                        if (leg.transport != null)
                          Polyline(
                            points: [leg.from, leg.to],
                            color: transportColor,
                            strokeWidth: 4,
                            // A flight is not drawn along its real route.
                            pattern: leg.transport!.transportMode ==
                                    TripTransportMode.plane
                                ? StrokePattern.dashed(segments: const [12, 8])
                                : const StrokePattern.solid(),
                          ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      for (final leg in journey.legs)
                        if (leg.transport != null)
                          Marker(
                            point: LatLng(
                              (leg.from.latitude + leg.to.latitude) / 2,
                              (leg.from.longitude + leg.to.longitude) / 2,
                            ),
                            width: 30,
                            height: 30,
                            child: _JourneyMarker(
                              color: transportColor,
                              selected:
                                  _selectedIds.contains(leg.transport!.id),
                              onTap: () => _select([leg.transport!.id]),
                              child: Icon(
                                leg.transport!.displayIcon,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      if (canAddTransport)
                        for (final missing in missingByLink.values)
                          Marker(
                            point: LatLng(
                              (missing.fromPoint.latitude +
                                      missing.toPoint.latitude) /
                                  2,
                              (missing.fromPoint.longitude +
                                      missing.toPoint.longitude) /
                                  2,
                            ),
                            width: 28,
                            height: 28,
                            child: _JourneyMarker(
                              color: linkColor,
                              selected: false,
                              onTap: () => showTripMissingTransportSheet(
                                context,
                                tripId: widget.tripId,
                                missing: missing,
                              ),
                              child: const Icon(
                                PhosphorIconsRegular.plus,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      for (final place in journey.places) _placeMarker(place),
                      if (pending != null)
                        osmPinMarker(
                          pending,
                          Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                  const OsmMapAttribution(),
                ],
              ),
              if (journey.isEmpty)
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text(l10n.activitiesJourneyEmpty),
                      ),
                    ),
                  ),
                ),
              if (selected.isNotEmpty || pending != null)
                Positioned(
                  left: 12,
                  right: 12,
                  // Leaves the OpenStreetMap credit visible.
                  bottom: 36,
                  child: selected.isNotEmpty
                      ? _SelectedActivitiesCard(
                          activities: selected,
                          numbers: numbers,
                          onOpen: (activity) => context.push(
                            '/trips/${widget.tripId}/activities/${activity.id}',
                          ),
                        )
                      : _PendingPlaceCard(
                          address: _pendingAddress.isNotEmpty
                              ? _pendingAddress
                              : formatCoordinates(
                                  pending!.latitude,
                                  pending.longitude,
                                ),
                          resolving: _resolvingAddress,
                          onAdd: _addActivityAtPending,
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _linkKey(TripActivity from, TripActivity to) =>
      '${from.id}>${to.id}';

  static TripMissingTransport? _missingFor(
    TripJourneyLeg leg,
    Map<String, TripMissingTransport> missingByLink,
  ) {
    final from = leg.fromActivity;
    final to = leg.toActivity;
    if (from == null || to == null) return null;
    return missingByLink[_linkKey(from, to)];
  }

  Marker _placeMarker(TripJourneyPlace place) {
    final label = place.numbersLabel;
    final ids = [for (final stop in place.stops) stop.activity.id];
    return Marker(
      point: place.point,
      width: label.length <= 1 ? 30 : 18 + 8.0 * label.length,
      height: 30,
      child: _JourneyMarker(
        color: place.stops.first.activity.category.filterGroup.filterColor,
        selected: ids.any(_selectedIds.contains),
        onTap: () => _select(ids),
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// "Whole trip" then one chip per day with places.
class _JourneyDayChips extends StatelessWidget {
  const _JourneyDayChips({
    required this.days,
    required this.selected,
    required this.onSelected,
  });

  final List<DateTime> days;
  final DateTime? selected;
  final ValueChanged<DateTime?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final format =
        DateFormat('EEE d MMM', Localizations.localeOf(context).toString());
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        children: [
          ChoiceChip(
            label: Text(l10n.activitiesJourneyAllTrip),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final day in days) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text(format.format(day)),
              selected: selected == day,
              onSelected: (_) => onSelected(day),
            ),
          ],
        ],
      ),
    );
  }
}

/// Marker of a place (its stop numbers) or of a transport (its mode).
class _JourneyMarker extends StatelessWidget {
  const _JourneyMarker({
    required this.color,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.white,
            width: selected ? 3 : 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

/// The activities of the marker tapped, each opening its page.
class _SelectedActivitiesCard extends StatelessWidget {
  const _SelectedActivitiesCard({
    required this.activities,
    required this.numbers,
    required this.onOpen,
  });

  final List<TripActivity> activities;

  /// Stop number per activity id (transports have none).
  final Map<String, int> numbers;
  final ValueChanged<TripActivity> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dateFormat = DateFormat(
      'EEE d MMM HH:mm',
      Localizations.localeOf(context).toString(),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            for (final activity in activities)
              ListTile(
                onTap: () => onOpen(activity),
                leading: CircleAvatar(
                  backgroundColor: activity.category.filterGroup.filterColor,
                  foregroundColor: Colors.white,
                  child: Icon(activity.displayIcon, size: 20),
                ),
                title: Text(
                  [
                    if (numbers[activity.id] != null)
                      '${numbers[activity.id]}.',
                    activity.label.trim().isEmpty
                        ? l10n.activitiesUntitled
                        : activity.label.trim(),
                  ].join(' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: activity.plannedAt == null
                    ? null
                    : Text(dateFormat.format(activity.plannedAt!.toLocal())),
                trailing: const Icon(PhosphorIconsRegular.caretRight),
              ),
          ],
        ),
      ),
    );
  }
}

class _PendingPlaceCard extends StatelessWidget {
  const _PendingPlaceCard({
    required this.address,
    required this.resolving,
    required this.onAdd,
  });

  final String address;
  final bool resolving;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(PhosphorIconsFill.mapPin, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: resolving
                      ? const LinearProgressIndicator()
                      : Text(address),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: resolving ? null : onAdd,
              icon: const Icon(PhosphorIconsRegular.plus),
              label: Text(l10n.activitiesJourneyAddHere),
            ),
          ],
        ),
      ),
    );
  }
}
