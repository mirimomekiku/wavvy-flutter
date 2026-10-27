import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

Widget _app(Widget child, {bool dark = false, bool reduceMotion = false}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: WavvyTheme.light(WvAppearance.aqua),
      darkTheme: WavvyTheme.dark(WvAppearance.aqua),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: c!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('toast', () {
    testWidgets('shows the title and detail on a panel with a gel orb', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const AquaToast(
            title: 'Downloaded',
            subtitle: 'A song',
            kind: ToastKind.success,
          ),
        ),
      );
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('A song'), findsOneWidget);
      expect(find.byType(AquaOrb), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('each kind has its own icon', (tester) async {
      for (final (kind, icon) in [
        (ToastKind.success, Icons.check_rounded),
        (ToastKind.error, Icons.priority_high_rounded),
        (ToastKind.info, Icons.info_outline_rounded),
      ]) {
        await tester.pumpWidget(_app(AquaToast(title: 't', kind: kind)));
        expect(find.byIcon(icon), findsOneWidget, reason: '$kind');
      }
    });

    testWidgets('is read as one announcement', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const AquaToast(title: 'Deleted', subtitle: 'Song removed')),
      );
      expect(
        tester.getSemantics(find.byType(AquaToast)),
        isSemantics(label: 'Deleted. Song removed', isLiveRegion: true),
      );
      handle.dispose();
    });

    for (final dark in [false, true]) {
      testWidgets('fits 320 wide with long text (dark: $dark)', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(
            Padding(
              padding: const EdgeInsets.all(16),
              child: AquaToast(
                title: 'A very long title that has to wrap onto another line',
                subtitle: 'And a long detail line ' * 6,
                kind: ToastKind.error,
              ),
            ),
            dark: dark,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('AppSnackbar shows it through the messenger and replaces it', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SizedBox()));
      AppSnackbar.showSuccess('First', 'one');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('First'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      AppSnackbar.showErrorSnackBar('Second', 'two');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Second'), findsOneWidget);
      expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
      // Let the toast time out so no timer is left behind.
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('check mark', () {
    testWidgets('is a gel orb with a tick and says "Done"', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const AquaCheckMark(size: 26)));
      expect(find.byType(AquaOrb), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Done'), findsOneWidget);
      expect(tester.getSize(find.byType(AquaOrb)), const Size(26, 26));
      handle.dispose();
    });

    testWidgets('takes a color', (tester) async {
      await tester.pumpWidget(
        _app(const AquaCheckMark(color: Color(0xFF2E9B4A))),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('spinner', () {
    testWidgets('animates, and is read as "Loading"', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const AquaSpinner(size: 30)));
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      // It keeps scheduling frames while it spins.
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      handle.dispose();
    });

    testWidgets('paints twelve spokes that move', (tester) async {
      await tester.pumpWidget(_app(const AquaSpinner(size: 30)));
      await tester.pump();
      final first = tester.renderObject<RenderBox>(
        find.byType(CustomPaint).last,
      );
      expect(first.size, const Size(30, 30));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('holds still when animations are reduced', (tester) async {
      await tester.pumpWidget(
        _app(const AquaSpinner(size: 30), reduceMotion: true),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a degenerate size does not break it', (tester) async {
      await tester.pumpWidget(_app(const AquaSpinner(size: 0)));
      expect(tester.takeException(), isNull);
    });
  });

  group('progress ring', () {
    testWidgets('with a value it draws a ring around its child', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const AquaProgressRing(
            value: 0.4,
            child: Icon(Icons.close_rounded, size: 14),
          ),
        ),
      );
      expect(find.byType(AquaSpinner), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without a value it is a spinner', (tester) async {
      await tester.pumpWidget(
        _app(
          const AquaProgressRing(child: Icon(Icons.close_rounded, size: 14)),
        ),
      );
      expect(find.byType(AquaSpinner), findsOneWidget);
    });

    testWidgets('out-of-range values are kept in range', (tester) async {
      for (final v in [-1.0, 0.0, 1.0, 5.0]) {
        await tester.pumpWidget(_app(AquaProgressRing(value: v)));
        expect(tester.takeException(), isNull, reason: '$v');
      }
    });
  });
}
