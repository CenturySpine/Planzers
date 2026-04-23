import 'package:planerz/core/firebase/firebase_target.dart';

/// Optional full invite base URL (path `/invite` included or not — normalized below).
/// When set, used for mobile invite links regardless of [FirebaseTarget].
const String _kInviteBaseUrlOverride = String.fromEnvironment('INVITE_BASE_URL');

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

/// Base URI for `/invite?…` when sharing from **mobile** (iOS/Android/desktop native).
///
/// Web builds use [Uri.base.origin] in the repository so deploy URL matches automatically.
Uri mobileInviteBaseUriForTarget(FirebaseTarget target) {
  final override = _kInviteBaseUrlOverride.trim();
  if (override.isNotEmpty) {
    final parsed = Uri.parse(override);
    return _asInviteBase(parsed);
  }

  final origin = switch (target) {
    FirebaseTarget.prod => _kProdPublicAppOrigin,
    FirebaseTarget.preview => _kPreviewPublicAppOrigin,
  };
  return _asInviteBase(Uri.parse(origin.trim()));
}

Uri _asInviteBase(Uri originOrFull) {
  if (originOrFull.path == '/invite' || originOrFull.path.endsWith('/invite')) {
    return originOrFull;
  }
  return originOrFull.replace(path: '/invite');
}
