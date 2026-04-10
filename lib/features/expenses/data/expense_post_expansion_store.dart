import 'package:shared_preferences/shared_preferences.dart';

/// Persists expand/collapse for each expense post in local storage (per device).
abstract final class ExpensePostExpansionStore {
  static String _key(String tripId, String groupId) {
    final t = tripId.trim();
    final g = groupId.trim();
    return 'exp_post_exp_v1_${t}_$g';
  }

  /// `null` if the user never changed this post on this device.
  static Future<bool?> read(String tripId, String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final k = _key(tripId, groupId);
    if (!prefs.containsKey(k)) return null;
    return prefs.getBool(k);
  }

  static Future<void> write(
    String tripId,
    String groupId,
    bool expanded,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(tripId, groupId), expanded);
  }
}
