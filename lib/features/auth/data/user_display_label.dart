import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

/// Label for a trip member (chip, expenses, etc.).
///
/// Prefers [account.name], then Firebase [displayName], then the local part of
/// the best available email ([account.email], then root [email]).
String tripMemberDisplayLabel(
  Map<String, dynamic>? data, {
  required String emptyFallback,
}) {
  if (data == null) return emptyFallback;

  final account = (data['account'] as Map<String, dynamic>?) ?? const {};
  final accountName = (account['name'] as String?)?.trim() ?? '';
  final accountEmail = (account['email'] as String?)?.trim() ?? '';
  final rootEmail = (data['email'] as String?)?.trim() ?? '';
  final displayName = (data['displayName'] as String?)?.trim() ?? '';

  if (accountName.isNotEmpty) return accountName;
  if (displayName.isNotEmpty) return displayName;

  final rawEmail =
      accountEmail.isNotEmpty ? accountEmail : rootEmail;
  if (rawEmail.isEmpty) return emptyFallback;

  final local = displayLabelFromEmail(rawEmail);
  return local.isNotEmpty ? local : rawEmail;
}

/// When the `users/{memberId}` snapshot is missing (e.g. doc absent from the
/// query) but the member is the signed-in user, use Auth email so [resolveTripMemberDisplayLabel]
/// can still derive a local-part label before [tripMemberPublicLabels] is filled.
Map<String, dynamic>? tripMemberUserDataWithAuthFallback(
  String memberId,
  String? currentUserId,
  Map<String, dynamic>? memberUserData,
) {
  if (memberUserData != null) return memberUserData;
  if (currentUserId == null || memberId != currentUserId) return null;
  final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
  if (email.isEmpty) return null;
  return {
    'email': email,
    'account': <String, dynamic>{'email': email},
  };
}

/// Resolves a member label: profile / auth user doc first, then
/// [tripMemberPublicLabels] from the trip document (server-written email local
/// part, or name synced from account settings).
String resolveTripMemberDisplayLabel({
  required String memberId,
  Map<String, dynamic>? userData,
  required Map<String, String> tripMemberPublicLabels,
  String? currentUserId,
  required String emptyFallback,
}) {
  final merged = tripMemberUserDataWithAuthFallback(
    memberId,
    currentUserId,
    userData,
  );
  final fromUser =
      tripMemberDisplayLabel(merged, emptyFallback: '');
  if (fromUser.isNotEmpty) return fromUser;

  final fromTrip = tripMemberPublicLabels[memberId]?.trim() ?? '';
  if (fromTrip.isNotEmpty) return fromTrip;

  return emptyFallback;
}

/// Display labels for [userIds] using `users/{id}` data when present,
/// then [tripMemberPublicLabels], same rules as [resolveTripMemberDisplayLabel].
Map<String, String> tripMemberLabelsFromUserDocsById(
  Map<String, Map<String, dynamic>> docsById,
  Iterable<String> userIds, {
  required Map<String, String> tripMemberPublicLabels,
  String? currentUserId,
  required String emptyFallback,
}) {
  final cleanIds = userIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  final labels = <String, String>{};
  for (final id in cleanIds) {
    labels[id] = resolveTripMemberDisplayLabel(
      memberId: id,
      userData: docsById[id],
      tripMemberPublicLabels: tripMemberPublicLabels,
      currentUserId: currentUserId,
      emptyFallback: emptyFallback,
    );
  }
  return labels;
}

/// Same as [tripMemberLabelsFromUserDocsById] but reads from a Firestore query
/// snapshot of `users` documents.
Map<String, String> tripMemberLabelsFromUserQuerySnapshot(
  QuerySnapshot<Map<String, dynamic>>? snapshot,
  Iterable<String> userIds, {
  required Map<String, String> tripMemberPublicLabels,
  String? currentUserId,
  required String emptyFallback,
}) {
  final docsById = <String, Map<String, dynamic>>{};
  for (final doc in snapshot?.docs ?? const []) {
    docsById[doc.id] = doc.data();
  }
  return tripMemberLabelsFromUserDocsById(
    docsById,
    userIds,
    tripMemberPublicLabels: tripMemberPublicLabels,
    currentUserId: currentUserId,
    emptyFallback: emptyFallback,
  );
}
