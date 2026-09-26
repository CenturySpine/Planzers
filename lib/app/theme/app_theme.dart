import 'package:flutter/material.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/app/theme/brand_palette.dart';
import 'package:planerz/app/theme/planerz_colors.dart';

/// Global Material 3 theme. Every standard control (fields, toggles, chips,
/// tabs, buttons, cards, dialogs, sheets, menus…) is styled here so screens
/// get a consistent, compact look without local overrides.
class AppTheme {
  const AppTheme._();

  static const String fontFamily = 'Figtree';

  static TextTheme _textTheme(Color ink, Color muted) {
    TextStyle s(double size, FontWeight weight, double height,
            [double spacing = 0, Color? color]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: height / size,
          letterSpacing: spacing,
          color: color ?? ink,
        );
    return TextTheme(
      displayLarge: s(48, FontWeight.w800, 54, -1),
      displayMedium: s(40, FontWeight.w800, 46, -0.8),
      displaySmall: s(32, FontWeight.w800, 38, -0.6),
      headlineLarge: s(28, FontWeight.w800, 34, -0.5),
      headlineMedium: s(24, FontWeight.w700, 30, -0.4),
      headlineSmall: s(21, FontWeight.w700, 27, -0.3),
      titleLarge: s(18, FontWeight.w700, 24, -0.2),
      titleMedium: s(15, FontWeight.w600, 21, -0.1),
      titleSmall: s(14, FontWeight.w600, 19),
      bodyLarge: s(15, FontWeight.w400, 21),
      bodyMedium: s(14, FontWeight.w400, 19),
      bodySmall: s(12.5, FontWeight.w400, 17, 0, muted),
      labelLarge: s(14, FontWeight.w600, 18),
      labelMedium: s(12.5, FontWeight.w600, 16),
      labelSmall: s(11, FontWeight.w600, 14, 0.2),
    );
  }

  static ThemeData light(BrandPaletteData p) {
    const ink = AppTokens.deep;
    const muted = AppTokens.onSurfaceVariant;
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: p.primary,
      onPrimary: Colors.white,
      primaryContainer: p.primaryLight,
      onPrimaryContainer: AppTokens.primaryDark,
      secondary: p.secondary,
      onSecondary: ink,
      secondaryContainer: p.secondaryContainer,
      onSecondaryContainer: AppTokens.primaryDark,
      // Readable amber step of Soleil (the raw sun hue is too light for
      // icons/text on white).
      tertiary: const Color(0xFFB36B00),
      onTertiary: Colors.white,
      tertiaryContainer: AppTokens.accentSoft,
      onTertiaryContainer: ink,
      error: AppTokens.error,
      onError: Colors.white,
      errorContainer: AppTokens.errorContainer,
      onErrorContainer: AppTokens.onErrorContainer,
      surface: p.surface,
      onSurface: ink,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFFAFBFC),
      surfaceContainer: AppTokens.scaffoldBackground,
      surfaceContainerHigh: const Color(0xFFF1F3F5),
      surfaceContainerHighest: p.surfaceContainerHighest,
      onSurfaceVariant: muted,
      outline: p.outline,
      outlineVariant: p.outlineVariant,
      shadow: const Color(0xFF17213A),
      scrim: const Color(0xFF0B1020),
      inverseSurface: p.inverseSurface,
      onInverseSurface: p.onInverseSurface,
      inversePrimary: AppTokens.secondary,
    );

    final text = _textTheme(ink, muted);
    const radiusMd = BorderRadius.all(Radius.circular(AppTokens.radiusMd));
    const radiusLg = BorderRadius.all(Radius.circular(AppTokens.radiusLg));
    const controlSize = Size(64, AppTokens.controlHeight);

    OutlineInputBorder field(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: colorScheme,
      textTheme: text,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      scaffoldBackgroundColor: p.scaffoldBackground,
      canvasColor: p.surface,
      dividerColor: p.outlineVariant,
      splashFactory: InkSparkle.splashFactory,
      splashColor: p.primary.withValues(alpha: 0.08),
      highlightColor: p.primary.withValues(alpha: 0.04),
      iconTheme: const IconThemeData(color: ink, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: p.appBarBackground,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: AppTokens.appBarHeight,
        titleSpacing: 4,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: p.outlineVariant)),
        titleTextStyle: text.titleLarge,
        iconTheme: const IconThemeData(color: ink, size: 22),
        actionsIconTheme: const IconThemeData(color: ink, size: 22),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLg,
          side: BorderSide(color: p.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        dense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        minVerticalPadding: 8,
        minLeadingWidth: 24,
        horizontalTitleGap: 12,
        iconColor: muted,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        shape: const RoundedRectangleBorder(borderRadius: radiusMd),
      ),
      dividerTheme: DividerThemeData(
        color: p.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: field(p.outlineVariant),
        enabledBorder: field(p.outlineVariant),
        focusedBorder: field(p.primary, 1.6),
        errorBorder: field(AppTokens.error),
        focusedErrorBorder: field(AppTokens.error, 1.6),
        disabledBorder: field(p.outlineVariant.withValues(alpha: 0.6)),
        labelStyle: text.bodyMedium?.copyWith(color: muted),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => text.labelMedium!.copyWith(
            color: states.contains(WidgetState.error)
                ? AppTokens.error
                : states.contains(WidgetState.focused)
                    ? p.primary
                    : muted,
          ),
        ),
        hintStyle: text.bodyMedium?.copyWith(color: AppTokens.outline),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: AppTokens.error),
        prefixIconColor: muted,
        suffixIconColor: muted,
        prefixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 40),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: controlSize,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: const RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: controlSize,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: const RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: text.labelLarge,
          elevation: 0,
          backgroundColor: p.surface,
          foregroundColor: p.primary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: controlSize,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: const RoundedRectangleBorder(borderRadius: radiusMd),
          side: BorderSide(color: p.outlineVariant),
          foregroundColor: ink,
          backgroundColor: p.surface,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: const RoundedRectangleBorder(borderRadius: radiusMd),
          foregroundColor: p.primary,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ink,
          shape: const RoundedRectangleBorder(borderRadius: radiusMd),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 3,
        shape: const RoundedRectangleBorder(borderRadius: radiusLg),
        extendedTextStyle: text.labelLarge,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
        extendedSizeConstraints:
            const BoxConstraints.tightFor(height: 48),
        smallSizeConstraints:
            const BoxConstraints.tightFor(width: 40, height: 40),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: AppTokens.primaryTint,
        disabledColor: AppTokens.surfaceMuted,
        checkmarkColor: AppTokens.primaryDark,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? p.primary
                : p.outlineVariant,
          ),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusSm)),
        ),
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => text.labelMedium!.copyWith(
            color: states.contains(WidgetState.selected)
                ? AppTokens.primaryDark
                : ink,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        iconTheme: const IconThemeData(size: 16, color: muted),
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: p.outlineVariant)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppTokens.primaryTint
                : p.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppTokens.primaryDark
                : muted,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppTokens.primaryDark
                : muted,
          ),
          textStyle: WidgetStatePropertyAll(text.labelMedium),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: muted,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        indicatorColor: p.primary,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: p.primary, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
        dividerColor: p.outlineVariant,
        dividerHeight: 1,
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
        tabAlignment: TabAlignment.fill,
        overlayColor:
            WidgetStatePropertyAll(p.primary.withValues(alpha: 0.06)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppTokens.surfaceMuted
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.primary
              : const Color(0xFFD3D8DF),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbIcon: const WidgetStatePropertyAll(null),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusXs)),
        ),
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? p.outlineVariant
                : AppTokens.outline,
            width: 1.6,
          ),
        ),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (states.contains(WidgetState.disabled)
                  ? AppTokens.outline
                  : p.primary)
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.primary
              : AppTokens.outline,
        ),
        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.primary,
        inactiveTrackColor: AppTokens.surfaceMuted,
        thumbColor: p.primary,
        trackHeight: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: AppTokens.surfaceMuted,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 6,
        borderRadius: const BorderRadius.all(Radius.circular(3)),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: p.accent,
        textColor: ink,
        textStyle: text.labelSmall?.copyWith(fontWeight: FontWeight.w800),
        smallSize: 8,
        largeSize: 16,
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusXl)),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: AppTokens.text700),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        showDragHandle: true,
        dragHandleColor: const Color(0xFFCBD1D9),
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppTokens.radiusXl)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLg,
          side: BorderSide(color: p.outlineVariant),
        ),
        textStyle: text.bodyMedium,
        labelTextStyle: WidgetStatePropertyAll(text.bodyMedium),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: radiusLg,
              side: BorderSide(color: p.outlineVariant),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: text.bodyMedium,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusLg),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.inverseSurface,
        contentTextStyle:
            text.bodyMedium?.copyWith(color: p.onInverseSurface),
        actionTextColor: AppTokens.accent,
        shape: const RoundedRectangleBorder(borderRadius: radiusMd),
        elevation: 4,
        insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.inverseSurface,
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        textStyle: text.labelMedium?.copyWith(color: p.onInverseSurface),
        waitDuration: const Duration(milliseconds: 400),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        iconColor: muted,
        collapsedIconColor: muted,
        textColor: ink,
        collapsedTextColor: ink,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: AppTokens.bottomNavBarHeight,
        indicatorColor: AppTokens.primaryTint,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateTextStyle.resolveWith(
          (states) => text.labelSmall!.copyWith(
            color: states.contains(WidgetState.selected)
                ? AppTokens.primaryDark
                : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: AppTokens.bottomNavTabIconSize,
            color: states.contains(WidgetState.selected)
                ? AppTokens.primaryDark
                : muted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surface,
        indicatorColor: AppTokens.primaryTint,
        selectedIconTheme: const IconThemeData(color: AppTokens.primaryDark),
        unselectedIconTheme: const IconThemeData(color: muted),
        selectedLabelTextStyle:
            text.labelMedium?.copyWith(color: AppTokens.primaryDark),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: muted),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: p.primary,
        headerForegroundColor: Colors.white,
        todayBorder: BorderSide(color: p.primary),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusXl)),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusXl)),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        PlanerzColors(
          info: p.info,
          infoContainer: p.infoContainer,
          success: p.success,
          successContainer: p.successContainer,
          warning: p.warning,
          warningContainer: p.warningContainer,
        ),
      ],
    );
  }
}
