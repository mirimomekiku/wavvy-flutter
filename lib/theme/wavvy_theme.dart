import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Kaisu's silver, paper and Aqua vocabulary adapted for mobile.
class WavvyTheme {
  WavvyTheme._();

  /// The saved theme index of each appearance. 5 and 6 are the original Aqua
  /// and Graphite and keep their numbers; the accents follow.
  static const Map<int, WvAppearance> byIndex = {
    5: WvAppearance.aqua,
    6: WvAppearance.graphite,
    7: WvAppearance.orange,
    8: WvAppearance.green,
    9: WvAppearance.purple,
    10: WvAppearance.pink,
    11: WvAppearance.red,
    12: WvAppearance.teal,
  };

  static const int defaultIndex = 5;

  /// Indices saved by older versions: Mint and Rose become Green and Red,
  /// Lilac and Peach become Purple and Orange, and the retired System theme
  /// becomes Aqua.
  static const Map<int, int> migratedIndex = {0: 8, 1: 11, 2: 5, 3: 9, 4: 7};

  /// The index to use for a saved value, which may come from an older version.
  static int normalizeIndex(int? saved) {
    if (saved == null) return defaultIndex;
    if (byIndex.containsKey(saved)) return saved;
    return migratedIndex[saved] ?? defaultIndex;
  }

  static WvAppearance appearanceFor(int index) =>
      byIndex[normalizeIndex(index)]!;

  /// Building a theme generates a tonal scheme and a full ThemeData, so the
  /// result is kept: switching light/dark or back to an earlier appearance or
  /// album color reuses the finished theme instead of rebuilding it. Oldest
  /// entries go first, so album colors don't pile up.
  static final Map<(bool, WvAppearance, int?), ThemeData> _cache = {};
  static const int _cacheLimit = 24;

  static ThemeData _themed(bool dark, WvAppearance appearance, Color? seed) {
    final key = (dark, appearance, seed?.toARGB32());
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit;
    final theme = _build(
      WvPalette(dark: dark, appearance: appearance, seed: seed),
    );
    _cache[key] = theme;
    if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
    return theme;
  }

  static ThemeData light(WvAppearance appearance, {Color? seed}) =>
      _themed(false, appearance, seed);

  static ThemeData dark(WvAppearance appearance, {Color? seed}) =>
      _themed(true, appearance, seed);

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
