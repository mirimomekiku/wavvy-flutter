import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/models/lyric.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/player_sheets/lyrics_fullscreen.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

import 'helpers/fake_engine.dart';
import 'helpers/fake_player.dart';

class _Lyrics extends LyricsNotifier {
  _Lyrics(this.initial);
  final LyricsState initial;
  final fetches = <String>[];

  @override
  LyricsState build() => initial;
  void put(LyricsState s) => state = s;

  @override
  Future<void> fetchLyrics({
    required String trackName,
    required String artistName,
    required String albumName,
    required int duration,
  }) async => fetches.add(trackName);
}

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
}

class _Library extends LibraryNotifier {
  _Library(this.songs);
  final List<SongModel> songs;
  @override
  LibraryState build() => LibraryState(songs: songs, filteredSongs: songs);
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

List<Lyric> _synced() => [
  Lyric(const Duration(seconds: 1), 'first line'),
  Lyric(const Duration(seconds: 5), 'second line'),
  Lyric(const Duration(seconds: 9), 'third line'),
  Lyric(const Duration(seconds: 13), 'fourth line'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final songs = [for (var i = 1; i <= 3; i++) testSong(i, albumId: 100)];
  late MemoryPlayer player;
  late _Lyrics lyrics;
  late List<bool> awake;
  late List<String> uiModes;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
    uiModes = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            uiModes.add(call.arguments as String);
          }
          return null;
        });
    awake = [];
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Pumps an app with a button that opens the full-screen page (or, with
  /// [sheet], the player sheet on its Lyrics tab).
  Future<ProviderContainer> open(
    WidgetTester tester, {
    LyricsState state = const LyricsState(),
    bool dark = false,
    double scale = 1,
    bool still = false,
    bool wakeLock = false,
    bool sheet = false,
    Size size = const Size(411, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    player = MemoryPlayer();
    lyrics = _Lyrics(state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(player),
          libraryProvider.overrideWith(() => _Library(songs)),
          playlistsProvider.overrideWith(_Playlists.new),
          positionProvider.overrideWith(_Position.new),
          durationProvider.overrideWith(_Duration.new),
          favoritesStoreProvider.overrideWithValue(_FavStore()),
          rateStoreProvider.overrideWithValue(_Rates()),
          ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
          downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
          lyricsProvider.overrideWith(() => lyrics),
          lyricsScreenAwakeProvider.overrideWithValue(awake.add),
          settingsProvider.overrideWith(
            () => _Settings(SettingsState(enableWakeLock: wakeLock)),
          ),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: WavvyTheme.light(WvAppearance.aqua),
          darkTheme: WavvyTheme.dark(WvAppearance.aqua),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: still,
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => sheet
                    ? Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const FullPlayerSheet(initialPage: 2),
                        ),
                      )
                    : LyricsFullscreenPage.open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    final c = ProviderScope.containerOf(
      tester.element(find.byType(TextButton)),
    );
    await c
        .read(playerProvider.notifier)
        .playSong(songs[0], contextList: songs);
    player.emit(0);
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return c;
  }

  TextStyle styleOf(WidgetTester tester, String text) =>
      DefaultTextStyle.of(tester.element(find.text(text))).style;

  double sizeOf(WidgetTester tester, String text) =>
      styleOf(tester, text).fontSize!;

  group('LyricsFullscreenPage', () {
    testWidgets('shows the song and the lines, the current one emphasized', (
      tester,
    ) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
      );
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
      expect(find.text('second line'), findsOneWidget);
      expect(find.byTooltip('Exit full screen'), findsOneWidget);
      expect(
        sizeOf(tester, 'second line'),
        greaterThan(sizeOf(tester, 'first line')),
      );
      final style = styleOf(tester, 'second line');
      expect(style.fontWeight, FontWeight.w800);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the emphasis follows the current line', (tester) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 0),
      );
      final before = sizeOf(tester, 'third line');
      lyrics.put(LyricsState(lyrics: _synced(), currentIndex: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(sizeOf(tester, 'third line'), greaterThan(before));
      expect(
        sizeOf(tester, 'first line'),
        lessThan(sizeOf(tester, 'third line')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap on a line seeks there', (tester) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 0),
      );
      await tester.tap(find.text('third line'));
      await tester.pump();
      expect(player.seeks, [const Duration(seconds: 9)]);
    });

    testWidgets(
      'the text size buttons change, persist and stop at the bounds',
      (tester) async {
        final c = await open(
          tester,
          state: LyricsState(lyrics: _synced(), currentIndex: 1),
        );
        final base = sizeOf(tester, 'second line');
        await tester.tap(find.byTooltip('Larger text'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(c.read(lyricsFullscreenScaleProvider), closeTo(1.1, 1e-9));
        expect(sizeOf(tester, 'second line'), greaterThan(base));

        await tester.tap(find.byTooltip('Smaller text'));
        await tester.tap(find.byTooltip('Smaller text'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(c.read(lyricsFullscreenScaleProvider), closeTo(0.9, 1e-9));
        expect(sizeOf(tester, 'second line'), lessThan(base));

        final stored = await tester.runAsync(
          () => SharedPreferencesAsync().getDouble(kLyricsScaleKey),
        );
        expect(stored, closeTo(0.9, 1e-9));

        for (var i = 0; i < 4; i++) {
          await tester.tap(find.byTooltip('Smaller text'));
          await tester.pump();
        }
        expect(
          c.read(lyricsFullscreenScaleProvider),
          closeTo(kLyricsScaleMin, 1e-9),
        );
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.text_decrease_rounded),
              )
              .onPressed,
          isNull,
        );
        for (var i = 0; i < 12; i++) {
          await tester.tap(find.byTooltip('Larger text'));
          await tester.pump();
        }
        expect(
          c.read(lyricsFullscreenScaleProvider),
          closeTo(kLyricsScaleMax, 1e-9),
        );
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.text_increase_rounded),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a saved size is used when the page opens', (tester) async {
      await SharedPreferencesAsync().setDouble(kLyricsScaleKey, 1.5);
      final c = await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(c.read(lyricsFullscreenScaleProvider), closeTo(1.5, 1e-9));
    });

    testWidgets('a nonsense saved size is kept within the bounds', (
      tester,
    ) async {
      await SharedPreferencesAsync().setDouble(kLyricsScaleKey, 40);
      final c = await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(c.read(lyricsFullscreenScaleProvider), kLyricsScaleMax);
    });

    testWidgets('immersive mode and the wake lock last as long as the page', (
      tester,
    ) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
        wakeLock: true,
      );
      expect(uiModes, ['SystemUiMode.immersiveSticky']);
      expect(awake, [true]);

      await tester.tap(find.byTooltip('Exit full screen'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LyricsFullscreenPage), findsNothing);
      expect(uiModes, [
        'SystemUiMode.immersiveSticky',
        'SystemUiMode.edgeToEdge',
      ]);
      // Settings keep the screen on, so leaving gives it back as it was.
      expect(awake, [true, true]);
    });

    testWidgets('leaving releases the wake lock when Settings do not hold it', (
      tester,
    ) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 0),
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LyricsFullscreenPage), findsNothing);
      expect(awake, [true, false]);
      expect(uiModes.last, 'SystemUiMode.edgeToEdge');
    });

    testWidgets('plain lyrics are one readable block that is not tappable', (
      tester,
    ) async {
      await open(
        tester,
        state: LyricsState(
          lyrics: [Lyric(Duration.zero, 'line one\nline two\nline three')],
          currentIndex: 0,
        ),
      );
      expect(find.text('line one\nline two\nline three'), findsOneWidget);
      expect(find.text('Lyrics are not synced to the music'), findsOneWidget);
      await tester.tap(find.text('line one\nline two\nline three'));
      await tester.pump();
      expect(player.seeks, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no lyrics and an error offer Try again', (tester) async {
      await open(tester);
      expect(find.text('No lyrics available'), findsOneWidget);
      lyrics.put(const LyricsState(error: 'Network error.'));
      await tester.pump();
      expect(find.text('Lyrics unavailable'), findsOneWidget);
      expect(find.text('Network error.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(lyrics.fetches, ['Track 1']);
    });

    testWidgets('loading shows a spinner, then the lines', (tester) async {
      await open(tester, state: const LyricsState(isLoading: true));
      expect(find.text('No lyrics available'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Track 1'), findsOneWidget);
      lyrics.put(LyricsState(lyrics: _synced(), currentIndex: 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('first line'), findsOneWidget);
    });

    testWidgets('follows the playing song', (tester) async {
      final c = await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
      );
      expect(find.text('Track 1'), findsOneWidget);
      player.emit(2);
      await tester.pump();
      expect(c.read(playerProvider).currentSong?.id, 3);
      expect(find.text('Track 3'), findsOneWidget);
      expect(find.text('Track 1'), findsNothing);
      lyrics.put(const LyricsState(isLoading: true));
      await tester.pump();
      lyrics.put(
        LyricsState(
          lyrics: [Lyric(const Duration(seconds: 2), 'other song')],
          currentIndex: 0,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('other song'), findsOneWidget);
      expect(find.text('second line'), findsNothing);
    });

    testWidgets('reduced motion jumps to the new line', (tester) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 0),
        still: true,
      );
      lyrics.put(LyricsState(lyrics: _synced(), currentIndex: 3));
      await tester.pump();
      // No animation to wait for: the line is already in place.
      final top = tester.getTopLeft(find.text('fourth line')).dy;
      expect(top, lessThan(900 * 0.6));
      expect(top, greaterThan(900 * 0.2));
      expect(tester.takeException(), isNull);
    });

    for (final dark in [false, true]) {
      for (final plain in [false, true]) {
        testWidgets(
          'fits at 320 wide and 1.5x text, dark $dark, plain $plain',
          (tester) async {
            await open(
              tester,
              dark: dark,
              scale: 1.5,
              size: const Size(320, 640),
              state: plain
                  ? LyricsState(
                      lyrics: [
                        Lyric(Duration.zero, 'a long unsynced lyric ' * 12),
                      ],
                      currentIndex: 0,
                    )
                  : LyricsState(lyrics: _synced(), currentIndex: 2),
            );
            await tester.tap(find.byTooltip('Larger text'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
            expect(find.byTooltip('Exit full screen'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('Lyrics tab', () {
    testWidgets(
      'has a Full screen button that opens the page and Back returns',
      (tester) async {
        await open(
          tester,
          sheet: true,
          state: LyricsState(lyrics: _synced(), currentIndex: 1),
        );
        expect(find.byTooltip('Full screen'), findsOneWidget);
        expect(find.byTooltip('Share Card'), findsOneWidget);
        expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);

        await tester.tap(find.byTooltip('Full screen'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(LyricsFullscreenPage), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(LyricsFullscreenPage), findsNothing);
        expect(find.byType(FullPlayerSheet), findsOneWidget);
        expect(find.byTooltip('Full screen'), findsOneWidget);
        expect(uiModes.last, 'SystemUiMode.edgeToEdge');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the sheet keeps following the line after the page closes', (
      tester,
    ) async {
      await open(
        tester,
        sheet: true,
        state: LyricsState(lyrics: _synced(), currentIndex: 0),
      );
      await tester.tap(find.byTooltip('Full screen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      lyrics.put(LyricsState(lyrics: _synced(), currentIndex: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byTooltip('Exit full screen'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('third line'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
