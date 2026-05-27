import 'package:planerz/features/trips/data/trip_member.dart';

/// Canonical child marker prepended to resolved participant display labels.
const String tripMemberChildLabelEmoji = '👶';

String _withChildLabelPrefix(String label, {required bool isChild}) {
  final trimmedLabel = label.trim();
  if (!isChild || trimmedLabel.isEmpty) {
    return trimmedLabel;
  }
  final canonicalPrefix = '$tripMemberChildLabelEmoji ';
  if (trimmedLabel.startsWith(canonicalPrefix)) {
    return trimmedLabel;
  }
  return '$canonicalPrefix$trimmedLabel';
}

String _stripChildLabelPrefix(String label) {
  final trimmedLabel = label.trim();
  final canonicalPrefix = '$tripMemberChildLabelEmoji ';
  if (trimmedLabel.startsWith(canonicalPrefix)) {
    return trimmedLabel.substring(canonicalPrefix.length).trimLeft();
  }
  return trimmedLabel;
}

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
  final trimmed = _stripChildLabelPrefix(label);
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

/// Resolved display name for a [TripMember].
///
/// When [member.useProfileName] is true and [profileData] contains a non-empty
/// account.name, that value is returned. Otherwise falls back to [member.participantName].
String resolveTripMemberDisplayLabel(
  TripMember member, {
  Map<String, dynamic>? profileData,
}) {
  String resolvedLabel;
  if (member.useProfileName && profileData != null) {
    final name = ((profileData['account'] as Map<String, dynamic>?) ?? const {})['name'] as String?;
    if (name != null && name.trim().isNotEmpty) {
      resolvedLabel = name.trim();
      return _withChildLabelPrefix(resolvedLabel, isChild: member.isChild);
    }
  }
  resolvedLabel = member.participantName;
  return _withChildLabelPrefix(resolvedLabel, isChild: member.isChild);
}

/// Display labels for all [members], keyed by TripMember document ID.
///
/// Pass [userDocsById] to enable profile-name resolution for members with [TripMember.useProfileName].
Map<String, String> tripMemberLabelsFromMembers(
  List<TripMember> members, {
  Map<String, Map<String, dynamic>> userDocsById = const {},
}) {
  return {
    for (final m in members)
      m.id: resolveTripMemberDisplayLabel(m, profileData: userDocsById[m.userId]),
  };
}

/// Extracts the account.name from a user profile document, or null if absent/empty.
String? profileNameFromData(Map<String, dynamic>? profileData) {
  if (profileData == null) return null;
  final name = ((profileData['account'] as Map<String, dynamic>?) ?? const {})['name'] as String?;
  return (name != null && name.trim().isNotEmpty) ? name.trim() : null;
}
