import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/account/data/account_repository.dart';

final appLocalePreferenceProvider = StreamProvider<Locale?>((ref) {
  return ref.watch(accountRepositoryProvider).watchPreferredLanguage().map((
    language,
  ) {
    return language?.locale;
  });
});
