import 'package:flutter/material.dart';

/// Planerz "Riviera" design tokens — single source of truth for every color,
/// radius and density value used by the app theme and custom widgets.
///
/// Color rule (keep the palette contained):
/// - Chrome (buttons, focus, selection, links, navigation) uses **Lagon** only.
/// - **Soleil** is a sparing highlight (brand mark, badges, "today").
/// - The four business hues (Repas / Nuits / Loisirs / Trajets, see
///   `activity_filter_colors.dart`) only appear to encode a category.
/// - Everything else is ink + neutrals.
///
/// Documented in PALETTES.md — keep both in sync.
@immutable
class AppTokens {
  const AppTokens._();

  // --- Brand ---

  /// Lagon — primary / chrome color (4.5:1 on white).
  static const Color primary = Color(0xFF0B8579);
  static const Color primaryDark = Color(0xFF086B61);

  /// Soleil — joyful highlight, never used for text on light surfaces.
  static const Color accent = Color(0xFFFFB938);
  static const Color onAccent = deep;

  /// Secondary tint used for decorative fills (derived from Lagon).
  static const Color secondary = Color(0xFF5FC7BA);

  /// Ink — primary text and titles.
  static const Color deep = Color(0xFF17213A);

  // --- Neutrals ---

  static const Color scaffoldBackground = Color(0xFFF5F6F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEEF0F3);
  static const Color surfaceHighest = surfaceMuted;
  static const Color divider = Color(0xFFE2E5EA);
  static const Color outline = Color(0xFF8891A1);
  static const Color onSurfaceVariant = Color(0xFF566074);
  static const Color text700 = Color(0xFF343D52);
  static const Color inverseSurface = Color(0xFF1E2840);
  static const Color onInverseSurface = Color(0xFFF2F4F8);

  // --- Semantic ---

  static const Color success = Color(0xFF178A55);
  static const Color successContainer = Color(0xFFE0F4EA);
  static const Color warning = Color(0xFFB77B00);
  static const Color warningContainer = Color(0xFFFFF4D6);
  static const Color error = Color(0xFFD0334A);
  static const Color errorContainer = Color(0xFFFDE7EA);
  static const Color onErrorContainer = Color(0xFF6B0F1D);
  static const Color info = Color(0xFF1F84D6);
  static const Color infoContainer = Color(0xFFE4F1FC);

  // --- Derived tints ---

  static const Color primarySoft = Color(0xFFD5EFEB);
  static const Color primaryTint = Color(0xFFEAF6F4);
  static const Color accentSoft = Color(0xFFFFF1D1);
  static const Color secondarySoft = Color(0xFFE6F6F3);
  static const Color secondaryTint = Color(0xFFDDF2EE);

  // --- Shape & density ---

  static const double radiusXs = 6;
  static const double radiusSm = 8;
  static const double radiusMd = 10;
  static const double radiusLg = 14;
  static const double radiusXl = 20;

  static const double appBarHeight = 52;
  static const double controlHeight = 40;
  static const double inputHeight = 44;
  static const double pagePadding = 16;

  static List<BoxShadow> get elev1 => const [
        BoxShadow(
          color: Color(0x0D17213A),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get elev2 => const [
        BoxShadow(
          color: Color(0x1417213A),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ];

  // --- Legacy aliases used by handoff-era widgets (same API, new values) ---

  static const Color dateBorderSet = Color(0xFF9FD3CC);
  static const Color dayTripBorderActive = Color(0xFF7CC4BB);
  static const Color dayTripBackgroundActive = primaryTint;
  static const Color dayTripIconBackgroundActive = primarySoft;
  static const Color dayTripIconBackgroundRest = surfaceMuted;
  static const Color dayTripIconColorRest = primaryDark;
  static const Color segmentTrack = surfaceMuted;
  static const Color nameIconBackground = primaryTint;
  static const Color nameEditPillBackground = primaryTint;
  static const Color nameOptionActiveBackground = primaryTint;

  static List<Color> get coverGradient => const [primary, primaryDark];

  static BoxShadow get ctaShadow => BoxShadow(
        color: primary.withValues(alpha: 0.22),
        blurRadius: 14,
        offset: const Offset(0, 4),
      );

  // Participants screen
  static Color get participantsChipOwnerBg => primaryTint;
  static Color get participantsChipOwnerFg => primaryDark;
  static Color get participantsChipAdminBg => accentSoft;
  static Color get participantsChipAdminFg => const Color(0xFF8A5A00);
  static Color get participantsChipChildBg => const Color(0xFFFCE8EF);
  static Color get participantsChipChildFg => const Color(0xFFB42A5C);
  static Color get participantsChipNeutralBg => surfaceMuted;
  static Color get participantsChipNeutralFg => onSurfaceVariant;
  static Color get participantsAvatarBg => primaryTint;
  static Color get participantsCalloutBg => primaryTint;
  static Color get participantsCalloutBorder => dateBorderSet;
  static Color get participantsDangerBg => errorContainer;
  static Color get participantsDangerBorder => error.withValues(alpha: 0.25);
  static Color get participantsGroupIconBg => surfaceMuted;
  static Color get participantsGroupIconFg => primaryDark;
  static Color get participantsAdminBadgeBg => primaryDark;

  // Trip overview
  static Color get overviewModuleAddBorder => dateBorderSet;
  static List<Color> get overviewBannerGradient => const [
        Color(0xFF0E3D48),
        primaryDark,
        primary,
      ];

  // Bottom navigation
  static const double bottomNavBarHeight = 60;
  static const double bottomNavTabIconSize = 22;

  // Board games
  static Color get gamesIconTileBg => successContainer;
  static Color get gamesCalloutBg => successContainer;
  static Color get gamesCalloutBorder => success.withValues(alpha: 0.25);

  /// Kept for screens that still wrap themselves in an overlay: the global
  /// theme already carries every token, so this is now a no-op passthrough.
  static ThemeData overlayOn(ThemeData base) => base;
}
