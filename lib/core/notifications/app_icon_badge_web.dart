import 'dart:js_interop';
@JS('navigator.setAppBadge')
external JSPromise<JSAny?> _setAppBadge(JSNumber count);

@JS('navigator.clearAppBadge')
external JSPromise<JSAny?> _clearAppBadge();

Future<void> applyAppIconBadgeCount(int unreadCount) async {
  try {
    if (unreadCount > 0) {
      await _setAppBadge(unreadCount.toJS).toDart;
      return;
    }
    await _clearAppBadge().toDart;
  } catch (_) {
    // Badging API support depends on browser and install mode.
  }
}
