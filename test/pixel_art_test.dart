import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

Widget _app(Widget child, {bool dark = false}) {
  final theme = dark
      ? WavvyTheme.dark(WvAppearance.materialYou)
      : WavvyTheme.light(WvAppearance.materialYou);
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: Center(child: child)),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 740 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('sprites', () {
    final all = <String, PixelSprite>{
      'note': PixelSprites.note,
      'vinyl': PixelSprites.vinyl,
      'headphones': PixelSprites.headphones,
      'cassette': PixelSprites.cassette,
      'speaker': PixelSprites.speaker,
      'heart': PixelSprites.heart,
      'star': PixelSprites.star,
      'search': PixelSprites.search,
      'download': PixelSprites.download,
      'home': PixelSprites.home,
      'library': PixelSprites.library,
      'mascot': PixelSprites.mascot,
      'mascotHappy': PixelSprites.mascotHappy,
      'mascotSleepy': PixelSprites.mascotSleepy,
    };

    all.forEach((name, s) {
      test('$name is a non-empty rectangular grid', () {
        expect(s.height, greaterThanOrEqualTo(10));
        expect(s.width, greaterThanOrEqualTo(12));
        expect(s.height, lessThanOrEqualTo(16));
        expect(s.width, lessThanOrEqualTo(16));
        for (final r in s.rows) {
          expect(r.length, s.width, reason: '$name row "$r"');
        }
        expect(
          s.rows.any((r) => r.replaceAll(RegExp(r'[ .]'), '').isNotEmpty),
          isTrue,
        );
      });
    });

    test('mascot variants share dimensions and differ', () {
      for (final m in [PixelSprites.mascotHappy, PixelSprites.mascotSleepy]) {
        expect(m.width, PixelSprites.mascot.width);
        expect(m.height, PixelSprites.mascot.height);
        expect(m.rows, isNot(PixelSprites.mascot.rows));
      }
    });
  });

  group('cover', () {
    test('pattern is deterministic, mirrored, non-empty', () {
      for (var seed = -5; seed < 200; seed++) {
        final a = pixelCoverPattern(seed);
        expect(a, pixelCoverPattern(seed));
        expect(a.length, 8);
        var count = 0;
        for (final row in a) {
          expect(row.length, 8);
          for (var x = 0; x < 4; x++) {
            expect(row[x], row[7 - x]);
          }
          count += row.where((b) => b).length;
        }
        expect(count, greaterThan(0));
      }
    });

    test('different seeds differ in pattern and colors', () {
      final patterns = {
        for (var i = 0; i < 50; i++) pixelCoverPattern(i).toString(),
      };
      expect(patterns.length, greaterThan(40));
      final colors = {
        for (var i = 0; i < 50; i++) pixelCoverColors(i).$1.toARGB32(),
      };
      expect(colors.length, greaterThan(25));
      expect(pixelCoverColors(7), pixelCoverColors(7));
      expect(
        pixelCoverColors(7, dark: true),
        isNot(pixelCoverColors(7, dark: false)),
      );
    });
  });

  group('PixelCornersBorder', () {
    test('path has stepped corners', () {
      const b = PixelCornersBorder(step: 4, steps: 2);
      const rect = Rect.fromLTWH(0, 0, 100, 60);
      final path = b.getOuterPath(rect);
      expect(path.contains(const Offset(50, 30)), isTrue);
      expect(path.contains(const Offset(0.5, 0.5)), isFalse);
      expect(path.contains(const Offset(99.5, 0.5)), isFalse);
      expect(path.contains(const Offset(0.5, 59.5)), isFalse);
      expect(path.contains(const Offset(99.5, 59.5)), isFalse);
      expect(path.contains(const Offset(50, 0.5)), isTrue);
      expect(path.contains(const Offset(0.5, 30)), isTrue);
      expect(b.getInnerPath(rect).contains(const Offset(50, 30)), isTrue);
    });

    test('scale and degenerate sizes', () {
      const b = PixelCornersBorder(
        step: 4,
        steps: 2,
        side: BorderSide(width: 2),
      );
      final s = b.scale(2) as PixelCornersBorder;
      expect(s.step, 8);
      expect(s.side.width, 4);
      expect(b.dimensions, const EdgeInsets.all(2));
      expect(() => b.getOuterPath(Rect.zero), returnsNormally);
      expect(
        () => b.getOuterPath(const Rect.fromLTWH(0, 0, 3, 3)),
        returnsNormally,
      );
    });

    testWidgets('works in ShapeDecoration and Material', (tester) async {
      await tester.pumpWidget(
        _app(
          const Material(
            shape: PixelCornersBorder(
              side: BorderSide(width: 2, color: Colors.red),
            ),
            child: SizedBox(width: 80, height: 40),
          ),
        ),
      );
      await tester.pumpWidget(
        _app(
          Container(
            width: 80,
            height: 40,
            decoration: const ShapeDecoration(
              color: Colors.blue,
              shape: PixelCornersBorder(),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PixelProgress', () {
    for (final v in [-1.0, 0.0, 0.5, 1.0, 2.0, double.nan, double.infinity]) {
      testWidgets('renders value $v', (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(PixelProgress(value: v)));
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('odd block counts and heights', (tester) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 30,
            child: PixelProgress(value: .5, blocks: 0, height: -3),
          ),
        ),
      );
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 20,
            child: PixelProgress(value: .5, blocks: 100),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('animated widgets', () {
    testWidgets('equalizer and loader animate and dispose', (tester) async {
      await tester.pumpWidget(
        _app(const Row(children: [PixelEqualizer(), PixelLoader()])),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('equalizer animate:false is static and toggles', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const PixelEqualizer(animate: false)));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(_app(const PixelEqualizer(animate: true)));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(_app(const PixelEqualizer(animate: false)));
      // Settles only if the equalizer's controller really stopped (the theme
      // cross-fade between the pumped apps finishes on its own).
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('zero and NaN sizes are safe', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              PixelEqualizer(size: 0),
              PixelLoader(size: double.nan),
              PixelSpriteView(sprite: PixelSprites.note, size: -4),
              WvPixelCover(seed: 1, size: 0),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });
  });

  group('WvWavySlider', () {
    Widget slider(
      List<double> changes,
      List<double> ends, {
      double value = 10,
      double max = 100,
      bool animate = false,
    }) {
      return _app(
        SizedBox(
          width: 300,
          child: WvWavySlider(
            value: value,
            max: max,
            animate: animate,
            onChanged: changes.add,
            onChangeEnd: ends.add,
          ),
        ),
      );
    }

    testWidgets('drag produces monotonic in-range values', (tester) async {
      final changes = <double>[], ends = <double>[];
      await tester.pumpWidget(slider(changes, ends));
      final rect = tester.getRect(find.byType(WvWavySlider));
      await tester.dragFrom(
        rect.centerLeft + const Offset(2, 0),
        const Offset(400, 0),
      );
      await tester.pump();
      expect(changes, isNotEmpty);
      for (var i = 0; i < changes.length; i++) {
        expect(changes[i], inInclusiveRange(0, 100));
        if (i > 0) expect(changes[i], greaterThanOrEqualTo(changes[i - 1]));
      }
      expect(changes.last, 100);
      expect(ends, hasLength(1));
    });

    testWidgets('tap sets value', (tester) async {
      final changes = <double>[], ends = <double>[];
      await tester.pumpWidget(slider(changes, ends));
      await tester.tap(find.byType(WvWavySlider));
      await tester.pump();
      expect(changes.single, closeTo(50, 1));
      expect(ends.single, closeTo(50, 1));
    });

    testWidgets('semantics increase/decrease', (tester) async {
      final handle = tester.ensureSemantics();
      final changes = <double>[], ends = <double>[];
      await tester.pumpWidget(slider(changes, ends, value: 10));
      tester.semantics.increase(
        find.semantics.byAction(SemanticsAction.increase),
      );
      tester.semantics.decrease(
        find.semantics.byAction(SemanticsAction.decrease),
      );
      expect(changes, [15, 5]);

      changes.clear();
      await tester.pumpWidget(slider(changes, ends, value: 99));
      tester.semantics.increase(
        find.semantics.byAction(SemanticsAction.increase),
      );
      expect(changes, [100]);

      changes.clear();
      await tester.pumpWidget(slider(changes, ends, value: 1));
      tester.semantics.decrease(
        find.semantics.byAction(SemanticsAction.decrease),
      );
      expect(changes, [0]);
      handle.dispose();
    });

    testWidgets('max == 0 and out-of-range values are safe', (tester) async {
      final changes = <double>[], ends = <double>[];
      await tester.pumpWidget(slider(changes, ends, value: 5, max: 0));
      await tester.tap(find.byType(WvWavySlider));
      await tester.drag(find.byType(WvWavySlider), const Offset(100, 0));
      await tester.pump();
      expect(changes, isEmpty);
      for (final v in [-5.0, 500.0, double.nan]) {
        await tester.pumpWidget(
          slider(changes, ends, value: v, max: 100, animate: true),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  for (final dark in [false, true]) {
    testWidgets('everything renders at 360x740 (dark: $dark)', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _app(
          dark: dark,
          SingleChildScrollView(
            child: Column(
              children: [
                const WvKicker('Recently added'),
                Wrap(
                  children: [
                    for (final s in [
                      PixelSprites.note,
                      PixelSprites.vinyl,
                      PixelSprites.headphones,
                      PixelSprites.cassette,
                      PixelSprites.speaker,
                      PixelSprites.heart,
                      PixelSprites.star,
                      PixelSprites.search,
                      PixelSprites.download,
                      PixelSprites.home,
                      PixelSprites.library,
                    ])
                      PixelSpriteView(sprite: s, size: 36),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PixelSpriteView(
                      sprite: PixelSprites.mascot,
                      size: 64,
                      themed: true,
                    ),
                    PixelSpriteView(
                      sprite: PixelSprites.mascotHappy,
                      size: 48,
                      themed: true,
                    ),
                    PixelSpriteView(
                      sprite: PixelSprites.mascotSleepy,
                      size: 33,
                      themed: true,
                    ),
                  ],
                ),
                const SizedBox(
                  width: 96,
                  height: 96,
                  child: WvPixelCover(seed: 42, radius: 12),
                ),
                const WvPixelCover(seed: 9, size: 40),
                const Row(children: [PixelEqualizer(), PixelLoader()]),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: PixelProgress(value: .4),
                ),
                WvWavySlider(value: 30, max: 100, onChanged: (_) {}),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });
  }
}
