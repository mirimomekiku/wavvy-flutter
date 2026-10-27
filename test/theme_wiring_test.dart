import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/providers/palette_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/snackbar.utils.dart';
import 'package:wavvy/wavvy_app.dart';

/// Palette notifier whose accent the test can set directly (the real one
/// derives it from album art through platform channels).
class _FakePalette extends PaletteNotifier {
  @override
  PaletteState build() => const PaletteState();

  void setAccent(Color? accent) {
    state = PaletteState(playerColor: accent, accent: accent);
  }
}

class _Harness {
  late ProviderContainer container;
  late ThemeData theme;
  late WvPalette palette;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [paletteProvider.overrideWith(_FakePalette.new)],
        child: WavvyMaterialApp(
          home: Builder(
            builder: (context) {
              theme = Theme.of(context);
              palette = Wv.of(context);
              container = ProviderScope.containerOf(context);
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SettingsNotifier get settings => container.read(settingsProvider.notifier);
  _FakePalette get paletteNotifier =>
      container.read(paletteProvider.notifier) as _FakePalette;
}

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  setUpAll(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('light / dark mode', () {
    testWidgets('toggling dark mode switches the whole theme and back', (
      tester,
    ) async {
      final h = _Harness();
      await h.pump(tester);

      expect(h.theme.brightness, Brightness.light);
      expect(h.palette.dark, isFalse);
      final lightBg = h.theme.scaffoldBackgroundColor;
      expect(lightBg, h.palette.background);

      await h.settings.toggleDarkMode(true);
      await tester.pumpAndSettle();

      expect(h.theme.brightness, Brightness.dark);
      expect(h.palette.dark, isTrue);
      expect(h.theme.scaffoldBackgroundColor, h.palette.background);
      expect(
        h.theme.scaffoldBackgroundColor.computeLuminance(),
        lessThan(lightBg.computeLuminance()),
      );
      expect(h.theme.scaffoldBackgroundColor, h.palette.background);
      expect(h.theme.colorScheme.onSurface, h.palette.text);

      await h.settings.toggleDarkMode(false);
      await tester.pumpAndSettle();

      expect(h.theme.brightness, Brightness.light);
      expect(h.theme.scaffoldBackgroundColor, lightBg);
    });

    testWidgets('text stays readable on every surface in both modes', (
      tester,
    ) async {
      final h = _Harness();
      await h.pump(tester);

      for (final dark in [false, true]) {
        await h.settings.toggleDarkMode(dark);
        await tester.pumpAndSettle();
        final p = h.palette;
        for (final bg in [p.background, p.surface, p.surfaceHigh]) {
          expect(_contrast(p.text, bg), greaterThan(7));
          expect(_contrast(p.textSecondary, bg), greaterThan(4.5));
        }
      }
    });
  });

  group('appearance setting', () {
    testWidgets('Aqua is the default and every accent is selectable', (
      tester,
    ) async {
      final h = _Harness();
      await h.pump(tester);
      expect(h.palette.appearance, WvAppearance.aqua);
      expect(h.theme.colorScheme.primary, h.palette.accent);

      final accents = <Color>{h.palette.accent};
      for (final entry in WavvyTheme.byIndex.entries) {
        await h.settings.updateThemeIndex(entry.key);
        await tester.pumpAndSettle();
        expect(h.palette.appearance, entry.value);
        expect(h.theme.colorScheme.primary, h.palette.accent);
        accents.add(h.palette.accent);
      }
      // Eight themes, eight different accents.
      expect(accents.length, WavvyTheme.byIndex.length);
    });

    testWidgets('the appearance survives switching light/dark', (tester) async {
      final h = _Harness();
      await h.pump(tester);

      await h.settings.updateThemeIndex(1);
      await h.settings.toggleDarkMode(true);
      await tester.pumpAndSettle();
      expect(h.palette.appearance, WvAppearance.red);
      expect(h.theme.brightness, Brightness.dark);

      await h.settings.toggleDarkMode(false);
      await tester.pumpAndSettle();
      expect(h.palette.appearance, WvAppearance.red);
    });

    test('accents are Aqua turned around the color wheel, as in Kaisu', () {
      final aqua = HSLColor.fromColor(
        WvPalette(dark: false, appearance: WvAppearance.aqua).seed ??
            const Color(0xFF356FCB),
      );
      expect(aqua, isNotNull);
      const turns = {
        WvAppearance.orange: 175.0,
        WvAppearance.green: 265.0,
        WvAppearance.purple: 65.0,
        WvAppearance.pink: 115.0,
        WvAppearance.red: 145.0,
        WvAppearance.teal: 320.0,
      };
      expect(WvPalette.hueShift, turns);
      // The resulting hues: orange, green, purple, pink, red, teal.
      double hue(WvAppearance a) =>
          HSLColor.fromColor(WvPalette(dark: false, appearance: a).accent).hue;
      double near(double a, double b) {
        final d = (a - b).abs() % 360;
        return d > 180 ? 360 - d : d;
      }

      final base = hue(WvAppearance.aqua);
      for (final e in turns.entries) {
        // Lightness is adjusted for readability, so only the hue is compared.
        expect(
          near(hue(e.key), (base + e.value) % 360),
          lessThan(8),
          reason: '${e.key}',
        );
      }
    });

    for (final dark in [false, true]) {
      for (final appearance in WvAppearance.values) {
        test('${appearance.name} is readable (${dark ? 'dark' : 'light'})', () {
          final p = WvPalette(dark: dark, appearance: appearance);
          expect(
            _contrast(p.accentText, p.background),
            greaterThanOrEqualTo(4.5),
            reason: 'accent text on the page',
          );
          expect(
            _contrast(p.accentText, p.surface),
            greaterThanOrEqualTo(4.5),
            reason: 'accent text on a card',
          );
          expect(
            _contrast(p.onAccent, p.accent),
            greaterThanOrEqualTo(4.5),
            reason: 'text on the accent fill',
          );
          expect(
            _contrast(p.onChipSelected, p.chipSelected),
            greaterThanOrEqualTo(4.5),
            reason: 'selected chip',
          );
        });
      }
    }
  });

  testWidgets('explicit companion themes override album colors and persist', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);
    await h.settings.toggleDynamicColors(true);
    h.paletteNotifier.setAccent(const Color(0xFF2962FF));
    await tester.pumpAndSettle();
    await h.settings.updateThemeIndex(6);
    await tester.pumpAndSettle();
    expect(h.palette.appearance, WvAppearance.graphite);
    expect(h.palette.seed, isNull);
    expect(h.container.read(settingsProvider).enableDynamicColors, isFalse);
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(settingsProvider.notifier).load();
    expect(restored.read(settingsProvider).currentThemeIndex, 6);
    expect(restored.read(settingsProvider).enableDynamicColors, isFalse);
  });

  group('saved color themes from older versions', () {
    Future<ProviderContainer> loadWith(int? saved, {bool dark = false}) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      if (saved != null) await prefs.setInt('theme_scheme_index', saved);
      await prefs.setBool('feature_dark_mode', dark);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.notifier).load();
      return container;
    }

    testWidgets('are carried over to the closest current theme', (
      tester,
    ) async {
      // Mint, Rose, System, Lilac, Peach.
      for (final (old, now) in [(0, 8), (1, 11), (2, 5), (3, 9), (4, 7)]) {
        final c = await loadWith(old);
        expect(
          c.read(settingsProvider).currentThemeIndex,
          now,
          reason: 'index $old',
        );
      }
    });

    testWidgets('current values are kept, and anything unknown is Aqua', (
      tester,
    ) async {
      for (final index in WavvyTheme.byIndex.keys) {
        expect(
          (await loadWith(index)).read(settingsProvider).currentThemeIndex,
          index,
        );
      }
      for (final bad in [null, 99, -1]) {
        expect(
          (await loadWith(bad)).read(settingsProvider).currentThemeIndex,
          5,
        );
      }
    });

    testWidgets('brightness is kept when the theme is migrated', (
      tester,
    ) async {
      final c = await loadWith(3, dark: true);
      expect(c.read(settingsProvider).currentThemeIndex, 9);
      expect(c.read(settingsProvider).isDarkMode, isTrue);
    });

    test('there is no System theme to select', () {
      expect(WavvyTheme.byIndex.values.map((a) => a.name).toSet(), {
        'aqua',
        'orange',
        'green',
        'purple',
        'pink',
        'red',
        'teal',
        'graphite',
      });
    });
  });

  group('dynamic colors', () {
    const blue = Color(0xFF2962FF);

    testWidgets('the album color becomes the accent and theme primary', (
      tester,
    ) async {
      final h = _Harness();
      await h.pump(tester);
      await h.settings.toggleDynamicColors(true);
      await tester.pumpAndSettle();
      final before = h.palette.accent;

      h.paletteNotifier.setAccent(blue);
      await tester.pumpAndSettle();

      expect(h.palette.seed, blue);
      expect(h.palette.accent, isNot(before));
      expect(h.theme.colorScheme.primary, h.palette.accent);
      // The whole tonal scheme follows, not just one color.
      expect(h.palette.primaryContainer, isNot(h.palette.surfaceHigh));
    });

    testWidgets('turning Dynamic Colors off restores the appearance accent', (
      tester,
    ) async {
      final h = _Harness();
      await h.pump(tester);
      await h.settings.toggleDynamicColors(true);
      await tester.pumpAndSettle();
      final before = h.palette.accent;

      h.paletteNotifier.setAccent(blue);
      await tester.pumpAndSettle();
      expect(h.palette.seed, blue);

      await h.settings.toggleDynamicColors(false);
      await tester.pumpAndSettle();
      expect(h.palette.seed, isNull);
      expect(h.palette.accent, before);

      await h.settings.toggleDynamicColors(true);
      await tester.pumpAndSettle();
      expect(h.palette.seed, blue);
    });

    testWidgets('works in dark mode and follows the next song', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await h.settings.toggleDynamicColors(true);
      await tester.pumpAndSettle();
      final before = h.palette.accent;
      await h.settings.toggleDarkMode(true);
      h.paletteNotifier.setAccent(blue);
      await tester.pumpAndSettle();

      expect(h.theme.brightness, Brightness.dark);
      final first = h.palette.accent;
      expect(first, isNot(before));

      h.paletteNotifier.setAccent(const Color(0xFFE91E63)); // pink
      await tester.pumpAndSettle();
      expect(h.palette.accent, isNot(first));

      h.paletteNotifier.setAccent(null); // nothing playing
      await tester.pumpAndSettle();
      expect(h.palette.seed, isNull);
      expect(h.palette.accent, isNot(first));
    });

    testWidgets('gray / colorless album art keeps the appearance accent', (
      tester,
    ) async {
      final h = _Harness();
      await h.pump(tester);
      await h.settings.toggleDynamicColors(true);
      await tester.pumpAndSettle();
      final before = h.palette.accent;

      h.paletteNotifier.setAccent(const Color(0xFF808080));
      await tester.pumpAndSettle();
      expect(h.palette.accent, before);
    });
  });

  group('every album color stays legible', () {
    const seeds = <String, Color>{
      'red': Color(0xFFD32F2F),
      'orange': Color(0xFFFF9800),
      'yellow': Color(0xFFFFEB3B),
      'lime': Color(0xFFCDDC39),
      'green': Color(0xFF2E7D32),
      'teal': Color(0xFF00897B),
      'cyan': Color(0xFF00E5FF),
      'blue': Color(0xFF1A237E),
      'purple': Color(0xFF6A1B9A),
      'pink': Color(0xFFFF4081),
      'near-black saturated': Color(0xFF200010),
      'near-white tinted': Color(0xFFFFF0F0),
    };

    for (final dark in [false, true]) {
      for (final entry in seeds.entries) {
        test('${entry.key} (${dark ? 'dark' : 'light'})', () {
          final p = WvPalette(
            dark: dark,
            appearance: WvAppearance.aqua,
            seed: entry.value,
          );
          expect(
            _contrast(p.accentText, p.background),
            greaterThanOrEqualTo(3.0),
            reason: 'accent text on background',
          );
          expect(
            _contrast(p.onAccent, p.accent),
            greaterThanOrEqualTo(3.0),
            reason: 'content on the accent fill',
          );
          expect(
            _contrast(p.onChipSelected, p.chipSelected),
            greaterThanOrEqualTo(4.5),
            reason: 'selected chip label',
          );
          expect(
            _contrast(p.onPrimaryContainer, p.primaryContainer),
            greaterThanOrEqualTo(4.5),
            reason: 'content on the primary container (now-playing)',
          );
          expect(
            _contrast(p.accent, p.background),
            greaterThanOrEqualTo(1.8),
            reason: 'accent fill vs background',
          );
        });
      }
    }

    test('every appearance is legible in both modes', () {
      for (final appearance in WvAppearance.values) {
        for (final dark in [false, true]) {
          final p = WvPalette(dark: dark, appearance: appearance);
          expect(
            _contrast(p.accentText, p.background),
            greaterThanOrEqualTo(3),
          );
          expect(_contrast(p.onAccent, p.accent), greaterThanOrEqualTo(3));
          expect(
            _contrast(p.onChipSelected, p.chipSelected),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    });
  });

  group('toast', () {
    for (final dark in [false, true]) {
      testWidgets('follows the ${dark ? 'dark' : 'light'} theme', (
        tester,
      ) async {
        final h = _Harness();
        await h.pump(tester);
        await h.settings.toggleDarkMode(dark);
        await tester.pumpAndSettle();

        AppSnackbar.showSnackbar('Saved', 'All good');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Saved'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
