import 'package:flutter/material.dart';

/// Visual identity preset (colors derived from the approved brand sets).
enum AppPaletteId {
  /// Rose / fuchsia (palette historique).
  cupidon,

  /// Turquoise, bleu et violet (palette Figma partagée).
  oligarch,
}

extension AppPaletteIdX on AppPaletteId {
  BrandPaletteData get data => switch (this) {
        AppPaletteId.cupidon => BrandPaletteData.cupidon,
        AppPaletteId.oligarch => BrandPaletteData.oligarch,
      };
}

/// All colors that feed [ThemeData] and [PlanzersColors].
@immutable
class BrandPaletteData {
  const BrandPaletteData({
    required this.primary,
    required this.primaryLight,
    required this.primarySoft,
    required this.accent,
    required this.secondary,
    required this.secondaryContainer,
    required this.success,
    required this.warning,
    required this.deep,
    required this.successContainer,
    required this.surface,
    required this.surfaceContainerHighest,
    required this.scaffoldBackground,
    required this.appBarBackground,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.inverseSurface,
    required this.onInverseSurface,
  });

  final Color primary;
  final Color primaryLight;
  final Color primarySoft;
  final Color accent;
  final Color secondary;
  final Color secondaryContainer;
  final Color success;
  final Color warning;
  final Color deep;
  final Color successContainer;
  final Color surface;
  final Color surfaceContainerHighest;
  final Color scaffoldBackground;
  final Color appBarBackground;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color inverseSurface;
  final Color onInverseSurface;

  static const BrandPaletteData cupidon = BrandPaletteData(
    primary: Color(0xFF97264E),
    primaryLight: Color(0xFFE798DC),
    primarySoft: Color(0xFFF3CDEE),
    accent: Color(0xFFCF30B8),
    secondary: Color(0xFF7ECFDD),
    secondaryContainer: Color(0xFFCFEFF4),
    success: Color(0xFF4DC75E),
    warning: Color(0xFFAE8F56),
    deep: Color(0xFF2E0B29),
    successContainer: Color(0xFFE8F8EA),
    surface: Color(0xFFFFFBFE),
    surfaceContainerHighest: Color(0xFFE8D7E2),
    scaffoldBackground: Color(0xFFF6EDF3),
    appBarBackground: Color(0xFFE3D0DD),
    onSurfaceVariant: Color(0xFF5C4B56),
    outline: Color(0xFF8A7582),
    outlineVariant: Color(0xFFDCC8D4),
    inverseSurface: Color(0xFF382D35),
    onInverseSurface: Color(0xFFFDEEF8),
  );

  /// Second palette: #70CDC5, #5A725E, #2B2129, #8A41A4, #3554D0, #F1CACA,
  /// #1D18BF, #A1B823 (roles sémantiques pour l’UI claire).
  static const BrandPaletteData oligarch = BrandPaletteData(
    primary: Color(0xFF3554D0),
    primaryLight: Color(0xFF9EADF0),
    primarySoft: Color(0xFFE8EDFA),
    accent: Color(0xFF8A41A4),
    secondary: Color(0xFF70CDC5),
    secondaryContainer: Color(0xFFCFF5F0),
    success: Color(0xFF5A725E),
    warning: Color(0xFFB0924A),
    deep: Color(0xFF2B2129),
    successContainer: Color(0xFFE5EDE6),
    surface: Color(0xFFFFFBFF),
    surfaceContainerHighest: Color(0xFFE1E6F4),
    scaffoldBackground: Color(0xFFF4F6FC),
    appBarBackground: Color(0xFFD9E0F4),
    onSurfaceVariant: Color(0xFF4B5065),
    outline: Color(0xFF767B8F),
    outlineVariant: Color(0xFFC5CBE0),
    inverseSurface: Color(0xFF2B2129),
    onInverseSurface: Color(0xFFF1F3F9),
  );
}
