import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:planerz/core/intl/app_language.dart';

const _appLanguagePrefKey = 'preferences.language';

final appLocalePreferenceProvider =
    AsyncNotifierProvider<AppLocalePreferenceNotifier, Locale?>(
      AppLocalePreferenceNotifier.new,
    );

final currentAppLanguageProvider = Provider<AppLanguage>((ref) {
  final locale = ref.watch(appLocalePreferenceProvider).asData?.value;
  return AppLanguage.fromLocale(locale) ?? AppLanguage.frFr;
});

class AppLocalePreferenceNotifier extends AsyncNotifier<Locale?> {
  @override
  Future<Locale?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_appLanguagePrefKey);
    return AppLanguage.fromCode(code)?.locale ?? AppLanguage.frFr.locale;
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = AsyncData(language.locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appLanguagePrefKey, language.code);
  }
}
