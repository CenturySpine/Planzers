import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

Future<void> resyncMyUnreadCountersAfterSignIn() async {
  try {
    await FirebaseFunctions.instance
        .httpsCallable('resyncMyTripUnreadCounters')
        .call();
  } catch (e, st) {
    debugPrint('Unread counters resync skipped: $e\n$st');
  }
}
