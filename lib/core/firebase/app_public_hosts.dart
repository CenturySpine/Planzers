import 'package:planerz/core/firebase/firebase_target.dart';

/// Optional full public app base URL override.
///
/// Backward compatibility: keeps reading `INVITE_BASE_URL` because existing
/// environments may still define it.
const String _kPublicAppBaseUrlOverride = String.fromEnvironment(
  'INVITE_BASE_URL',
);

/// Production web app origin (scheme + host, optional port). No trailing slash.
const String _kProdPublicAppOrigin = String.fromEnvironment(
  'PROD_PUBLIC_APP_ORIGIN',
  defaultValue: 'https://planerz.centuryspine.org',
);

/// Preview web app origin (Vercel preview, staging host, etc.).
const String _kPreviewPublicAppOrigin = String.fromEnvironment(
  'PREVIEW_PUBLIC_APP_ORIGIN',
  defaultValue: 'https://preview.planerz.centuryspine.org',
);

/// Public web app base URI for the selected Firebase target.
Uri publicAppBaseUriForTarget(FirebaseTarget target) {
  final override = _kPublicAppBaseUrlOverride.trim();
  if (override.isNotEmpty) {
    return Uri.parse(override);
  }

  final origin = switch (target) {
    FirebaseTarget.prod => _kProdPublicAppOrigin,
    FirebaseTarget.preview => _kPreviewPublicAppOrigin,
  };
  return Uri.parse(origin.trim());
}
