import 'dart:io' show Platform;

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';

Future<void> applyAppIconBadgeCount(int unreadCount) async {
  if (kIsWeb) {
    return;
  }
  if (!Platform.isAndroid && !Platform.isIOS) {
    return;
  }
  try {
    if (unreadCount > 0) {
      AppBadgePlus.updateBadge(unreadCount);
    } else {
      AppBadgePlus.updateBadge(0);
    }
  } catch (_) {
    // Badge support is best effort and should never break app flow.
  }
}
