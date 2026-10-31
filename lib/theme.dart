import 'package:flutter/material.dart';

// DeckPad visual language: quiet graphite surfaces, hairline borders, one soft accent.
const kBg = Color(0xFF09090B);
const kSurface = Color(0xFF121214);
const kSurface2 = Color(0xFF17171A);
const kBorder = Color(0xFF1F1F23);
const kBorder2 = Color(0xFF25252A);
const kText = Color(0xFFEDEDEF);
const kMuted = Color(0xFF8E8E97);
const kAccent = Color(0xFF8B9CFF);
const kLive = Color(0xFFFF5D6C);
const kOk = Color(0xFF5EE3A1);

/// Softens a button's stored colour into a pastel that reads on the dark surface (used for icons / active tint).
Color accentFor(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withSaturation(h.saturation.clamp(0.0, 0.85)).withLightness(0.72).toColor();
}

/// Small uppercase section label used across the tool and settings screens.
TextStyle sectionStyle() => const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.1, color: kMuted);

ThemeData buildTheme() {
  final scheme = ColorScheme.dark(
    primary: kAccent,
    onPrimary: kBg,
    secondary: kAccent,
    surface: kSurface,
    onSurface: kText,
    surfaceContainerHighest: kSurface2,
    surfaceContainerHigh: kSurface2,
    surfaceContainer: kSurface,
    secondaryContainer: kBorder2,
    onSecondaryContainer: kText,
    primaryContainer: kAccent.withValues(alpha: 0.16),
    onPrimaryContainer: kText,
    outline: kBorder2,
    outlineVariant: kBorder,
    error: kLive,
  );
  final base = ThemeData(useMaterial3: true, brightness: Brightness.dark, colorScheme: scheme, scaffoldBackgroundColor: kBg);
  final shape14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),
    splashFactory: InkRipple.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: kText),
    ),
    cardTheme: CardThemeData(
      color: kSurface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: kBorder)),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF1C1C20), thickness: 1, space: 1),
    listTileTheme: const ListTileThemeData(iconColor: kMuted, textColor: kText, subtitleTextStyle: TextStyle(color: kMuted, fontSize: 12.5)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      labelStyle: const TextStyle(color: kMuted),
      hintStyle: const TextStyle(color: Color(0xFF5E5E66)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kAccent, width: 1.2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: kText, foregroundColor: kBg, minimumSize: const Size(0, 46), shape: shape14, textStyle: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: kText, side: const BorderSide(color: kBorder2), minimumSize: const Size(0, 44), shape: shape14),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kAccent, shape: shape14)),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: kAccent.withValues(alpha: 0.16),
      side: const BorderSide(color: kBorder2),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontSize: 13, color: kText),
      showCheckmark: false,
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
      activeTrackColor: kAccent,
      inactiveTrackColor: kBorder2,
      thumbColor: kText,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 2),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 18),
      trackShape: RoundedRectSliderTrackShape(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kBg : kMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kAccent : kBorder2),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: kBorder2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: kSurface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kSurface2,
      contentTextStyle: const TextStyle(color: kText, fontSize: 13.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder2)),
    ),
    popupMenuTheme: PopupMenuThemeData(color: kSurface2, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kAccent),
    expansionTileTheme: const ExpansionTileThemeData(iconColor: kMuted, collapsedIconColor: kMuted, shape: Border(), collapsedShape: Border()),
  );
}
