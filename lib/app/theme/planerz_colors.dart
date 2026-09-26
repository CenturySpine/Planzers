import 'package:flutter/material.dart';
import 'package:planerz/app/theme/app_tokens.dart';

/// Extra semantic colors (not fully covered by [ColorScheme]) for widgets.
@immutable
class PlanerzColors extends ThemeExtension<PlanerzColors> {
  const PlanerzColors({
    required this.info,
    required this.infoContainer,
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
  });

  final Color info;
  final Color infoContainer;
  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;

  static const PlanerzColors fallback = PlanerzColors(
    info: AppTokens.info,
    infoContainer: AppTokens.infoContainer,
    success: AppTokens.success,
    successContainer: AppTokens.successContainer,
    warning: AppTokens.warning,
    warningContainer: AppTokens.warningContainer,
  );

  @override
  PlanerzColors copyWith({
    Color? info,
    Color? infoContainer,
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
  }) {
    return PlanerzColors(
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
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
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
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
