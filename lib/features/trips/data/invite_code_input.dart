const inviteCodeCharCount = 6;
const inviteCodeSegmentSize = 3;

/// Uppercase alphanumeric invite code digits only (hyphens and spaces stripped).
String sanitizeInviteCodeInput(String raw) {
  final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (cleaned.length <= inviteCodeCharCount) return cleaned;
  return cleaned.substring(0, inviteCodeCharCount);
}

/// Builds the stored invite token shape (`XXX-XXX`) from segmented input.
String formatInviteCodeToken(String code) {
  if (code.length != inviteCodeCharCount) return code;
  return '${code.substring(0, inviteCodeSegmentSize)}-'
      '${code.substring(inviteCodeSegmentSize)}';
}
