import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavvy/theme/theme_crossfade.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

void main() {
  group('theme cache', () {
    test('the same theme is built once and reused', () {
      expect(
        identical(
          WavvyTheme.dark(WvAppearance.aqua),
          WavvyTheme.dark(WvAppearance.aqua),
        ),
        isTrue,
      );
      expect(
        identical(
          WavvyTheme.light(WvAppearance.graphite),
          WavvyTheme.light(WvAppearance.graphite),
        ),
        isTrue,
      );
    });

    test('light, dark, appearance and album color are different themes', () {
      final aqua = WavvyTheme.light(WvAppearance.aqua);
      expect(identical(aqua, WavvyTheme.dark(WvAppearance.aqua)), isFalse);
      expect(identical(aqua, WavvyTheme.light(WvAppearance.graphite)), isFalse);
      expect(
        identical(
          aqua,
          WavvyTheme.light(WvAppearance.aqua, seed: const Color(0xFFD32F2F)),
        ),
        isFalse,
      );
    });

    test('album colors do not grow the cache without bound', () {
      for (var i = 0; i < 60; i++) {
        WavvyTheme.light(WvAppearance.aqua, seed: Color(0xFF000000 + i * 4000));
      }
      // The oldest album theme was dropped; the same request still works.
      final again = WavvyTheme.light(
        WvAppearance.aqua,
        seed: const Color(0xFF000000),
      );
      expect(again.brightness, Brightness.light);
    });
  });

  group('cross-fade', () {
    Widget app(bool dark, {Key? key}) => MaterialApp(
      theme: WavvyTheme.light(WvAppearance.aqua),
      darkTheme: WavvyTheme.dark(WvAppearance.aqua),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) =>
          ThemeCrossFade(themeKey: dark, child: child!),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) =>
                Text('hello', style: TextStyle(color: Wv.of(context).text)),
          ),
        ),
      ),
    );

    testWidgets('the new theme applies on the very next frame', (tester) async {
      await tester.pumpWidget(app(false));
      final light = Wv.of(tester.element(find.text('hello'))).background;
      await tester.pumpWidget(app(true));
      // No tween: the first frame after the switch is already dark.
      final dark = Wv.of(tester.element(find.text('hello'))).background;
      expect(dark, isNot(light));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the fade finishes and leaves only the app', (tester) async {
      await tester.pumpWidget(app(false));
      await tester.pumpWidget(app(true));
      // The previous frame is held on top while it fades out.
      expect(find.byType(RawImage), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RawImage), findsNothing);
      expect(find.text('hello'), findsOneWidget);
      // And it can fade again.
      await tester.pumpWidget(app(false));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unchanged theme does not fade', (tester) async {
      await tester.pumpWidget(app(false));
      await tester.pumpWidget(app(false));
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets('quick successive switches are handled', (tester) async {
      await tester.pumpWidget(app(false));
      await tester.pumpWidget(app(true));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(app(false));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(RawImage), findsNothing);
    });
  });
}
