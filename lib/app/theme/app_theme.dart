import 'package:flutter/material.dart';
import 'package:planzers/app/theme/app_palette.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get light {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppPalette.primary,
      onPrimary: Colors.white,
      primaryContainer: AppPalette.primaryLight,
      onPrimaryContainer: AppPalette.deep,
      secondary: AppPalette.secondary,
      onSecondary: AppPalette.deep,
      secondaryContainer: Color(0xFFCFEFF4),
      onSecondaryContainer: AppPalette.deep,
      tertiary: AppPalette.accent,
      onTertiary: Colors.white,
      tertiaryContainer: AppPalette.primarySoft,
      onTertiaryContainer: AppPalette.deep,
      error: Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFFFBFE),
      onSurface: AppPalette.deep,
      surfaceContainerHighest: Color(0xFFE8D7E2),
      onSurfaceVariant: Color(0xFF5C4B56),
      outline: Color(0xFF8A7582),
      outlineVariant: Color(0xFFDCC8D4),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFF382D35),
      onInverseSurface: Color(0xFFFDEEF8),
      inversePrimary: AppPalette.primarySoft,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF6EDF3),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 1,
      ),
    );
  }
}
