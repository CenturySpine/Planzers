/// Shared display-name length limits (account profile, trip join, etc.).
/// Matches server rules in Cloud Functions.
const int kDisplayNameMinLength = 2;
const int kDisplayNameMaxLength = 50;

bool isDisplayNameLengthValid(String raw) {
  final length = raw.trim().length;
  return length >= kDisplayNameMinLength && length <= kDisplayNameMaxLength;
}
