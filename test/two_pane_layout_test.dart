import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/models/lyric.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/player_sheets/layouts/two_pane_layout.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/queue_selection_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/settings/player_layout_setting.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

import 'helpers/fake_engine.dart';
import 'helpers/fake_player.dart';

class _Library extends LibraryNotifier {
  @override
  LibraryState build() => const LibraryState();
}

class _Playlists extends PlaylistsNotifier {
  @override
  PlaylistsState build() => const PlaylistsState();
}

class _Position extends PositionNotifier {
  @override
  Duration build() => const Duration(seconds: 50);
}

class _Duration extends DurationNotifier {
  @override
  Duration build() => const Duration(minutes: 3);
}

class _FavStore implements FavoritesStore {
  @override
  Future<Map<int, int>> load() async => {};
  @override
  Future<void> add(int id, int at) async {}
  @override
  Future<void> remove(int id) async {}
}

class _Rates implements RateStore {
  @override
  Future<Map<String, PlaybackRate>> load() async => {};
  @override
  Future<void> save(Map<String, PlaybackRate> r) async {}
}

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
}

class _Lyrics extends LyricsNotifier {
  @override
  LyricsState build() => LyricsState(
    currentIndex: 1,
    lyrics: [
      Lyric(Duration.zero, 'A little room to breathe.'),
      Lyric(const Duration(seconds: 40), 'Your music, wherever you go.'),
      Lyric(const Duration(seconds: 60), 'Another day in motion.'),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final songs = [for (var i = 1; i <= 5; i++) testSong(i, albumId: 100)];

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  /// Pumps [child] (default: the layout between two bars the height of the
  /// sheet's header and toolbar) with row 2 playing.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required Size size,
    double scale = 1,
    bool dark = false,
    WvAppearance appearance = WvAppearance.aqua,
    SettingsState settings = const SettingsState(),
    bool lyricsOn = true,
    Widget? child,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final player = MemoryPlayer();
    addTearDown(player.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(player),
          libraryProvider.overrideWith(_Library.new),
          playlistsProvider.overrideWith(_Playlists.new),
          positionProvider.overrideWith(_Position.new),
          durationProvider.overrideWith(_Duration.new),
          settingsProvider.overrideWith(() => _Settings(settings)),
          lyricsProvider.overrideWith(_Lyrics.new),
          favoritesStoreProvider.overrideWithValue(_FavStore()),
          rateStoreProvider.overrideWithValue(_Rates()),
          ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
          downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: WavvyTheme.light(appearance),
          darkTheme: WavvyTheme.dark(appearance),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: c!,
          ),
          home: Scaffold(
            body:
                child ??
                Column(
                  children: [
                    const SizedBox(height: 56),
                    Expanded(
                      child: TwoPaneLayout(
                        data: PlayerLayoutData(
                          song: songs[1],
                          onLyrics: lyricsOn ? () {} : null,
                          onArtist: () {},
                        ),
                      ),
                    ),
                    const SizedBox(height: 56),
                  ],
                ),
          ),
        ),
      ),
    );
    final c = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    await c
        .read(playerProvider.notifier)
        .playSong(songs[1], contextList: songs);
    player.emit(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return c;
  }

  group('no overflow', () {
    final wide = {
      '800x360': const Size(800, 360),
      '915x412': const Size(915, 412),
      '740x360': const Size(740, 360),
      '1280x800': const Size(1280, 800),
      '840x1000 portrait tablet': const Size(840, 1000),
    };
    for (final entry in wide.entries) {
      for (final scale in [1.0, 1.5]) {
        for (final dark in [false, true]) {
          testWidgets('${entry.key} x$scale dark=$dark', (tester) async {
            await pump(tester, size: entry.value, scale: scale, dark: dark);
            expect(tester.takeException(), isNull);
            expect(find.text('Up next'), findsOneWidget);
            expect(find.byTooltip('Pause'), findsOneWidget);
            // The right pane's lyrics too.
            await tester.tap(find.text('Lyrics'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('stacked 360x640 x$scale dark=$dark', (tester) async {
          await pump(
            tester,
            size: const Size(360, 640),
            scale: scale,
            dark: dark,
          );
          expect(tester.takeException(), isNull);
          expect(find.byTooltip('Pause'), findsOneWidget);
          expect(find.text('Up next'), findsOneWidget);
          await tester.tap(find.text('Lyrics'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
        });
      }
    }
    for (final appearance in [
      WvAppearance.graphite,
      WvAppearance.pinstripe,
      WvAppearance.brushedMetal,
    ]) {
      for (final size in [const Size(800, 360), const Size(360, 640)]) {
        for (final dark in [false, true]) {
          testWidgets('${appearance.name} $size dark=$dark', (tester) async {
            await pump(
              tester,
              size: size,
              scale: 1.5,
              dark: dark,
              appearance: appearance,
            );
            expect(tester.takeException(), isNull);
            expect(find.byTooltip('Pause'), findsOneWidget);
          });
        }
      }
    }
  });

  group('panes', () {
    testWidgets('the tabs switch panes and the choice is kept', (tester) async {
      final c = await pump(tester, size: const Size(915, 412));
      expect(find.text('Up next'), findsOneWidget);
      expect(find.byTooltip('Full screen'), findsNothing);

      await tester.tap(find.text('Lyrics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Up next'), findsNothing);
      expect(find.text('Your music, wherever you go.'), findsOneWidget);
      expect(find.byTooltip('Full screen'), findsOneWidget);
      expect(find.byTooltip('Share Card'), findsOneWidget);
      expect(c.read(twoPaneTabProvider), TwoPaneTab.lyrics);

      await tester.tap(find.text('Queue'));
      await tester.pump();
      expect(find.text('Up next'), findsOneWidget);
      expect(find.byTooltip('Full screen'), findsNothing);
    });

    testWidgets('the lyrics button shows lyrics instead of leaving', (
      tester,
    ) async {
      await pump(tester, size: const Size(915, 412));
      await tester.tap(find.byTooltip('View lyrics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Up next'), findsNothing);
      expect(find.text('Your music, wherever you go.'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
    });

    testWidgets('without lyrics there is only the queue', (tester) async {
      await pump(tester, size: const Size(915, 412), lyricsOn: false);
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('Lyrics'), findsNothing);
      expect(find.byTooltip('View lyrics'), findsNothing);
    });

    testWidgets('a tapped queue row jumps and selecting works', (tester) async {
      final c = await pump(tester, size: const Size(1280, 800));
      final player = c.read(audioPlayerProvider) as MemoryPlayer;
      await tester.tap(find.text('Track 4'));
      await tester.pump();
      expect(player.seeks, hasLength(1));

      await tester.longPress(find.text('Track 3'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(AquaCheckbox), findsNWidgets(5));
      await tester.tap(find.text('Track 5'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      expect(player.seeks, hasLength(1));
      expect(c.read(queueSelectionProvider).sorted, [2, 4]);
      // Leaving the Queue pane ends selecting.
      await tester.tap(find.text('Lyrics'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(c.read(queueSelectionProvider).active, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rotating while selecting does not crash', (tester) async {
      final c = await pump(tester, size: const Size(1280, 800));
      await tester.longPress(find.text('Track 3'));
      await tester.pump();
      expect(c.read(queueSelectionProvider).active, isTrue);
      tester.view.physicalSize = const Size(800, 1280);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Pause'), findsOneWidget);
    });
  });

  group('the sheet', () {
    Future<ProviderContainer> sheet(
      WidgetTester tester,
      Size size, {
      SettingsState settings = const SettingsState(),
    }) => pump(
      tester,
      size: size,
      settings: settings,
      child: const FullPlayerSheet(),
    );

    testWidgets('hides Queue and Lyrics from the switcher on a wide screen', (
      tester,
    ) async {
      await sheet(tester, const Size(915, 412));
      expect(find.byTooltip('Player'), findsOneWidget);
      expect(find.byTooltip('Queue'), findsNothing);
      expect(find.byTooltip('Lyrics'), findsNothing);
      expect(find.byTooltip('About'), findsOneWidget);
      expect(find.text('Up next'), findsOneWidget);
    });

    testWidgets('keeps them on a narrow screen', (tester) async {
      await sheet(tester, const Size(411, 900));
      expect(find.byTooltip('Queue'), findsOneWidget);
      expect(find.byTooltip('Lyrics'), findsOneWidget);
    });

    testWidgets('keeps them on a narrow screen with the layout chosen', (
      tester,
    ) async {
      await sheet(
        tester,
        const Size(411, 900),
        settings: SettingsState(playerLayout: PlayerLayout.twoPane.index),
      );
      expect(find.byTooltip('Queue'), findsOneWidget);
      expect(find.byTooltip('Lyrics'), findsOneWidget);
      // The stacked version is shown on the Player page.
      expect(find.text('Up next'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adaptive off keeps the chosen layout on a wide screen', (
      tester,
    ) async {
      await sheet(
        tester,
        const Size(915, 412),
        settings: const SettingsState(playerLayoutAdaptive: false),
      );
      expect(find.byTooltip('Queue'), findsOneWidget);
      expect(find.byTooltip('Lyrics'), findsOneWidget);
      expect(find.byType(TwoPaneLayout), findsNothing);
    });

    testWidgets('adaptive off still honours a hand-picked two panes', (
      tester,
    ) async {
      await sheet(
        tester,
        const Size(915, 412),
        settings: SettingsState(
          playerLayout: PlayerLayout.twoPane.index,
          playerLayoutAdaptive: false,
        ),
      );
      expect(find.byType(TwoPaneLayout), findsOneWidget);
      expect(find.byTooltip('Queue'), findsNothing);
    });

    testWidgets('rotating on the Queue page lands on the player', (
      tester,
    ) async {
      final c = await sheet(tester, const Size(411, 900));
      await tester.tap(find.byTooltip('Queue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      tester.view.physicalSize = const Size(915, 412);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      expect(find.byType(TwoPaneLayout), findsOneWidget);
      expect(c.read(twoPaneTabProvider), TwoPaneTab.queue);
      expect(find.byTooltip('Pause'), findsOneWidget);
    });

    testWidgets('going to About and back keeps the pane', (tester) async {
      await sheet(tester, const Size(915, 412));
      await tester.tap(find.text('Lyrics'));
      await tester.pump();
      await tester.tap(find.byTooltip('About'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byTooltip('Player'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Your music, wherever you go.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('resolving', () {
    const wide = Size(915, 412);
    const narrow = Size(411, 900);
    test('adaptive on switches every layout on a wide screen', () {
      for (final layout in PlayerLayout.values) {
        final s = SettingsState(playerLayout: layout.index);
        expect(resolvePlayerLayout(s, wide), PlayerLayout.twoPane);
        expect(resolvePlayerLayout(s, narrow), layout);
      }
      expect(kTwoPaneReady, isTrue);
    });
    test('adaptive off keeps the chosen layout', () {
      for (final layout in PlayerLayout.values) {
        final s = SettingsState(
          playerLayout: layout.index,
          playerLayoutAdaptive: false,
        );
        expect(resolvePlayerLayout(s, wide), layout);
        expect(resolvePlayerLayout(s, narrow), layout);
      }
    });
    test('a portrait tablet needs 840 dp', () {
      const s = SettingsState();
      expect(resolvePlayerLayout(s, const Size(800, 1280)), PlayerLayout.vinyl);
      expect(
        resolvePlayerLayout(s, const Size(840, 1280)),
        PlayerLayout.twoPane,
      );
    });
  });

  group('preview', () {
    testWidgets('paints and is in the picker', (tester) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsProvider.overrideWith(
                () => _Settings(const SettingsState()),
              ),
            ],
            child: MaterialApp(
              theme: WavvyTheme.light(WvAppearance.aqua),
              darkTheme: WavvyTheme.dark(WvAppearance.aqua),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: const Scaffold(body: PlayerLayoutPicker()),
            ),
          ),
        );
        await tester.pump();
        expect(kPlayerLayoutPreviews[PlayerLayout.twoPane], isNotNull);
        expect(find.byType(TwoPaneLayoutPreview), findsOneWidget);
        expect(find.text('Two panes'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('paints at tiny sizes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WavvyTheme.light(WvAppearance.aqua),
          home: const Center(
            child: SizedBox(
              width: 20,
              height: 12,
              child: TwoPaneLayoutPreview(),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
