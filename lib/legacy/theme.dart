import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'models.dart';

/// Shared Tasko v2 surfaces, preserving the original light and dark colors.
class TaskoColors {
  static const lightBackground = Color(0xFFE9EEF2);
  static const darkBackground = Color(0xFF0C141C);

  static Color background(BuildContext c) =>
      Theme.of(c).scaffoldBackgroundColor;
  static Color card(BuildContext c) => Theme.of(c).cardTheme.color!;
  static Color column(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
      ? Theme.of(c).colorScheme.surfaceContainerLow
      : Theme.of(c).colorScheme.surfaceContainer;
}

class StatusPalette {
  final Color foreground, background, ink;
  final IconData icon;
  const StatusPalette(this.foreground, this.background, this.ink, this.icon);
  static StatusPalette of(TaskStatus s, Brightness b) {
    const icons = [
      Symbols.radio_button_unchecked_sharp,
      Symbols.clock_loader_40_sharp,
      Symbols.visibility_sharp,
      Symbols.block_sharp,
      Symbols.check_circle_sharp,
    ];
    const light = [
      [0xFF5E6F82, 0xFFE6EBF0, 0xFF2E3D4C],
      [0xFF1F6FB2, 0xFFE0ECF7, 0xFF154E7E],
      [0xFF0E7C86, 0xFFDCF0F1, 0xFF0A5960],
      [0xFFB3264E, 0xFFF7E0E6, 0xFF8A1C3C],
      [0xFF4F7A28, 0xFFE6EFDB, 0xFF3A5A1C],
    ];
    const dark = [
      [0xFF8D9DAE, 0xFF1E2A37, 0xFFB9C6D2],
      [0xFF5FA6E3, 0xFF13283C, 0xFFA3CDF0],
      [0xFF43B7C0, 0xFF0F2D31, 0xFF93D8DD],
      [0xFFEF6E8F, 0xFF35151F, 0xFFF5A8BB],
      [0xFF93BD66, 0xFF1B2B15, 0xFFBBD89F],
    ];
    final c = (b == Brightness.dark ? dark : light)[s.index];
    return StatusPalette(Color(c[0]), Color(c[1]), Color(c[2]), icons[s.index]);
  }
}

TextStyle monoStyle(BuildContext c, {double size = 11, Color? color}) =>
    TextStyle(
      fontFamily: 'JetBrains Mono',
      fontSize: size,
      height: 1.4,
      color: color ?? Theme.of(c).colorScheme.onSurfaceVariant,
    );

ThemeData taskoTheme(Brightness brightness) {
  final d = brightness == Brightness.dark;
  Color c(int l, int dark) => Color(d ? dark : l);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c(0xFFAD4C0C, 0xFFF08A4B),
    onPrimary: c(0xFFFFFFFF, 0xFF1E0E03),
    primaryContainer: c(0xFFFBE7DA, 0xFF4A230B),
    onPrimaryContainer: c(0xFF5A2604, 0xFFFFD6BC),
    secondary: c(0xFF3E5366, 0xFFA9BCCD),
    onSecondary: c(0xFFFFFFFF, 0xFF10202D),
    secondaryContainer: c(0xFFDCE5EC, 0xFF22313F),
    onSecondaryContainer: c(0xFF1B2B3A, 0xFFD3DEE8),
    error: c(0xFFB3264E, 0xFFEF6E8F),
    onError: c(0xFFFFFFFF, 0xFF3D0717),
    errorContainer: c(0xFFF7E0E6, 0xFF35151F),
    onErrorContainer: c(0xFF8A1C3C, 0xFFF5A8BB),
    surface: c(0xFFF7F9FA, 0xFF111B25),
    onSurface: c(0xFF0E1B2C, 0xFFDCE3EA),
    onSurfaceVariant: c(0xFF4B5B6B, 0xFF93A3B3),
    surfaceContainerLowest: c(0xFFFFFFFF, 0xFF080F15),
    surfaceContainerLow: c(0xFFF3F6F8, 0xFF131E28),
    surfaceContainer: c(0xFFEEF2F5, 0xFF172230),
    surfaceContainerHigh: c(0xFFE9EEF2, 0xFF1C2836),
    surfaceContainerHighest: c(0xFFE2E8ED, 0xFF233140),
    outline: c(0xFF7F8E9D, 0xFF66788A),
    outlineVariant: c(0xFFCBD5DD, 0xFF2C3B4A),
    surfaceTint: Colors.transparent,
    inverseSurface: c(0xFF1B2836, 0xFFDCE3EA),
    onInverseSurface: c(0xFFE6ECF1, 0xFF172230),
    inversePrimary: c(0xFFF08A4B, 0xFF8F3E09),
  );
  TextStyle t(
    String family,
    double size,
    FontWeight weight,
    double line, {
    double tracking = 0,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: weight,
    height: line / size,
    letterSpacing: tracking,
    color: scheme.onSurface,
  );
  final text = TextTheme(
    displayLarge: t('Geologica', 54, FontWeight.w300, 58, tracking: -1),
    displayMedium: t('Geologica', 45, FontWeight.w300, 50, tracking: -.8),
    displaySmall: t('Geologica', 37, FontWeight.w300, 42, tracking: -.5),
    headlineLarge: t('Geologica', 31, FontWeight.w700, 36, tracking: -.4),
    headlineMedium: t('Geologica', 26, FontWeight.w700, 30, tracking: -.3),
    headlineSmall: t('Geologica', 21, FontWeight.w700, 26, tracking: -.2),
    titleLarge: t('Geologica', 18, FontWeight.w700, 24, tracking: -.1),
    titleMedium: t('Onest', 15, FontWeight.w600, 20),
    titleSmall: t('Onest', 13, FontWeight.w600, 18, tracking: .1),
    bodyLarge: t('Onest', 15, FontWeight.w400, 22),
    bodyMedium: t('Onest', 13, FontWeight.w400, 19),
    bodySmall: t('Onest', 11, FontWeight.w400, 16, tracking: .2),
    labelLarge: t('Onest', 13, FontWeight.w600, 16, tracking: .1),
    labelMedium: t('Onest', 11, FontWeight.w600, 14, tracking: .4),
    labelSmall: t('Onest', 10, FontWeight.w600, 12, tracking: .5),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: text,
    fontFamily: 'Onest',
    scaffoldBackgroundColor: d
        ? TaskoColors.darkBackground
        : TaskoColors.lightBackground,
    splashFactory: NoSplash.splashFactory,
    iconTheme: IconThemeData(
      size: 20,
      weight: 300,
      color: scheme.onSurfaceVariant,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge,
      centerTitle: false,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: shape,
        minimumSize: const Size(48, 48),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(shape),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: shape,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 2,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: scheme.surface,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: shape,
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: shape,
        side: BorderSide(color: scheme.outline),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c(0xFFFFFFFF, 0xFF172230),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    cardTheme: CardThemeData(
      color: c(0xFFFFFFFF, 0xFF172230),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      showDragHandle: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: shape,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      elevation: 0,
      height: 80,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: shape,
      selectedLabelTextStyle: text.labelLarge,
      unselectedLabelTextStyle: text.bodyMedium,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: text.labelLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      shape: shape,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.onSurface,
      linearTrackColor: scheme.surfaceContainerHighest,
      linearMinHeight: 4,
    ),
  );
}
