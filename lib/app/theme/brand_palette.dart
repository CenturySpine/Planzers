import 'package:flutter/material.dart';
import 'package:planerz/app/theme/app_tokens.dart';

/// Visual identity preset.
enum AppPaletteId {
  /// Lagon / Soleil / ink (see [AppTokens]).
  riviera,
}

extension AppPaletteIdX on AppPaletteId {
  BrandPaletteData get data => switch (this) {
        AppPaletteId.riviera => BrandPaletteData.riviera,
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
    required this.info,
    required this.infoContainer,
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
  final Color info;
  final Color infoContainer;
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

  static const BrandPaletteData riviera = BrandPaletteData(
    primary: AppTokens.primary,
    primaryLight: AppTokens.primarySoft,
    primarySoft: AppTokens.primaryTint,
    accent: AppTokens.accent,
    secondary: AppTokens.secondary,
    secondaryContainer: AppTokens.secondarySoft,
    info: AppTokens.info,
    infoContainer: AppTokens.infoContainer,
    success: AppTokens.success,
    successContainer: AppTokens.successContainer,
    warning: AppTokens.warning,
    warningContainer: AppTokens.warningContainer,
    deep: AppTokens.deep,
    surface: AppTokens.surface,
    surfaceContainerHighest: AppTokens.surfaceMuted,
    scaffoldBackground: AppTokens.scaffoldBackground,
    appBarBackground: AppTokens.surface,
    onSurfaceVariant: AppTokens.onSurfaceVariant,
    outline: AppTokens.outline,
    outlineVariant: AppTokens.divider,
    inverseSurface: AppTokens.inverseSurface,
    onInverseSurface: AppTokens.onInverseSurface,
  );
}
