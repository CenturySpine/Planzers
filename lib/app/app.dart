import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/preview_environment_chrome.dart';
import 'package:planerz/app/router.dart';
import 'package:planerz/app/theme/app_palette_provider.dart';
import 'package:planerz/app/theme/app_theme.dart';
import 'package:planerz/app/theme/brand_palette.dart';
import 'package:planerz/core/firebase/bootstrap.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';

class PlanerzApp extends StatelessWidget {
  const PlanerzApp({required this.firebaseTarget, super.key});

  final FirebaseTarget firebaseTarget;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        firebaseTargetProvider.overrideWithValue(firebaseTarget),
      ],
      child: _PlanerzThemedApp(firebaseTarget: firebaseTarget),
    );
  }
}

class _PlanerzThemedApp extends ConsumerWidget {
  const _PlanerzThemedApp({required this.firebaseTarget});

  final FirebaseTarget firebaseTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paletteAsync = ref.watch(appPaletteProvider);
    final AppPaletteId paletteId = switch (paletteAsync) {
      AsyncData(:final value) => value,
      _ => AppPaletteId.cupidon,
    };

    return MaterialApp.router(
      title: firebaseTarget.isPreview ? 'Planerz · Preview' : 'Planerz',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(paletteId.data),
      themeMode: ThemeMode.light,
      // Required for [showDatePicker] with fr_FR: default delegates only
      // support English ([DefaultMaterialLocalizations]).
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      routerConfig: appRouter,
      builder: (context, child) {
        return FirebaseBootstrap(
          target: firebaseTarget,
          child: PreviewEnvironmentChrome(
            target: firebaseTarget,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
