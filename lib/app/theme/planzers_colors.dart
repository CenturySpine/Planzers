import 'package:flutter/material.dart';

/// Extra semantic colors (not fully covered by [ColorScheme]) for widgets.
@immutable
class PlanzersColors extends ThemeExtension<PlanzersColors> {
  const PlanzersColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
  });

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;

  static const PlanzersColors fallback = PlanzersColors(
    success: Color(0xFF4DC75E),
    successContainer: Color(0xFFE8F8EA),
    warning: Color(0xFFAE8F56),
    warningContainer: Color(0xFFF7EDDC),
  );

  @override
  PlanzersColors copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
  }) {
    return PlanzersColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
    );
  }

  @override
  PlanzersColors lerp(ThemeExtension<PlanzersColors>? other, double t) {
    if (other is! PlanzersColors) return this;
    return PlanzersColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
    );
  }
}

extension PlanzersThemeContext on BuildContext {
  PlanzersColors get planzersColors =>
      Theme.of(this).extension<PlanzersColors>() ?? PlanzersColors.fallback;
}
