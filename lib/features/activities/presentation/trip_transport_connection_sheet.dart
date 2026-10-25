import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/presentation/osm_map.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_place_field.dart';
import 'package:planerz/features/activities/presentation/trip_transport_connection.dart';
import 'package:planerz/features/activities/presentation/trip_transport_mode_presentation.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Asks where [transport] stops for a connection and how the journey goes
/// on from there, then cuts it in two: up to the stop, then from the stop to
/// its arrival. Only for [canAddTripTransportConnection].
Future<void> showTripTransportConnectionSheet(
  BuildContext context, {
  required String tripId,
  required TripActivity transport,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final connection = await showModalBottomSheet<_Connection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ConnectionSheet(tripId: tripId, transport: transport),
  );
  if (connection == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final repository = ProviderScope.containerOf(context, listen: false)
      .read(activitiesRepositoryProvider);
  String name(String value) => value.isEmpty ? l10n.activitiesUntitled : value;
  final labels = tripTransportConnectionLabels(
    label: transport.label.trim(),
    stopName: name(tripTransportPlaceName(connection.address)),
    arrivalName: name(tripTransportPlaceName(transport.address)),
    routeLabel: l10n.activitiesMissingTransportLabel,
  );
  final schedule = tripTransportConnectionSchedule(
    transport,
    stop: connection.location.toLatLng(),
    mode: connection.mode,
  );
  try {
    // The first part is shortened before the second is added: should a
    // later write fail, the rest of the way shows as a transport to fill in.
    await repository.updateActivity(
      tripId: tripId,
      activityId: transport.id,
      label: labels.first,
      category: transport.category,
      linkUrl: transport.linkUrl,
      address: connection.address,
      freeComments: transport.freeComments,
      location: connection.location,
      departureAddress: transport.departureAddress,
      departureLocation: transport.departureLocation,
      transportMode: transport.transportMode,
    );
    await repository.setActivityDuration(
      tripId: tripId,
      activityId: transport.id,
      durationMinutes: schedule.firstMinutes,
    );
    await repository.addActivity(
      tripId: tripId,
      label: labels.second,
      category: TripActivityCategory.transport,
      linkUrl: '',
      address: transport.address,
      freeComments: '',
      plannedAt: schedule.secondStart,
      durationMinutes: schedule.secondMinutes,
      location: transport.location,
      departureAddress: connection.address,
      departureLocation: connection.location,
      transportMode: connection.mode,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.activitiesTransportConnectionAdded)),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
    );
  }
}

/// Where the connection is and how the journey goes on from there.
typedef _Connection = ({
  String address,
  GeoPoint location,
  TripTransportMode mode,
});

class _ConnectionSheet extends StatefulWidget {
  const _ConnectionSheet({required this.tripId, required this.transport});

  final String tripId;
  final TripActivity transport;

  @override
  State<_ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<_ConnectionSheet> {
  final _addressController = TextEditingController();
  GeoPoint? _location;
  TripTransportMode? _mode;

  @override
  void initState() {
    super.initState();
    _addressController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final address = _addressController.text.trim();
    final location = _location;
    final mode = _mode;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            l10n.activitiesTransportConnectionAdd,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TripActivityPlaceField(
            tripId: widget.tripId,
            controller: _addressController,
            location: location,
            onLocationChanged: (point) => setState(() => _location = point),
            labelText: l10n.activitiesTransportConnectionStop,
            fallbackCenter: widget.transport.departureLocation,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.activitiesTransportConnectionMode,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          TripTransportModeChips(
            value: mode,
            onChanged: (value) => setState(() => _mode = value),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: address.isEmpty || location == null || mode == null
                    ? null
                    : () => Navigator.of(context).pop<_Connection>(
                          (
                            address: address,
                            location: location,
                            mode: mode,
                          ),
                        ),
                child: Text(l10n.commonAdd),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
