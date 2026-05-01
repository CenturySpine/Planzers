import 'package:cloud_functions/cloud_functions.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/features/administration/domain/app_usage_stats.dart';

Map<String, dynamic> _deepConvert(Map map) {
  return map.map(
    (k, v) => MapEntry(k.toString(), v is Map ? _deepConvert(v) : v),
  );
}

class AdministrationRepository {
  Future<AppUsageStats> getAppUsageStats() async {
    final callable = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    ).httpsCallable('getAppUsageStats');
    final result = await callable.call();
    return AppUsageStats.fromMap(_deepConvert(result.data as Map));
  }
}
