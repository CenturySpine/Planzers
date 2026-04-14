import 'app_icon_badge_stub.dart'
    if (dart.library.io) 'app_icon_badge_io.dart'
    if (dart.library.js_interop) 'app_icon_badge_web.dart' as impl;

Future<void> applyAppIconBadgeCount(int unreadCount) {
  final next = unreadCount < 0 ? 0 : unreadCount;
  return impl.applyAppIconBadgeCount(next);
}
