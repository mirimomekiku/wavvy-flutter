import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Kaisu's silver, paper and Aqua vocabulary adapted for mobile.
class WavvyTheme {
  WavvyTheme._();

  /// Legacy indices are retained; 5 = Aqua and 6 = Graphite.
  static WvAppearance appearanceFor(int index) {
    switch (index) {
      case 0:
        return WvAppearance.green;
      case 1:
        return WvAppearance.red;
      case 2:
        return WvAppearance.materialYou;
      case 4:
        return WvAppearance.peach;
      case 3:
        return WvAppearance.lilac;
      case 6:
        return WvAppearance.graphite;
      default:
        return WvAppearance.aqua;
    }
  }

  /// [system] is the platform's wallpaper-derived scheme for this brightness
  /// (only used by the Material You appearance).
  static ThemeData light(
    WvAppearance appearance, {
    Color? seed,
    ColorScheme? system,
  }) => _build(
    WvPalette(dark: false, appearance: appearance, seed: seed, system: system),
  );

  static ThemeData dark(
    WvAppearance appearance, {
    Color? seed,
    ColorScheme? system,
  }) => _build(
    WvPalette(dark: true, appearance: appearance, seed: seed, system: system),
  );

  static ThemeData _build(WvPalette a) {
    final scheme = a.scheme;
    final brightness = scheme.brightness;

    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'WorkSans',
      brightness: brightness,
      colorScheme: scheme,
    );

    final textTheme = base.textTheme.apply(
      bodyColor: a.text,
      displayColor: a.text,
    );

    return base.copyWith(
      extensions: [a],
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        prefixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        filled: true,
        fillColor: a.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: a.separator),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: a.separator),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: a.accent, width: 1.5),
        ),
      ),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: a.background,
      canvasColor: a.background,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      dividerTheme: DividerThemeData(
        thickness: Ds.hairline,
        space: Ds.hairline,
        color: a.separator,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: a.background,
        foregroundColor: a.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: a.surfaceHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ds.radiusXL),
          side: BorderSide(color: a.separator, width: 1),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: a.surfaceHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Ds.radiusXL),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: a.scheme.inverseSurface,
        contentTextStyle: TextStyle(color: a.scheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ds.radiusM),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: a.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ds.radiusM),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: a.accent,
        linearTrackColor: a.surfaceHighest,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: a.accent,
        selectionColor: a.accent.withValues(alpha: 0.35),
        selectionHandleColor: a.accent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: a.accent,
        inactiveTrackColor: a.surfaceHighest,
        thumbColor: a.accent,
        overlayColor: a.accent.withValues(alpha: 0.12),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
    );
  }
}
