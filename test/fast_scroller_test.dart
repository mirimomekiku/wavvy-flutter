import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/fast_scroller.dart';

final _thumb = find.byKey(const Key('fast_scroller_thumb'));
final _bubble = find.byKey(const Key('fast_scroller_bubble'));

/// 100 items spread evenly over A-Z (4 each, the last letters get 3).
String _label(int i) => String.fromCharCode(65 + i * 26 ~/ 100);

void main() {
  group('letters', () {
    test('letterFor maps the first character', () {
      expect(letterFor('Abba'), 'A');
      expect(letterFor('zebra'), 'Z');
      expect(letterFor('  mid'), 'M');
      expect(letterFor('7 Rings'), '#');
      expect(letterFor('(Intro)'), '#');
      expect(letterFor(''), '#');
      expect(letterFor('   '), '#');
      expect(letterFor('<unknown>'), '#');
      expect(letterFor('Édith Piaf'), 'E');
      expect(letterFor('étude'), 'E');
      expect(letterFor('ñandú'), 'N');
      expect(letterFor('日本'), '#');
      expect(letterFor('ß'), '#');
    });

    test('a fraction points at fraction * (count - 1)', () {
      expect(indexForFraction(0, 100), 0);
      expect(indexForFraction(1, 100), 99);
      expect(indexForFraction(0.5, 101), 50);
      expect(indexForFraction(-1, 100), 0);
      expect(indexForFraction(2, 100), 99);
      expect(indexForFraction(0.7, 1), 0);
      expect(indexForFraction(0.7, 0), 0);
    });

    test('letterForFraction uses the label of that item', () {
      expect(letterForFraction(0, 100, _label), 'A');
      expect(letterForFraction(1, 100, _label), 'Z');
      expect(letterForFraction(0.5, 100, _label), 'N');
      expect(letterForFraction(0.5, 100, null), isNull);
      expect(letterForFraction(0.5, 0, _label), isNull);
    });

    test('lettersAscending tells alphabetical lists from the rest', () {
      expect(lettersAscending(100, _label), isTrue);
      expect(lettersAscending(100, (i) => _label(99 - i)), isFalse);
      expect(lettersAscending(3, (i) => ['9', 'A', 'b'][i]), isTrue);
      expect(lettersAscending(0, _label), isTrue);
    });
  });

  group('FastScroller', () {
    final haptics = <MethodCall>[];

    setUp(() {
      haptics.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    var childBuilds = 0;

    Widget app(
      ScrollController controller, {
      int count = 100,
      bool letters = true,
      double scale = 1,
      bool dark = false,
    }) {
      childBuilds = 0;
      return MaterialApp(
        theme: dark
            ? WavvyTheme.dark(WvAppearance.green)
            : WavvyTheme.light(WvAppearance.green),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: FastScroller(
            controller: controller,
            itemCount: count,
            labelAt: letters ? _label : null,
            child: Builder(
              builder: (context) {
                childBuilds++;
                return CustomScrollView(
                  controller: controller,
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => SizedBox(
                          height: 56,
                          child: Text('Row $i ${_label(i)}'),
                        ),
                        childCount: count,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    }

    AnimatedOpacity fade(WidgetTester tester) => tester.widget(
      find.ancestor(of: _thumb, matching: find.byType(AnimatedOpacity)),
    );

    bool ignoring(WidgetTester tester) => tester
        .widget<IgnorePointer>(
          find.ancestor(of: _thumb, matching: find.byType(IgnorePointer)).first,
        )
        .ignoring;

    testWidgets('appears on scroll and fades about 1.2 s later', (
      tester,
    ) async {
      final c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      expect(fade(tester).opacity, 0);
      expect(ignoring(tester), isTrue);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();
      expect(fade(tester).opacity, 1);
      expect(ignoring(tester), isFalse);

      await tester.pump(const Duration(milliseconds: 1000));
      expect(fade(tester).opacity, 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(fade(tester).opacity, 0);
      expect(ignoring(tester), isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('is excluded from semantics', (tester) async {
      final c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();
      expect(
        find.ancestor(of: _thumb, matching: find.byType(ExcludeSemantics)),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('dragging the thumb scrubs the list and shows the letter', (
      tester,
    ) async {
      final c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -50));
      await tester.pump();
      expect(_bubble, findsNothing);
      final before = childBuilds;

      final gesture = await tester.startGesture(tester.getCenter(_thumb));
      await tester.pump();
      expect(_bubble, findsOneWidget);
      await gesture.moveBy(const Offset(0, 250));
      await tester.pump();
      final max = c.position.maxScrollExtent;
      // The thumb travels viewport height minus its own height (600 - 56).
      expect(c.offset / max, closeTo(250 / 544, 0.05));
      final f = c.offset / max;
      final letter = _label((f * 99).round());
      expect(
        find.descendant(of: _bubble, matching: find.text(letter)),
        findsOneWidget,
      );
      expect(haptics, isNotEmpty);

      await gesture.moveBy(const Offset(0, 1000));
      await tester.pump();
      expect(c.offset, closeTo(max, 1));
      expect(
        find.descendant(of: _bubble, matching: find.text('Z')),
        findsOneWidget,
      );

      await gesture.up();
      await tester.pump();
      expect(_bubble, findsNothing);
      // The scroll view's own builder never ran again: only the overlay did.
      expect(childBuilds, before);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(fade(tester).opacity, 0);
    });

    testWidgets('a haptic tick only when the letter changes', (tester) async {
      final c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -50));
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(_thumb));
      await tester.pump();
      final first = haptics.length;
      // A tiny move stays on the same letter.
      await gesture.moveBy(const Offset(0, 1));
      await tester.pump();
      expect(haptics.length, first);
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();
      expect(haptics.length, greaterThan(first));
      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a plain thumb without letters has no bubble', (tester) async {
      final c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c, letters: false));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -50));
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(_thumb));
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();
      expect(c.offset, greaterThan(500));
      expect(_bubble, findsNothing);
      expect(haptics, isEmpty);
      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('hidden for short lists', (tester) async {
      final c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c, count: 29));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();
      expect(_thumb, findsNothing);
    });

    testWidgets('lets taps through outside the strip while hidden', (
      tester,
    ) async {
      final c = ScrollController();
      addTearDown(c.dispose);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: WavvyTheme.light(WvAppearance.green),
          home: Scaffold(
            body: FastScroller(
              controller: c,
              itemCount: 100,
              child: ListView.builder(
                controller: c,
                itemCount: 100,
                itemBuilder: (context, i) => InkWell(
                  onTap: () => taps++,
                  child: SizedBox(height: 56, child: Text('Row $i')),
                ),
              ),
            ),
          ),
        ),
      );
      // The right edge, where a row's action button would be.
      await tester.tapAt(const Offset(790, 20));
      expect(taps, 1);
    });

    for (final scale in const [1.0, 1.5]) {
      for (final dark in const [false, true]) {
        testWidgets('renders at text x$scale ${dark ? 'dark' : 'light'}', (
          tester,
        ) async {
          final c = ScrollController();
          addTearDown(c.dispose);
          await tester.pumpWidget(app(c, scale: scale, dark: dark));
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -50),
          );
          await tester.pump();
          final gesture = await tester.startGesture(tester.getCenter(_thumb));
          await gesture.moveBy(const Offset(0, 100));
          await tester.pump();
          expect(_bubble, findsOneWidget);
          expect(tester.takeException(), isNull);
          await gesture.up();
          await tester.pump(const Duration(seconds: 2));
        });
      }
    }
  });
}
