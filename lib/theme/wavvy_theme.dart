import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Classic Mac OS X Aqua theme. Material components still work (so screens
/// that haven't been restyled stay usable) but are recolored to Aqua, with
/// no ripples and Cupertino page motion.
class WavvyTheme {
  WavvyTheme._();

  static AquaAppearance appearanceFor(int index) =>
      index == 1 ? AquaAppearance.graphite : AquaAppearance.blue;

  static ThemeData light(AquaAppearance appearance, {Color? seed}) => _build(
    AquaPalette(dark: false, appearance: appearance, seed: seed),
  );

  static ThemeData dark(AquaAppearance appearance, {Color? seed}) => _build(
    AquaPalette(dark: true, appearance: appearance, seed: seed),
  );

  static ThemeData _build(AquaPalette a) {
    final brightness = a.dark ? Brightness.dark : Brightness.light;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: a.gelBlue[2],
          brightness: brightness,
        ).copyWith(
          primary: a.accent,
          onPrimary: Colors.white,
          primaryContainer: a.selection[1],
          onPrimaryContainer: Colors.white,
          surface: a.background,
          onSurface: a.text,
          onSurfaceVariant: a.textSecondary,
          surfaceContainerLowest: a.background,
          surfaceContainerLow: a.background,
          surfaceContainer: a.stripe,
          surfaceContainerHigh: a.background,
          surfaceContainerHighest: a.stripe,
          outline: a.border,
          outlineVariant: a.separator,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );

    // Lucida Grande isn't available; Noto Sans is the closest humanist face.
    final textTheme = GoogleFonts.notoSansTextTheme(
      base.textTheme,
    ).apply(bodyColor: a.text, displayColor: a.text);

    return base.copyWith(
      extensions: [a],
      textTheme: textTheme,
      primaryTextTheme: GoogleFonts.notoSansTextTheme(base.primaryTextTheme),
      scaffoldBackgroundColor: a.background,
      canvasColor: a.background,
      // Aqua has no Material ripples.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      dividerTheme: DividerThemeData(
        thickness: Ds.hairline,
        space: Ds.hairline,
        color: a.separator,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: a.toolbar[0],
        foregroundColor: a.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: a.background,
        elevation: 14,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ds.radiusM + 2),
          side: BorderSide(color: a.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: a.background,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Ds.radiusL),
          ),
          side: BorderSide(color: a.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: a.dark
            ? const Color(0xFF3A3A3A)
            : const Color(0xFF2B2B2B),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ds.radiusM),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: a.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ds.radiusS),
          side: BorderSide(color: a.border),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: a.gelBlue[2],
        inactiveTrackColor: a.separator,
        thumbColor: a.gelGray[1],
        trackHeight: 5,
      ),
    );
  }
}
