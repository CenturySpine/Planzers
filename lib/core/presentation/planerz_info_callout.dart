import 'package:flutter/material.dart';
import 'package:planerz/app/theme/planerz_colors.dart';

/// Colored info callout (light blue container, same shape as AI dialog banners).
class PlanerzInfoCallout extends StatelessWidget {
  const PlanerzInfoCallout({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planerzColors = context.planerzColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: planerzColors.infoContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: planerzColors.info,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: planerzColors.info,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
