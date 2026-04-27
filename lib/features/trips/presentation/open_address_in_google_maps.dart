import 'package:flutter/material.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [address] in Google Maps search (same behaviour as trip overview).
Future<void> openAddressInGoogleMaps(
  BuildContext context,
  String address,
) async {
  final query = address.trim();
  if (query.isEmpty) return;

  final mapsUri = Uri.https(
    'www.google.com',
    '/maps/search/',
    <String, String>{
      'api': '1',
      'query': query,
    },
  );

  final didLaunch = await launchUrl(
    mapsUri,
    mode: LaunchMode.platformDefault,
  );

  if (!didLaunch && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.locationOpenImpossible)),
    );
  }
}
