import 'package:flutter/material.dart';

/// Single-icon pill toggle: shows the current-state icon only; tap to switch.
class StatePillToggle extends StatelessWidget {
  const StatePillToggle({
    super.key,
    required this.offIcon,
    required this.onIcon,
    required this.on,
    required this.onChanged,
  });

  final IconData offIcon;
  final IconData onIcon;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!on),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 30,
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? cs.secondaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          on ? onIcon : offIcon,
          size: 18,
          color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
