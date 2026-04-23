import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/app_palette_provider.dart';
import 'package:planerz/app/theme/brand_palette.dart';
import 'package:planerz/l10n/app_localizations.dart';

class PalettePickerButton extends ConsumerWidget {
  const PalettePickerButton({super.key});

  static const double _swatchSize = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final paletteAsync = ref.watch(appPaletteProvider);
    final AppPaletteId current = switch (paletteAsync) {
      AsyncData(:final value) => value,
      _ => AppPaletteId.cupidon,
    };

    return PopupMenuButton<AppPaletteId>(
      tooltip: l10n.accountColorPalette,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 0, maxWidth: 280),
      onSelected: (id) async {
        await ref.read(appPaletteProvider.notifier).setPalette(id);
        if (!context.mounted) return;
        final label = switch (id) {
          AppPaletteId.cupidon => 'Cupidon',
          AppPaletteId.oligarch => 'Oligarch',
        };
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(l10n.paletteSaved(label)),
              duration: const Duration(milliseconds: 1100),
            ),
          );
      },
      itemBuilder: (context) => [
        _paletteMenuItem(
          context,
          id: AppPaletteId.cupidon,
          label: 'Cupidon',
          colors: BrandPaletteData.cupidon,
          selected: current == AppPaletteId.cupidon,
        ),
        _paletteMenuItem(
          context,
          id: AppPaletteId.oligarch,
          label: 'Oligarch',
          colors: BrandPaletteData.oligarch,
          selected: current == AppPaletteId.oligarch,
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _paletteSwatchStrip(context, colors: current.data),
            const SizedBox(width: 4),
            Icon(
              Icons.palette_outlined,
              size: 22,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuEntry<AppPaletteId> _paletteMenuItem(
    BuildContext context, {
    required AppPaletteId id,
    required String label,
    required BrandPaletteData colors,
    required bool selected,
  }) {
    return PopupMenuItem<AppPaletteId>(
      value: id,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _paletteSwatchStrip(context, colors: colors),
          const SizedBox(width: 10),
          Text(label),
          if (selected) ...[
            const SizedBox(width: 10),
            Icon(
              Icons.check,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }

  /// Two fixed swatches: main brand hue + accent (secondary is often too close
  /// between palettes for a third dot to read at a glance).
  Widget _paletteSwatchStrip(
    BuildContext context, {
    required BrandPaletteData colors,
  }) {
    final outline = Theme.of(context).colorScheme.outline.withValues(alpha: 0.35);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _swatch(colors.primary, outline),
        const SizedBox(width: 3),
        _swatch(colors.accent, outline),
      ],
    );
  }

  Widget _swatch(Color fill, Color outline) {
    return Container(
      width: _swatchSize,
      height: _swatchSize,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: outline, width: 0.5),
      ),
    );
  }
}
