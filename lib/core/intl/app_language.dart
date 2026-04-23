import 'package:flutter/material.dart';

enum AppLanguage {
  frFr(code: 'fr_FR', locale: Locale('fr', 'FR')),
  enUs(code: 'en_US', locale: Locale('en', 'US'));

  const AppLanguage({required this.code, required this.locale});

  final String code;
  final Locale locale;

  static AppLanguage? fromCode(String? value) {
    final normalized = (value ?? '').trim();
    for (final language in AppLanguage.values) {
      if (language.code == normalized) {
        return language;
      }
    }
    return null;
  }

  static AppLanguage? fromLocale(Locale? locale) {
    if (locale == null) return null;
    for (final language in AppLanguage.values) {
      if (language.locale.languageCode == locale.languageCode &&
          (language.locale.countryCode ?? '') == (locale.countryCode ?? '')) {
        return language;
      }
    }
    return null;
  }
}
