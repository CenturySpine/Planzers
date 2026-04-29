import 'package:flutter/material.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/core/firebase/firebase_target.dart';

/// Top strip when running the preview Firebase / build target.
class PreviewEnvironmentChrome extends StatelessWidget {
  const PreviewEnvironmentChrome({
    required this.target,
    required this.child,
    super.key,
  });

  final FirebaseTarget target;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (target != FirebaseTarget.preview) {
      return child;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: context.planerzColors.warning,
          elevation: 1,
          child: SafeArea(
            bottom: false,
            minimum: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.science_outlined,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Preview · préversion',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
