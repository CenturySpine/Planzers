const autoOpenCurrentTripPreferenceKey = 'autoOpenCurrentTrip';

bool readAutoOpenCurrentTripPreference(Map<String, dynamic>? userData) {
  final accountRaw = userData?['account'];
  if (accountRaw is! Map) {
    return true;
  }

  final value = accountRaw[autoOpenCurrentTripPreferenceKey];
  return value is bool ? value : true;
}
