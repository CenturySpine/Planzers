import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:planerz/app/theme/brand_palette.dart';
import 'package:planerz/app/theme/planerz_colors.dart';

class AppTheme {
  const AppTheme._();

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

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.geistTextTheme(),
      scaffoldBackgroundColor: p.scaffoldBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: p.appBarBackground,
        foregroundColor: p.deep,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 52,
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 1,
      ),
      extensions: <ThemeExtension<dynamic>>[
        PlanerzColors(
          success: p.success,
          successContainer: p.successContainer,
          warning: p.warning,
          warningContainer: p.warningContainer,
        ),
      ],
    );
  }
}
