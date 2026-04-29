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

/// All colors that feed [ThemeData] and [PlanerzColors].
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
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.deep,
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
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color deep;
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
    successContainer: Color(0xFFE8F8EA),
    warning: Color(0xFFAE8F56),
    warningContainer: Color(0xFFF7EDDC),
    deep: Color(0xFF2E0B29),
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

  /// Source Figma: #3A58F8 #2E206D #FECD55 #F9600F #BDE2F9 #2EB37F #FCCEFC #ACACAE
  static const BrandPaletteData oligarch = BrandPaletteData(
    primary: Color(0xFF3A58F8),
    primaryLight: Color(0xFFBDE2F9),
    primarySoft: Color(0xFFE5F2FD),
    accent: Color(0xFFD44D00),
    secondary: Color(0xFF70CDC5),
    secondaryContainer: Color(0xFFCFF5F0),
    success: Color(0xFF2EB37F),
    successContainer: Color(0xFFCCF5E4),
    warning: Color(0xFFC49A00),
    warningContainer: Color(0xFFFFF3CC),
    deep: Color(0xFF2E206D),
    surface: Color(0xFFFFFBFF),
    surfaceContainerHighest: Color(0xFFDCE3FA),
    scaffoldBackground: Color(0xFFF2F4FD),
    appBarBackground: Color(0xFFD2DAF8),
    onSurfaceVariant: Color(0xFF483D6B),
    outline: Color(0xFF6E6A8A),
    outlineVariant: Color(0xFFC0BCDC),
    inverseSurface: Color(0xFF2E206D),
    onInverseSurface: Color(0xFFEFF0FA),
  );
}
