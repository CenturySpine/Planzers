import 'package:flutter/material.dart';
import 'package:planerz/app/theme/brand_palette.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/app/theme/static_colors.dart';

class AppTheme {
  const AppTheme._();

  static const String _fontFamily = 'Geist';

  static ThemeData light(BrandPaletteData p) {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: p.primary,
      onPrimary: Colors.white,
      primaryContainer: p.primaryLight,
      onPrimaryContainer: p.deep,
      secondary: p.secondary,
      onSecondary: p.deep,
      secondaryContainer: p.secondaryContainer,
      onSecondaryContainer: p.deep,
      tertiary: p.accent,
      onTertiary: Colors.white,
      tertiaryContainer: p.primarySoft,
      onTertiaryContainer: p.deep,
      error: const Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: const Color(0xFFFFDAD6),
      onErrorContainer: const Color(0xFF410002),
      surface: p.surface,
      onSurface: p.deep,
      surfaceContainerHighest: p.surfaceContainerHighest,
      onSurfaceVariant: p.onSurfaceVariant,
      outline: p.outline,
      outlineVariant: p.outlineVariant,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: p.inverseSurface,
      onInverseSurface: p.onInverseSurface,
      inversePrimary: p.primarySoft,
    );

    final baseTextTheme = ThemeData.light(useMaterial3: true).textTheme;

    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      colorScheme: colorScheme,
      textTheme: baseTextTheme.apply(fontFamily: _fontFamily),
      scaffoldBackgroundColor: StaticColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: p.deep,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 52,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          // Keep a clear rounded-rectangle shape (not fully pill/circular).
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 1,
      ),
      extensions: <ThemeExtension<dynamic>>[
        PlanerzColors(
          info: p.info,
          infoContainer: p.infoContainer,
          success: p.success,
          successContainer: p.successContainer,
          warning: p.warning,
          warningContainer: p.warningContainer,
        ),
      ],
    );
  }
}
