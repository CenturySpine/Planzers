import 'package:pub_semver/pub_semver.dart';

/// Returns true if [currentTag] is strictly older than [latestTag].
/// Both tags may carry a leading 'v' (e.g. 'v0.2.0-alpha3').
/// Returns false if either tag cannot be parsed as a valid semver string.
bool isUpdateRequired(String currentTag, String latestTag) {
  try {
    final current = Version.parse(_strip(currentTag));
    final latest = Version.parse(_strip(latestTag));
    return current < latest;
  } catch (_) {
    return false;
  }
}

String _strip(String tag) =>
    tag.startsWith('v') ? tag.substring(1) : tag;
