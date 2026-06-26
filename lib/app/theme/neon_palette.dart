import 'package:flutter/material.dart';

/// Néon brand colors for handoff screens and future app-wide rollout.
///
/// Intentionally separate from [BrandPaletteData] / [AppPaletteId] — not user-selectable
/// and not mixed into the global app theme.
@immutable
class NeonPalette {
  const NeonPalette._();

  static const Color primary = Color(0xFF6745DE);
  static const Color accent = Color(0xFFFF6B6B);
  static const Color secondary = Color(0xFF4ECDC4);
  static const Color deep = Color(0xFF1F1547);

  static const Color scaffoldBackground = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFFA0A0A0);
  static const Color divider = Color(0xFFE5E7EB);
  static const Color onSurfaceVariant = Color(0xFF6B7280);
  static const Color text700 = Color(0xFF374151);

  static Color get primarySoft => Color.lerp(surface, primary, 0.16)!;
  static Color get primaryTint => Color.lerp(surface, primary, 0.08)!;
  static Color get secondarySoft => Color.lerp(surface, secondary, 0.14)!;
  static Color get secondaryTint => Color.lerp(surface, secondary, 0.22)!;

  static Color get dateBorderSet => Color.lerp(divider, primary, 0.35)!;
  static Color get dayTripBorderActive => Color.lerp(divider, primary, 0.45)!;
  static Color get dayTripBackgroundActive => Color.lerp(surface, primary, 0.05)!;
  static Color get dayTripIconBackgroundActive => Color.lerp(surface, primary, 0.14)!;
  static Color get dayTripIconBackgroundRest =>
      Color.lerp(surface, secondary, 0.22)!;
  static Color get dayTripIconColorRest =>
      Color.lerp(deep, secondary, 0.70)!;

  static Color get segmentTrack =>
      Color.lerp(surface, outline, 0.12)!;

  static Color get nameIconBackground => Color.lerp(surface, primary, 0.12)!;
  static Color get nameEditPillBackground => Color.lerp(surface, primary, 0.10)!;
  static Color get nameOptionActiveBackground =>
      Color.lerp(surface, primary, 0.06)!;

  static List<Color> get coverGradient => [
        primary,
        Color.lerp(primary, accent, 0.30)!,
      ];

  static BoxShadow get ctaShadow => BoxShadow(
        color: primary.withValues(alpha: 0.28),
        blurRadius: 18,
        offset: const Offset(0, 6),
      );

  // --- Participants screen (handoff tokens) ---

  static Color get participantsChipOwnerBg => primaryTint;
  static Color get participantsChipOwnerFg => primary;
  static Color get participantsChipAdminBg => secondaryTint;
  static Color get participantsChipAdminFg => dayTripIconColorRest;
  static Color get participantsChipChildBg => Color.lerp(surface, accent, 0.14)!;
  static Color get participantsChipChildFg =>
      Color.lerp(accent, deep, 0.35)!;
  static Color get participantsChipNeutralBg => segmentTrack;
  static Color get participantsChipNeutralFg => onSurfaceVariant;
  static Color get participantsAvatarBg => nameIconBackground;
  static Color get participantsCalloutBg => primaryTint;
  static Color get participantsCalloutBorder => dateBorderSet;
  static Color get participantsDangerBg => Color.lerp(surface, accent, 0.07)!;
  static Color get participantsDangerBorder => accent.withValues(alpha: 0.22);
  static Color get participantsGroupIconBg => dayTripIconBackgroundRest;
  static Color get participantsGroupIconFg => dayTripIconColorRest;
  static Color get participantsAdminBadgeBg => dayTripIconColorRest;

  // --- Trip overview screen (handoff tokens) ---

  static const Color success = Color(0xFF2EB37F);
  static const Color error = Color(0xFFBA1A1A);
  static const Color surfaceHighest = Color(0xFFEEEFF2);

  static Color get accentSoft => Color.lerp(surface, accent, 0.16)!;

  static List<BoxShadow> get elev1 => const [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ];

  static List<Color> get overviewBannerGradient => [
        deep,
        primary,
        Color.lerp(primary, secondary, 0.55)!,
      ];

  // --- Trip bottom navigation (handoff tokens) ---

  static const Color primaryDark = Color(0xFF5036AD);

  static const double bottomNavBarHeight = 72;
  static const double bottomNavFabSize = 60;
  static const double bottomNavFabOverflow = 16;
  static const double bottomNavFabBorderWidth = 4;
  static const double bottomNavFabIconSize = 27;
  static const double bottomNavTabIconSize = 24;
  static const double bottomNavIndicatorWidth = 18;
  static const double bottomNavIndicatorHeight = 3;
  static const double bottomNavIndicatorTop = 6;

  static LinearGradient get bottomNavFabGradient => const LinearGradient(
        colors: [primary, primaryDark],
        transform: GradientRotation(1.0471975511965976), // CSS 150deg
      );

  static List<BoxShadow> get bottomNavElevation => const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 8,
          spreadRadius: 3,
          offset: Offset(0, 4),
        ),
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get bottomNavFabShadow => [
        BoxShadow(
          color: primary.withValues(alpha: 0.70),
          blurRadius: 22,
          spreadRadius: -6,
          offset: const Offset(0, 10),
        ),
        const BoxShadow(
          color: Color(0x2E000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get bottomNavFabShadowSelected => [
        const BoxShadow(
          color: surface,
          spreadRadius: 3,
        ),
        const BoxShadow(
          color: primary,
          spreadRadius: 6,
        ),
        ...bottomNavFabShadow,
      ];

  // --- Board games screen (handoff tokens) ---

  static Color get gamesIconTileBg => Color.lerp(surface, success, 0.16)!;

  static Color get gamesCalloutBg => Color.lerp(surface, success, 0.14)!;

  static Color get gamesCalloutBorder =>
      Color.lerp(divider, success, 0.28)!;

  /// Local theme overlay so Material widgets on Néon screens use these tokens.
  static ThemeData overlayOn(ThemeData base) {
    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scaffoldBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: deep,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          color: deep,
          fontWeight: FontWeight.w500,
        ),
      ),
      splashColor: primary.withValues(alpha: 0.08),
      highlightColor: primary.withValues(alpha: 0.05),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: divider),
        ),
      ),
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: primarySoft,
        secondary: secondary,
        tertiary: accent,
        surface: surface,
        onSurface: deep,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: divider,
        error: accent,
        surfaceTint: Colors.transparent,
        surfaceContainerHighest: segmentTrack,
      ),
    );
  }
}
