import 'dart:math';

/// Firestore trip [memberIds] entry for a not-yet-invited traveler (replaced by a
/// real Firebase uid when they join and pick this row).
bool isTripPlaceholderMemberId(String id) {
  final t = id.trim();
  return t.startsWith('ph_') && t.length > 10;
}

/// New random placeholder id (prefix [ph_] + alphanumeric body).
String generateTripPlaceholderMemberId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  final buf = StringBuffer('ph_');
  for (var i = 0; i < 24; i++) {
    buf.write(chars[r.nextInt(chars.length)]);
  }
  return buf.toString();
}
