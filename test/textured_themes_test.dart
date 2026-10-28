import 'dart:ui' as ui;

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
import 'package:wavvy/theme/wavvy_texture.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/wavvy_app.dart';
import 'package:wavvy/widgets/theme_selector.dart';

class _FakePalette extends PaletteNotifier {
  @override
  PaletteState build() => const PaletteState();
}

const _textured = [WvAppearance.pinstripe, WvAppearance.brushedMetal];

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('tokens', () {
    test('differ per appearance and between light and dark', () {
      for (final dark in [false, true]) {
        final seen = <int>{};
        for (final a in WvAppearance.values) {
          final p = WvPalette(dark: dark, appearance: a);
          seen.add(p.accent.toARGB32());
        }
        expect(seen.length, WvAppearance.values.length);
      }
      for (final a in _textured) {
        final light = WvPalette(dark: false, appearance: a);
        final dark = WvPalette(dark: true, appearance: a);
        expect(light.background, isNot(dark.background));
        expect(light.accent, isNot(dark.accent));
        expect(
          light.background.computeLuminance(),
          greaterThan(dark.background.computeLuminance()),
        );
      }
      for (final dark in [false, true]) {
        final aqua = WvPalette(dark: dark, appearance: WvAppearance.aqua);
        final pin = WvPalette(dark: dark, appearance: WvAppearance.pinstripe);
        final metal = WvPalette(
          dark: dark,
          appearance: WvAppearance.brushedMetal,
        );
        expect(pin.background, isNot(aqua.background));
        expect(metal.background, isNot(aqua.background));
        expect(metal.background, isNot(pin.background));
        expect(metal.chromeGradient, isNot(aqua.chromeGradient));
      }
    });

    test('only the textured looks have a texture', () {
      for (final a in WvAppearance.values) {
        final p = WvPalette(dark: false, appearance: a);
        final textured = _textured.contains(a);
        expect(p.textureKind != null, textured, reason: a.name);
        expect(p.pageTexture != null, textured, reason: a.name);
        expect(p.pageColor == Colors.transparent, textured, reason: a.name);
        expect(
          p.chromeGrain != null,
          a == WvAppearance.brushedMetal,
          reason: a.name,
        );
      }
    });

    test('album colors tint the accent, the texture and page stay neutral', () {
      for (final a in _textured) {
        for (final dark in [false, true]) {
          final plain = WvPalette(dark: dark, appearance: a);
          final album = WvPalette(
            dark: dark,
            appearance: a,
            seed: const Color(0xFFD32F2F),
          );
          expect(album.accent, isNot(plain.accent));
          expect(album.background, plain.background);
          expect(album.textureKind, plain.textureKind);
        }
      }
    });

    test('the text is readable on the page and the cards', () {
      for (final a in _textured) {
        for (final dark in [false, true]) {
          final p = WvPalette(dark: dark, appearance: a);
          for (final bg in [p.background, p.surface, p.surfaceHigh]) {
            double c(Color x, Color y) {
              final l1 = x.computeLuminance(), l2 = y.computeLuminance();
              return (l1 > l2 ? l1 + 0.05 : l2 + 0.05) /
                  (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
            }

            expect(c(p.text, bg), greaterThan(7));
            expect(c(p.textSecondary, bg), greaterThan(4.5));
            expect(c(p.accentText, p.background), greaterThanOrEqualTo(4.5));
          }
        }
      }
    });
  });

  group('indices', () {
    test('round trip, and older values still migrate', () {
      expect(WavvyTheme.appearanceFor(13), WvAppearance.pinstripe);
      expect(WavvyTheme.appearanceFor(14), WvAppearance.brushedMetal);
      expect(WavvyTheme.normalizeIndex(13), 13);
      expect(WavvyTheme.normalizeIndex(14), 14);
      for (final e in WavvyTheme.byIndex.entries) {
        expect(WavvyTheme.normalizeIndex(e.key), e.key);
        expect(WavvyTheme.appearanceFor(e.key), e.value);
      }
      expect(WvAppearance.values.toSet(), WavvyTheme.byIndex.values.toSet());
      // Aqua and Graphite keep their numbers.
      expect(WavvyTheme.byIndex[5], WvAppearance.aqua);
      expect(WavvyTheme.byIndex[6], WvAppearance.graphite);
      // Retired System and the other old values become Aqua or their accent.
      expect(WavvyTheme.normalizeIndex(2), 5);
      expect(WavvyTheme.normalizeIndex(0), 8);
      expect(WavvyTheme.normalizeIndex(99), 5);
      expect(WavvyTheme.normalizeIndex(null), 5);
    });

    test('a saved Pinstripe or Brushed Metal survives a restart', () async {
      final first = ProviderContainer();
      addTearDown(first.dispose);
      first.read(settingsProvider);
      await first.read(settingsProvider.notifier).updateThemeIndex(14);
      expect(first.read(settingsProvider).currentThemeIndex, 14);
      // What load() reads back on the next start.
      final stored = await SharedPreferencesAsync().getInt(
        'theme_scheme_index',
      );
      expect(WavvyTheme.normalizeIndex(stored), 14);
    });

    test('the theme cache stays bounded with every appearance', () {
      for (var i = 0; i < 80; i++) {
        for (final a in WvAppearance.values) {
          WavvyTheme.light(a, seed: Color(0xFF000000 + i * 5000));
        }
      }
      final t = WavvyTheme.dark(WvAppearance.brushedMetal);
      expect(identical(t, WavvyTheme.dark(WvAppearance.brushedMetal)), isTrue);
      expect(t.extension<WvPalette>()!.appearance, WvAppearance.brushedMetal);
      expect(t.brightness, Brightness.dark);
    });
  });

  group('texture', () {
    test('tiles, shaders and decorations are made once', () {
      for (final kind in WvTextureKind.values) {
        for (final dark in [false, true]) {
          expect(
            identical(WvTextures.tile(kind, dark), WvTextures.tile(kind, dark)),
            isTrue,
          );
          expect(
            identical(
              WvTextures.shader(kind, dark),
              WvTextures.shader(kind, dark),
            ),
            isTrue,
          );
          expect(
            identical(
              WvTextures.decoration(kind, dark),
              WvTextures.decoration(kind, dark),
            ),
            isTrue,
          );
        }
      }
      expect(
        identical(
          WvPalette(
            dark: false,
            appearance: WvAppearance.brushedMetal,
          ).chromeGrain,
          WvPalette(
            dark: false,
            appearance: WvAppearance.brushedMetal,
          ).chromeGrain,
        ),
        isTrue,
      );
      final pin = WvTextures.tile(WvTextureKind.pinstripe, false);
      expect(pin.height, WvTextures.pinstripePeriod);
      final metal = WvTextures.tile(WvTextureKind.brushed, true);
      expect(metal.width, greaterThan(32));
    });

    test('the grain is the same pixels every time', () async {
      Future<List<int>> bytes(ui.Image i) async =>
          (await i.toByteData())!.buffer.asUint8List().toList();
      final a = await bytes(WvTextures.tile(WvTextureKind.brushed, false));
      final b = await bytes(WvTextures.tile(WvTextureKind.brushed, false));
      expect(a, b);
      // It has real variation: more than a handful of distinct alphas.
      expect(a.toSet().length, greaterThan(8));
    });

    test('the painter paints at several sizes without errors', () {
      for (final kind in WvTextureKind.values) {
        for (final size in const [
          Size.zero,
          Size(1, 1),
          Size(320, 640),
          Size(1080, 2400),
        ]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          WvTexturePainter(
            kind: kind,
            dark: size.width > 500,
            base: Colors.grey,
            gradient: const LinearGradient(
              colors: [Colors.white, Colors.black],
            ),
          ).paint(canvas, size);
          recorder.endRecording().dispose();
        }
      }
    });

    test('repaints only when something changed', () {
      const p = WvTexturePainter(
        kind: WvTextureKind.brushed,
        dark: false,
        base: Colors.grey,
      );
      expect(
        p.shouldRepaint(
          const WvTexturePainter(
            kind: WvTextureKind.brushed,
            dark: false,
            base: Colors.grey,
          ),
        ),
        isFalse,
      );
      expect(
        p.shouldRepaint(
          const WvTexturePainter(
            kind: WvTextureKind.brushed,
            dark: true,
            base: Colors.grey,
          ),
        ),
        isTrue,
      );
    });
  });

  group('backdrop', () {
    Widget app(WvAppearance a, {bool dark = false}) => MaterialApp(
      theme: WavvyTheme.light(a),
      darkTheme: WavvyTheme.dark(a),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      home: Builder(
        builder: (context) => WvBackdrop(
          child: Scaffold(
            backgroundColor: Wv.of(context).pageColor,
            body: const Center(child: Text('page')),
          ),
        ),
      ),
    );

    testWidgets('adds one boundary and painter only when textured', (
      tester,
    ) async {
      Finder painter() => find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is WvTexturePainter,
      );
      for (final a in WvAppearance.values) {
        await tester.pumpWidget(app(a));
        expect(
          painter(),
          _textured.contains(a) ? findsOneWidget : findsNothing,
          reason: a.name,
        );
        expect(find.text('page'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the page is opaque while a route slides over another', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: WavvyTheme.light(WvAppearance.pinstripe),
          home: Builder(
            builder: (context) => WvBackdrop(
              child: Scaffold(
                backgroundColor: Wv.of(context).pageColor,
                body: const Text('first'),
              ),
            ),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (context) => WvBackdrop(
            child: Scaffold(
              backgroundColor: Wv.of(context).pageColor,
              body: const Text('second'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Mid transition both pages exist and each carries its own opaque base.
      expect(find.byType(WvBackdrop, skipOffstage: false), findsNWidgets(2));
      final painters = tester
          .widgetList<CustomPaint>(
            find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is WvTexturePainter,
            ),
          )
          .map((w) => w.painter! as WvTexturePainter);
      expect(painters.length, 2);
      for (final p in painters) {
        expect(p.base.a, 1.0);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    for (final a in _textured) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('${a.name} renders (dark: $dark, scale $scale)', (
            tester,
          ) async {
            tester.view.physicalSize = const Size(320, 640);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: app(a, dark: dark),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('chrome with grain paints', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WavvyTheme.light(WvAppearance.brushedMetal),
          home: Builder(
            builder: (context) {
              final a = Wv.of(context);
              return Container(
                height: 60,
                decoration: BoxDecoration(
                  gradient: a.chromeGradient,
                  image: a.chromeGrain,
                  borderRadius: BorderRadius.circular(16),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('selector', () {
    Widget host({bool dark = false, double scale = 1}) => ProviderScope(
      child: MaterialApp(
        theme: WavvyTheme.light(WvAppearance.aqua),
        darkTheme: WavvyTheme.dark(WvAppearance.aqua),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: ThemeSelector(),
          ),
        ),
      ),
    );

    testWidgets('lists and selects Pinstripe and Brushed Metal', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ThemeSelector)),
      );
      for (final entry in {'Pinstripe': 13, 'Brushed Metal': 14}.entries) {
        expect(find.text(entry.key), findsOneWidget);
        await tester.tap(find.text(entry.key));
        await tester.pump();
        expect(container.read(settingsProvider).currentThemeIndex, entry.value);
        expect(
          tester.getSemantics(find.text(entry.key)),
          isSemantics(isButton: true, isSelected: true),
        );
      }
      expect(
        tester.getSemantics(find.text('Pinstripe')),
        isNot(isSemantics(isSelected: true)),
      );
      handle.dispose();
    });

    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('fits 320 wide (dark: $dark, scale $scale)', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(host(dark: dark, scale: scale));
          expect(find.text('Brushed Metal'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('wiring', () {
    for (final entry in {
      13: WvAppearance.pinstripe,
      14: WvAppearance.brushedMetal,
    }.entries) {
      testWidgets('choosing ${entry.value.name} changes the app theme', (
        tester,
      ) async {
        late ProviderContainer container;
        late WvPalette palette;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [paletteProvider.overrideWith(_FakePalette.new)],
            child: WavvyMaterialApp(
              home: Builder(
                builder: (context) {
                  palette = Wv.of(context);
                  container = ProviderScope.containerOf(context);
                  return WvBackdrop(
                    child: Scaffold(
                      backgroundColor: palette.pageColor,
                      body: const SizedBox(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(palette.appearance, WvAppearance.aqua);
        final before = palette.background;

        final settings = container.read(settingsProvider.notifier);
        await settings.updateThemeIndex(entry.key);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(palette.appearance, entry.value);
        expect(palette.textureKind, isNotNull);
        expect(palette.background, isNot(before));
        expect(tester.takeException(), isNull);

        // Light/dark keeps the look, and the cross-fade finishes cleanly.
        await settings.toggleDarkMode(true);
        await tester.pumpAndSettle();
        expect(palette.appearance, entry.value);
        expect(palette.dark, isTrue);
        expect(find.byType(RawImage), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
