import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

enum _RouteMapApp { googleMaps, waze }

Future<void> openRouteInMapAppsSelector(
  BuildContext context, {
  required String destinationAddress,
  String? originAddress,
}) async {
  final destination = destinationAddress.trim();
  if (destination.isEmpty) return;
  final origin = (originAddress ?? '').trim();

  final app = await showModalBottomSheet<_RouteMapApp>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: Text(AppLocalizations.of(ctx)!.openRouteGoogleMaps),
            onTap: () => Navigator.of(ctx).pop(_RouteMapApp.googleMaps),
          ),
          ListTile(
            leading: const Icon(Icons.navigation_outlined),
            title: Text(AppLocalizations.of(ctx)!.openRouteWaze),
            onTap: () => Navigator.of(ctx).pop(_RouteMapApp.waze),
          ),
        ],
      ),
    ),
  );
  if (app == null || !context.mounted) return;

  final didLaunch = await switch (app) {
    _RouteMapApp.googleMaps => _openGoogleMapsRoute(
        destinationAddress: destination,
        originAddress: origin,
      ),
    _RouteMapApp.waze => _openWazeRoute(destinationAddress: destination),
  };

  if (!didLaunch && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.locationOpenImpossible),
      ),
    );
  }
}

Future<bool> _openGoogleMapsRoute({
  required String destinationAddress,
  required String originAddress,
}) async {
  final appParams = <String, String>{
    'daddr': destinationAddress,
    'directionsmode': 'driving',
    if (originAddress.isNotEmpty) 'saddr': originAddress,
  };
  final appUri = Uri.parse('comgooglemaps://?${Uri(queryParameters: appParams).query}');
  final webUri = Uri.https(
    'www.google.com',
    '/maps/dir/',
    <String, String>{
      'api': '1',
      'destination': destinationAddress,
      if (originAddress.isNotEmpty) 'origin': originAddress,
      'travelmode': 'driving',
    },
  );
  return _launchPreferNativeThenWeb(appUri: appUri, webUri: webUri);
}

Future<bool> _openWazeRoute({
  required String destinationAddress,
}) async {
  final appUri = Uri.parse(
    'waze://?${Uri(queryParameters: {'q': destinationAddress, 'navigate': 'yes'}).query}',
  );
  final webUri = Uri.https(
    'www.waze.com',
    '/ul',
    <String, String>{
      'q': destinationAddress,
      'navigate': 'yes',
    },
  );
  return _launchPreferNativeThenWeb(appUri: appUri, webUri: webUri);
}

Future<bool> _launchPreferNativeThenWeb({
  required Uri appUri,
  required Uri webUri,
}) async {
  if (!kIsWeb) {
    final openedNative = await launchUrl(
      appUri,
      mode: LaunchMode.externalApplication,
    );
    if (openedNative) return true;
  }
  return launchUrl(
    webUri,
    mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
  );
}
