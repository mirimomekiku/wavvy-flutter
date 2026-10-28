import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/downloader/flavor.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/search/search_tab.dart';
import 'package:wavvy/screens/settings/settings.screen.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

import 'helpers/fake_engine.dart';

// These expectations follow the build flavor. Run the file twice:
//   flutter test test/flavor_test.dart
//   flutter test --flavor play test/flavor_test.dart

class _Library extends LibraryNotifier {
  @override
  LibraryState build() => const LibraryState();
}

class _Player extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}

class _Settings extends SettingsNotifier {
  @override
  // The user setting is ON; only the flavor decides.
  SettingsState build() => const SettingsState(enableDownloader: true);
}

Widget _app(Widget home) => ProviderScope(
  overrides: [
    libraryProvider.overrideWith(_Library.new),
    playerProvider.overrideWith(_Player.new),
    settingsProvider.overrideWith(_Settings.new),
    ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
    downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
  ],
  child: MaterialApp(theme: WavvyTheme.light(WvAppearance.aqua), home: home),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(411 * 2, 900 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  test('the downloader flag matches the build', () {
    const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
    expect(kDownloaderAvailable, flavor != 'play');
  });

  test('the visualizer flag matches the build', () {
    const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
    expect(kVisualizerAvailable, flavor != 'play');
  });

  test(
    'the setting alone cannot add the Visualizer page in the Play build',
    () {
      final on = playerSheetPages(const SettingsState(enableVisualizer: true));
      expect(on.contains(4), kVisualizerAvailable);
      expect(
        playerSheetPages(const SettingsState(enableVisualizer: false)),
        isNot(contains(4)),
      );
      // The other pages are the same in both builds.
      expect(on.take(4), [0, 1, 2, 3]);
    },
  );

  test('the setting alone cannot turn the downloader on in the Play build', () {
    expect(
      const SettingsState(enableDownloader: true).downloaderOn,
      kDownloaderAvailable,
    );
    expect(const SettingsState(enableDownloader: false).downloaderOn, isFalse);
  });

  testWidgets('Search shows the downloader only in the full build', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(_app(const Scaffold(body: SearchTab())));
    await tester.pump();
    expect(
      find.byTooltip('Online'),
      kDownloaderAvailable ? findsOneWidget : findsNothing,
    );
    expect(
      find.byTooltip('Downloads'),
      kDownloaderAvailable ? findsOneWidget : findsNothing,
    );
    expect(find.text('Songs, albums, artists'), findsOneWidget);
  });

  testWidgets('Settings shows the downloader only in the full build', (
    tester,
  ) async {
    // Tall enough that the whole list is built.
    tester.view.physicalSize = const Size(411 * 2, 4000 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const SettingsScreen()));
    await tester.pump();
    final present = kDownloaderAvailable ? findsOneWidget : findsNothing;
    expect(find.text('Downloads'), present);
    // The group header and the engine row.
    expect(
      find.text('Downloader'),
      kDownloaderAvailable ? findsNWidgets(2) : findsNothing,
    );
    expect(find.text('Wi-Fi only'), present);
    // The Visualizer toggle is a full-build feature too.
    expect(
      find.text('Visualizer'),
      kVisualizerAvailable ? findsOneWidget : findsNothing,
    );
    // Everything else is there in both.
    expect(find.text('Lyrics'), findsOneWidget);
  });
}
