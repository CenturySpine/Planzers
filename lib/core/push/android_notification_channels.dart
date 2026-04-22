import 'android_notification_channels_stub.dart'
    if (dart.library.io) 'android_notification_channels_mobile.dart'
    if (dart.library.js_interop) 'android_notification_channels_stub.dart' as impl;

Future<void> initAndroidNotificationChannels() =>
    impl.initAndroidNotificationChannels();
