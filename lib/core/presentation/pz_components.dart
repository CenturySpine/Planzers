import 'package:planerz/app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:planerz/app/theme/app_tokens.dart';

/// Shared Riviera building blocks used across feature screens, so page
/// layouts stay consistent (see DESIGN_CHARTER.md).

/// One option of a [PzSegmentedControl].
class PzSegment<T> {
  const PzSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Exclusive view switcher with the same pill look as the app tabs
/// (tinted pill behind the selected label, on a muted track).
class PzSegmentedControl<T> extends StatelessWidget {
  const PzSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<PzSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd + 2),
      ),
      child: Row(
        children: [
          for (final segment in segments)
            Expanded(
              child: _PzSegmentButton(
                label: segment.label,
                icon: segment.icon,
                selected: segment.value == selected,
                onTap: () => onChanged(segment.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _PzSegmentButton extends StatelessWidget {
  const _PzSegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppTokens.primaryDark : AppTokens.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppTokens.surface : Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              boxShadow: selected ? AppTokens.elev1 : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section title for grouped content ("Voitures", "Chambres"…), with an
/// optional count and trailing action.
class PzSectionHeader extends StatelessWidget {
  const PzSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 16, 4, 8),
  });

  final String title;
  final int? count;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppTokens.deep,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            PzCountPill(count: count!),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Small neutral counter pill.
class PzCountPill extends StatelessWidget {
  const PzCountPill({super.key, required this.count, this.highlighted = false});

  final int count;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: highlighted ? AppTokens.accent : AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: AppTokens.deep,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Centered empty state: tinted icon tile, title, optional message.
class PzEmptyState extends StatelessWidget {
  const PzEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTokens.primaryTint,
                borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              ),
              child: Icon(icon, size: 28, color: AppTokens.primary),
            ),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: textTheme.titleMedium),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "done / total" progress line with optional trailing actions (list
/// screens: shopping, packing…).
class PzProgressBar extends StatelessWidget {
  const PzProgressBar({
    super.key,
    required this.done,
    required this.total,
    this.trailing = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 2, 4, 4),
  });

  final int done;
  final int total;
  final List<Widget> trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            PhosphorIconsFill.checkCircle,
            size: 16,
            color: AppTokens.primary,
          ),
          const SizedBox(width: 4),
          Text(
            '$done/$total',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTokens.deep,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (trailing.isNotEmpty) const SizedBox(width: 4),
          ...trailing,
          if (trailing.isEmpty) const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// Initials avatar used in dense rows (rooms, carpools…).
class PzInitialAvatar extends StatelessWidget {
  const PzInitialAvatar({
    super.key,
    required this.label,
    this.size = 24,
    this.background = AppTokens.primaryTint,
    this.foreground = AppTokens.primaryDark,
  });

  final String label;
  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final clean = label.trim();
    final initial = clean.isEmpty ? '?' : clean.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

/// Person chip: initial avatar + name (compact, non-interactive).
class PzPersonChip extends StatelessWidget {
  const PzPersonChip({super.key, required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 9, 3),
      decoration: BoxDecoration(
        color: muted ? AppTokens.surfaceMuted : AppTokens.primaryTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PzInitialAvatar(
            label: label,
            size: 20,
            background: AppTokens.surface,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: muted ? AppTokens.onSurfaceVariant : AppTokens.deep,
            ),
          ),
        ],
      ),
    );
  }
}

enum PzCalloutTone { info, warning, error, success, brand }

/// Inline message block (tinted background, icon, optional title) — the one
/// callout style for hints, warnings and errors.
class PzCallout extends StatelessWidget {
  const PzCallout({
    super.key,
    required this.message,
    this.title,
    this.tone = PzCalloutTone.info,
    this.icon,
  });

  final String message;
  final String? title;
  final PzCalloutTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, IconData defaultIcon) = switch (tone) {
      PzCalloutTone.info => (
          AppTokens.infoContainer,
          const Color(0xFF1667A8),
          PhosphorIconsRegular.info
        ),
      PzCalloutTone.warning => (
          AppTokens.warningContainer,
          const Color(0xFF8A5A00),
          PhosphorIconsRegular.warning
        ),
      PzCalloutTone.error => (
          AppTokens.errorContainer,
          AppTokens.onErrorContainer,
          PhosphorIconsRegular.warningCircle
        ),
      PzCalloutTone.success => (
          AppTokens.successContainer,
          const Color(0xFF0F6B41),
          PhosphorIconsRegular.checkCircle
        ),
      PzCalloutTone.brand => (
          AppTokens.primaryTint,
          AppTokens.primaryDark,
          PhosphorIconsRegular.info
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd + 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title!.isNotEmpty) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
