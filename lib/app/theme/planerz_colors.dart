import 'package:flutter/material.dart';

/// Extra semantic colors (not fully covered by [ColorScheme]) for widgets.
@immutable
class PlanerzColors extends ThemeExtension<PlanerzColors> {
  const PlanerzColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
  });

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;

  static const PlanerzColors fallback = PlanerzColors(
    success: Color(0xFF4DC75E),
    successContainer: Color(0xFFE8F8EA),
    warning: Color(0xFFAE8F56),
    warningContainer: Color(0xFFF7EDDC),
  );

  @override
  PlanerzColors copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
  }) {
    return PlanerzColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
    );
  }

  @override
  PlanerzColors lerp(ThemeExtension<PlanerzColors>? other, double t) {
    if (other is! PlanerzColors) return this;
    return PlanerzColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
    );
  }
}

extension PlanerzThemeContext on BuildContext {
  PlanerzColors get planerzColors =>
      Theme.of(this).extension<PlanerzColors>() ?? PlanerzColors.fallback;
}
