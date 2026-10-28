import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/settings/player_layout_setting.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('the registry', () {
    test('every layout has a builder and a picker thumbnail', () {
      for (final layout in PlayerLayout.values) {
        expect(kPlayerLayoutBuilders[layout], isNotNull, reason: layout.name);
        expect(kPlayerLayoutPreviews[layout], isNotNull, reason: layout.name);
        expect(layout.label, isNotEmpty);
        expect(layout.description, isNotEmpty);
      }
    });

    test('the layouts keep their saved indices', () {
      // Saved by index: new layouts go at the end, these never move.
      expect(PlayerLayout.values.map((l) => l.name).toList(), [
        'vinyl',
        'itunes',
        'coverFlow',
        'hifi',
        'poster',
        'lyrics',
        'twoPane',
        'cassette',
        'cd',
      ]);
    });
  });

  group('which layout shows', () {
    const phone = Size(411, 915);
    const landscapePhone = Size(915, 411);
    const tablet = Size(1280, 800);
    const portraitTablet = Size(800, 1280);

    test('the chosen one on a phone in portrait', () {
      for (final layout in PlayerLayout.values) {
        expect(
          resolvePlayerLayout(SettingsState(playerLayout: layout.index), phone),
          layout,
        );
      }
    });

    test('two panes on wide screens when the switch is on', () {
      const settings = SettingsState(playerLayout: 2); // Cover Flow chosen
      expect(
        resolvePlayerLayout(settings, landscapePhone),
        PlayerLayout.twoPane,
      );
      expect(resolvePlayerLayout(settings, tablet), PlayerLayout.twoPane);
    });

    test('the chosen one on wide screens when the switch is off', () {
      const settings = SettingsState(
        playerLayout: 4, // Poster
        playerLayoutAdaptive: false,
      );
      expect(
        resolvePlayerLayout(settings, landscapePhone),
        PlayerLayout.poster,
      );
      expect(resolvePlayerLayout(settings, tablet), PlayerLayout.poster);
    });

    test('a portrait tablet needs 840 wide to count as wide', () {
      const settings = SettingsState(playerLayout: 1);
      expect(
        resolvePlayerLayout(settings, portraitTablet),
        PlayerLayout.itunes,
      );
      expect(
        resolvePlayerLayout(settings, const Size(840, 1280)),
        PlayerLayout.twoPane,
      );
    });

    test('a nonsense saved index falls back to a real layout', () {
      expect(
        resolvePlayerLayout(const SettingsState(playerLayout: 99), phone),
        PlayerLayout.values.last,
      );
      expect(
        resolvePlayerLayout(const SettingsState(playerLayout: -3), phone),
        PlayerLayout.vinyl,
      );
    });
  });

  group('the picker', () {
    Widget app(ProviderContainer container, {bool dark = false}) =>
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: dark
                ? WavvyTheme.dark(WvAppearance.aqua)
                : WavvyTheme.light(WvAppearance.aqua),
            home: const Scaffold(
              body: SingleChildScrollView(child: PlayerLayoutPicker()),
            ),
          ),
        );

    testWidgets('lists every layout with a thumbnail, light and dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(app(container, dark: dark));
        for (final layout in PlayerLayout.values) {
          expect(find.text(layout.label), findsOneWidget, reason: layout.name);
        }
        expect(
          find.byType(PlayerLayoutTile),
          findsNWidgets(PlayerLayout.values.length),
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('choosing a layout saves it', (tester) async {
      tester.view.physicalSize = const Size(411, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container));
      await tester.tap(find.text(PlayerLayout.hifi.label));
      await tester.pump();
      expect(container.read(settingsProvider).playerLayout, 3);
      await tester.tap(find.text(PlayerLayout.vinyl.label));
      await tester.pump();
      expect(container.read(settingsProvider).playerLayout, 0);
    });

    testWidgets('the wide-screen switch can be turned off and on', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container));
      expect(container.read(settingsProvider).playerLayoutAdaptive, isTrue);
      await tester.tap(find.text('Two panes on wide screens'));
      await tester.pump();
      expect(container.read(settingsProvider).playerLayoutAdaptive, isFalse);
      await tester.tap(find.text('Two panes on wide screens'));
      await tester.pump();
      expect(container.read(settingsProvider).playerLayoutAdaptive, isTrue);
    });

    testWidgets('the tile says which layout is selected', (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(411, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container));
      final selected = tester
          .widgetList<PlayerLayoutTile>(find.byType(PlayerLayoutTile))
          .where((t) => t.selected)
          .map((t) => t.layout)
          .toList();
      expect(selected, [PlayerLayout.vinyl]); // the default
      handle.dispose();
    });
  });
}
