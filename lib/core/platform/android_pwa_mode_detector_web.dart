// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

bool isAndroidPwaMode() {
  final userAgent = html.window.navigator.userAgent.toLowerCase();
  final isAndroidDevice = userAgent.contains('android');
  if (!isAndroidDevice) {
    return false;
  }

  final standalone =
      html.window.matchMedia('(display-mode: standalone)').matches;
  final minimalUi =
      html.window.matchMedia('(display-mode: minimal-ui)').matches;
  final fullscreen =
      html.window.matchMedia('(display-mode: fullscreen)').matches;

  return standalone || minimalUi || fullscreen;
}
