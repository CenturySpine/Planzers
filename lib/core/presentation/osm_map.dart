import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Centre of France: where a map opens when no point is known.
const LatLng osmFranceCenter = LatLng(46.6, 2.4);

/// OpenStreetMap raster tiles shared by every map of the app (free, no key;
/// the OSMF tile policy asks for an identifying user agent).
TileLayer osmTileLayer() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'fr.centuryspine.planerz',
    );

/// The credit every map showing OpenStreetMap tiles must carry, on the map
/// itself (a credit only on a legal page is not enough). Add it as the last
/// child of a [FlutterMap].
class OsmMapAttribution extends StatelessWidget {
  const OsmMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SimpleAttributionWidget(
      source: Text(l10n.mapAttributionOsm),
      onTap: () => launchUrl(Uri.https('www.openstreetmap.org', '/copyright')),
    );
  }
}

/// A pin whose tip sits on [point].
Marker osmPinMarker(LatLng point, Color color) => Marker(
      point: point,
      width: 40,
      height: 40,
      alignment: Alignment.topCenter,
      child: Icon(PhosphorIconsFill.mapPin, color: color, size: 36),
    );

extension GeoPointLatLng on GeoPoint {
  LatLng toLatLng() => LatLng(latitude, longitude);
}

extension LatLngGeoPoint on LatLng {
  GeoPoint toGeoPoint() => GeoPoint(latitude, longitude);
}
