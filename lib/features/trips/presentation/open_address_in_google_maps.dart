import 'package:flutter/material.dart';
import 'package:planerz/features/trips/presentation/open_route_in_map_apps.dart';

/// Opens driving directions to [address] via the shared map-app selector.
Future<void> openAddressInGoogleMaps(
  BuildContext context,
  String address,
) {
  return openRouteInMapAppsSelector(
    context,
    destinationAddress: address,
  );
}
