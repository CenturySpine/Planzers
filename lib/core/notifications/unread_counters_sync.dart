import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

Future<void> resyncMyUnreadCountersAfterSignIn() async {
  try {
    await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('resyncMyTripUnreadCounters')
        .call();
  } catch (e, st) {
    // One line: full stack on every sign-in looked like a Flutter/daemon crash.
    debugPrint('Unread counters resync skipped: $e');
    assert(() {
      debugPrint('$st');
      return true;
    }());
  }
}
