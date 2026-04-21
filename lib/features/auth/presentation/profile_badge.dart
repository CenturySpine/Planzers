import 'package:flutter/material.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';

/// Builds a profile badge from a user profile map.
///
/// Uses the canonical stored profile photo when available, otherwise falls back
/// to a uniform circular badge with the first uppercase letter of the label.
Widget buildProfileBadge({
  required BuildContext context,
  required String displayLabel,
  Map<String, dynamic>? userData,
  double size = 28,
}) {
  final scheme = Theme.of(context).colorScheme;
  final fallback = Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      shape: BoxShape.circle,
    ),
    child: Text(
      avatarInitialFromDisplayLabel(displayLabel),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
        height: 1.0,
      ),
    ),
  );

  final photoUrl = tripMemberStoredProfileBadgeUrl(userData);
  if (photoUrl.isEmpty) {
    return fallback;
  }

  return SizedBox(
    width: size,
    height: size,
    child: ClipOval(
      child: Image.network(
        photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    ),
  );
}
