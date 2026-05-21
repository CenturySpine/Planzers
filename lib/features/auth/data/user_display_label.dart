import 'package:firebase_auth/firebase_auth.dart';
import 'package:planerz/features/trips/data/trip_member.dart';

/// Local part of [email] for compact labels (text before '@').
///
/// If [email] has no '@', returns the trimmed string as-is.
String displayLabelFromEmail(String email) {
  final e = email.trim();
  if (e.isEmpty) return '';
  final at = e.indexOf('@');
  if (at <= 0) return e;
  return e.substring(0, at).trim();
}

/// Masked phone-based label for compact fallback display.
///
/// Keeps country code when present and reveals only last 2 digits.
String displayLabelFromPhoneNumber(String phoneNumber) {
  final rawPhoneNumber = phoneNumber.trim();
  if (rawPhoneNumber.isEmpty) return '';

  final phoneDigits = rawPhoneNumber.replaceAll(RegExp(r'\D'), '');
  if (phoneDigits.isEmpty) return '';
  if (phoneDigits.length < 2) return rawPhoneNumber;

  final lastTwoDigits = phoneDigits.substring(phoneDigits.length - 2);
  final countryCodeMatch = RegExp(r'^\+\d+').firstMatch(rawPhoneNumber);
  final countryCodePrefix = countryCodeMatch?.group(0) ?? '';
  final prefix =
      countryCodePrefix.isNotEmpty ? '$countryCodePrefix ' : '';
  return '$prefix•• •• •• $lastTwoDigits';
}

/// First uppercase character used for avatar fallback.
String avatarInitialFromDisplayLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed[0].toUpperCase();
}

bool _isGoogleHostedPhotoUrl(String url) {
  final raw = url.trim();
  if (raw.isEmpty) return false;
  final uri = Uri.tryParse(raw);
  final host = uri?.host.toLowerCase() ?? '';
  return host.contains('googleusercontent.com') ||
      host.contains('google.com') ||
      host.contains('ggpht.com');
}

/// Canonical profile badge URL from our own user profile data.
///
/// We intentionally reject Google-hosted URLs to avoid calling third-party
/// avatar hosts from participant lists.
String tripMemberStoredProfileBadgeUrl(Map<String, dynamic>? data) {
  if (data == null) return '';
  final account = (data['account'] as Map<String, dynamic>?) ?? const {};
  final accountPhoto = (account['photoUrl'] as String?)?.trim() ?? '';
  if (accountPhoto.isNotEmpty && !_isGoogleHostedPhotoUrl(accountPhoto)) {
    return accountPhoto;
  }
  return '';
}

/// Display name for a [TripMember]: always [TripMember.participantName].
String resolveTripMemberDisplayLabel(TripMember member) {
  return member.participantName;
}

/// Profile badge URL for a [TripMember].
///
/// Returns '' for unclaimed members (no [TripMember.userId]).
/// For claimed members, looks up [userDocsById] by UID.
String resolveTripMemberBadgeUrl(
  TripMember member,
  Map<String, Map<String, dynamic>> userDocsById,
) {
  final uid = member.userId;
  if (uid == null || uid.trim().isEmpty) return '';
  return tripMemberStoredProfileBadgeUrl(userDocsById[uid]);
}

/// Display labels for all [members], keyed by TripMember document ID.
Map<String, String> tripMemberLabelsFromMembers(List<TripMember> members) {
  return {for (final m in members) m.id: m.participantName};
}

/// Badge URLs for all [members], keyed by TripMember document ID.
/// Only claimed members (userId != null) may have a photo.
Map<String, String> tripMemberBadgeUrlsFromMembers(
  List<TripMember> members,
  Map<String, Map<String, dynamic>> userDocsById,
) {
  return {
    for (final m in members)
      m.id: resolveTripMemberBadgeUrl(m, userDocsById),
  };
}

/// When the current user's participant doc is not yet loaded, use Auth
/// info to build a provisional display name for their own badge.
///
/// Returns null if no usable identity is available.
Map<String, dynamic>? tripMemberUserDataWithAuthFallback(
  String? userId,
  Map<String, Map<String, dynamic>> userDocsById,
) {
  final uid = userId?.trim() ?? '';
  if (uid.isEmpty) return null;
  final existing = userDocsById[uid];
  if (existing != null) return existing;

  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser?.uid != uid) return null;

  final email = currentUser?.email?.trim() ?? '';
  final phoneNumber = currentUser?.phoneNumber?.trim() ?? '';
  var fallbackName = '';
  if (email.isNotEmpty) {
    fallbackName = displayLabelFromEmail(email);
  } else if (phoneNumber.isNotEmpty) {
    fallbackName = displayLabelFromPhoneNumber(phoneNumber);
  }
  if (fallbackName.isEmpty) return null;
  return {
    'email': email,
    'phoneNumber': phoneNumber,
    'account': <String, dynamic>{
      'email': email,
      'phoneNumber': phoneNumber,
      'name': fallbackName,
    },
  };
}
