import 'package:flutter/material.dart';

/// Néon brand colors for the trip-create screen only.
///
/// Intentionally separate from [BrandPaletteData] / [AppPaletteId] — not user-selectable
/// and not mixed into the global app theme.
@immutable
class TripCreateNeonPalette {
  const TripCreateNeonPalette._();

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
}
