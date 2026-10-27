import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/theme_selector.dart';

Widget _app({bool dark = false, double scale = 1}) => ProviderScope(
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
      body: Padding(padding: EdgeInsets.all(16), child: ThemeSelector()),
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('shows Aqua, the six accents and Graphite, but not System', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    for (final name in [
      'Aqua',
      'Orange',
      'Green',
      'Purple',
      'Pink',
      'Red',
      'Teal',
      'Graphite',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('System'), findsNothing);
    expect(find.text('Color theme'), findsOneWidget);
  });

  testWidgets('tapping a theme selects it and marks it selected', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ThemeSelector)),
    );
    expect(container.read(settingsProvider).currentThemeIndex, 5);

    await tester.tap(find.text('Teal'));
    await tester.pump();
    expect(container.read(settingsProvider).currentThemeIndex, 12);
    expect(
      WavvyTheme.appearanceFor(
        container.read(settingsProvider).currentThemeIndex,
      ),
      WvAppearance.teal,
    );
    expect(
      tester.getSemantics(find.text('Teal')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('Aqua')),
      isNot(isSemantics(isSelected: true)),
    );
    handle.dispose();
  });

  testWidgets('choosing a theme turns album colors off', (tester) async {
    await tester.pumpWidget(_app());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ThemeSelector)),
    );
    await container.read(settingsProvider.notifier).toggleDynamicColors(true);
    await tester.tap(find.text('Orange'));
    await tester.pump();
    expect(container.read(settingsProvider).enableDynamicColors, isFalse);
    expect(container.read(settingsProvider).currentThemeIndex, 7);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('fits 320 wide (dark: $dark, scale $scale)', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(dark: dark, scale: scale));
        expect(tester.takeException(), isNull);
      });
    }
  }

  test(
    'every theme builds in light and dark, with distinct primary colors',
    () {
      for (final dark in [false, true]) {
        final primaries = <Color>{};
        for (final a in WvAppearance.values) {
          final theme = dark ? WavvyTheme.dark(a) : WavvyTheme.light(a);
          expect(theme.brightness, dark ? Brightness.dark : Brightness.light);
          primaries.add(theme.colorScheme.primary);
        }
        expect(primaries.length, WvAppearance.values.length);
      }
    },
  );
}
