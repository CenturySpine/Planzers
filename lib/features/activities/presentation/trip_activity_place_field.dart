import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/core/presentation/osm_map.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_place_picker_page.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// A point of the trip to open the place picker on when the activity has
/// none: the one of the latest located activity ([activities] newest first).
GeoPoint? tripActivitiesFallbackCenter(Iterable<TripActivity> activities) {
  for (final activity in activities) {
    final point = activity.location ?? activity.departureLocation;
    if (point != null) return point;
  }
  return null;
}

/// The points to show for an activity: its place, or a transport's
/// departure then arrival.
List<LatLng> tripActivityMapPoints(TripActivity activity) => [
      if (activity.departureLocation != null)
        activity.departureLocation!.toLatLng(),
      if (activity.location != null) activity.location!.toLatLng(),
    ];

/// Address field of an activity form with a button opening the place
/// picker; once a point is set, a small map shows it under the field.
class TripActivityPlaceField extends StatelessWidget {
  const TripActivityPlaceField({
    super.key,
    required this.tripId,
    required this.controller,
    required this.location,
    required this.onLocationChanged,
    required this.labelText,
    this.hintText,
    this.fallbackCenter,
    this.textInputAction = TextInputAction.next,
  });

  /// The trip whose places the picker offers first.
  final String tripId;
  final TextEditingController controller;
  final GeoPoint? location;
  final ValueChanged<GeoPoint?> onLocationChanged;
  final String labelText;
  final String? hintText;

  /// Where the picker opens when no point is set.
  final GeoPoint? fallbackCenter;
  final TextInputAction textInputAction;

  Future<void> _pick(BuildContext context) async {
    final picked = await TripPlacePickerPage.open(
      context,
      tripId: tripId,
      initialPoint: location?.toLatLng(),
      initialCenter: fallbackCenter?.toLatLng(),
      initialAddress: controller.text,
    );
    if (picked == null) return;
    if (picked.address.isNotEmpty) controller.text = picked.address;
    onLocationChanged(GeoPoint(picked.lat, picked.lng));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final point = location;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          textInputAction: textInputAction,
          decoration: InputDecoration(
            labelText: labelText,
            hintText: hintText,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: l10n.activitiesPlacePickOnMap,
              onPressed: () => _pick(context),
              icon: Icon(
                point == null
                    ? PhosphorIconsRegular.mapPin
                    : PhosphorIconsFill.mapPin,
              ),
            ),
          ),
          minLines: 1,
          maxLines: 3,
        ),
        if (point != null) ...[
          const SizedBox(height: 8),
          Stack(
            children: [
              TripActivityMapPreview(
                points: [point.toLatLng()],
                onTap: () => _pick(context),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton.filledTonal(
                  tooltip: l10n.activitiesPlaceRemoveLocation,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onLocationChanged(null),
                  icon: const Icon(PhosphorIconsRegular.x, size: 18),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Small still map of an activity: its point, or a transport's departure
/// and arrival joined by a line.
class TripActivityMapPreview extends StatelessWidget {
  const TripActivityMapPreview({
    super.key,
    required this.points,
    this.height = 150,
    this.onTap,
  });

  /// One point, or a departure then an arrival.
  final List<LatLng> points;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;
    final isRoute = points.length > 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          // Recentres the map when the points change.
          key: ValueKey(
            points.map((p) => '${p.latitude},${p.longitude}').join('|'),
          ),
          options: MapOptions(
            initialCenter: points.last,
            initialZoom: 14,
            initialCameraFit: isRoute
                ? CameraFit.coordinates(
                    coordinates: points,
                    padding: const EdgeInsets.all(40),
                    maxZoom: 15,
                  )
                : null,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
            onTap: onTap == null ? null : (_, __) => onTap!(),
          ),
          children: [
            osmTileLayer(),
            if (isRoute)
              PolylineLayer(
                polylines: [
                  Polyline(points: points, color: color, strokeWidth: 3),
                ],
              ),
            MarkerLayer(
              markers: [
                if (isRoute)
                  Marker(
                    point: points.first,
                    width: 16,
                    height: 16,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: surface,
                        border: Border.all(color: color, width: 3),
                      ),
                    ),
                  ),
                osmPinMarker(points.last, color),
              ],
            ),
            const OsmMapAttribution(),
          ],
        ),
      ),
    );
  }
}
