import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:planerz/app/theme/app_tokens.dart';

/// Planerz logo mark (pin + setting sun), vector so it stays crisp at any size.
class PlanerzBrandMark extends StatelessWidget {
  const PlanerzBrandMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/planerz_mark.svg',
      width: size,
      height: size,
    );
  }
}

/// Mark + "planerz" wordmark, for headers and the sign-in screen.
class PlanerzBrandLockup extends StatelessWidget {
  const PlanerzBrandLockup({
    super.key,
    this.markSize = 32,
    this.fontSize = 22,
    this.color = AppTokens.deep,
    this.showMark = true,
  });

  final double markSize;
  final double fontSize;
  final Color color;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMark) ...[
          PlanerzBrandMark(size: markSize),
          SizedBox(width: markSize * 0.28),
        ],
        Text(
          'planerz',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1,
            color: color,
          ),
        ),
      ],
    );
  }
}
