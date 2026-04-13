import 'package:flutter/material.dart';

/// Extra semantic colors (not fully covered by [ColorScheme]) for widgets.
@immutable
class PlanzersColors extends ThemeExtension<PlanzersColors> {
  const PlanzersColors({
    required this.success,
    required this.warning,
    required this.successContainer,
  });

  final Color success;
  final Color warning;
  final Color successContainer;

  static const PlanzersColors fallback = PlanzersColors(
    success: Color(0xFF4DC75E),
    warning: Color(0xFFAE8F56),
    successContainer: Color(0xFFE8F8EA),
  );

  @override
  PlanzersColors copyWith({
    Color? success,
    Color? warning,
    Color? successContainer,
  }) {
    return PlanzersColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      successContainer: successContainer ?? this.successContainer,
    );
  }

  @override
  PlanzersColors lerp(ThemeExtension<PlanzersColors>? other, double t) {
    if (other is! PlanzersColors) return this;
    return PlanzersColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
    );
  }
}

extension PlanzersThemeContext on BuildContext {
  PlanzersColors get planzersColors =>
      Theme.of(this).extension<PlanzersColors>() ?? PlanzersColors.fallback;
}
