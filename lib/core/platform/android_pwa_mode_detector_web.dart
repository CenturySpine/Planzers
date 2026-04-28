// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

bool isAndroidPwaMode() {
  final userAgent = html.window.navigator.userAgent.toLowerCase();
  final isAndroidDevice = userAgent.contains('android');
  return isAndroidDevice;
}
