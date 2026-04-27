import 'android_pwa_mode_detector_stub.dart'
    if (dart.library.html) 'android_pwa_mode_detector_web.dart'
    as detector;

bool isAndroidPwaMode() => detector.isAndroidPwaMode();
