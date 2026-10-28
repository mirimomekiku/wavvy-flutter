import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/models/lyric.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/lyrics_first_layout.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/player_sheets/lyrics_fullscreen.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/settings/player_layout_setting.dart';
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

class _Handler extends Fake implements WavvyAudioHandler {
  int pauses = 0;
  @override
  Future<void> pause() async => pauses++;
}

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
  @override
  Future<void> setPlayerLayout(int index) async =>
      state = state.copyWith(playerLayout: index);
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
  late _Handler handler;
  var artistTaps = 0;
  var lyricsTaps = 0;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          return null;
        });
    artistTaps = 0;
    lyricsTaps = 0;
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Pumps the layout (or, with [sheet], the whole player sheet) with the
  /// Lyrics first layout chosen in the settings.
  Future<ProviderContainer> open(
    WidgetTester tester, {
    LyricsState state = const LyricsState(),
    bool dark = false,
    double scale = 1,
    bool still = false,
    bool sheet = false,
    bool fetching = true,
    bool withLyricsButton = true,
    WvAppearance appearance = WvAppearance.aqua,
    Size size = const Size(360, 640),
    double? height,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    player = MemoryPlayer();
    lyrics = _Lyrics(state);
    handler = _Handler();
    final data = PlayerLayoutData(
      song: songs[0],
      onLyrics: withLyricsButton ? () => lyricsTaps++ : null,
      onArtist: () => artistTaps++,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(player),
          audioHandlerProvider.overrideWithValue(handler),
          libraryProvider.overrideWith(() => _Library(songs)),
          playlistsProvider.overrideWith(_Playlists.new),
          positionProvider.overrideWith(_Position.new),
          durationProvider.overrideWith(_Duration.new),
          favoritesStoreProvider.overrideWithValue(_FavStore()),
          rateStoreProvider.overrideWithValue(_Rates()),
          ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
          downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
          lyricsProvider.overrideWith(() => lyrics),
          settingsProvider.overrideWith(
            () => _Settings(
              SettingsState(
                playerLayout: PlayerLayout.lyrics.index,
                enableLyricsFetching: fetching,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: WavvyTheme.light(appearance),
          darkTheme: WavvyTheme.dark(appearance),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: still,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: sheet
                ? const FullPlayerSheet()
                : SizedBox(
                    height: height ?? size.height - 120,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final song = ref.watch(
                          playerProvider.select((s) => s.currentSong),
                        );
                        return PlayerLayoutHost(
                          data: PlayerLayoutData(
                            song: song ?? songs[0],
                            onLyrics: data.onLyrics,
                            onArtist: data.onArtist,
                          ),
                        );
                      },
                    ),
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
        .playSong(songs[0], contextList: songs);
    player.emit(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return c;
  }

  double sizeOf(WidgetTester tester, String text) =>
      DefaultTextStyle.of(tester.element(find.text(text))).style.fontSize!;

  group('header', () {
    testWidgets('shows the cover, title and artist; the artist opens About', (
      tester,
    ) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
      );
      expect(find.byType(LyricsFirstLayout), findsOneWidget);
      expect(find.byType(PlayerCover), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
      await tester.tap(find.text('Artist'));
      expect(artistTaps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the full-screen button opens the full-screen lyrics', (
      tester,
    ) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
      );
      await tester.tap(find.byTooltip('Full-screen lyrics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LyricsFullscreenPage), findsOneWidget);
    });

    testWidgets('no full-screen button when lyrics are off for the sheet', (
      tester,
    ) async {
      await open(tester, withLyricsButton: false);
      expect(find.byTooltip('Full-screen lyrics'), findsNothing);
    });

    testWidgets('the heart adds to favorites', (tester) async {
      final c = await open(tester);
      await tester.tap(find.byTooltip('Add to Favorites'));
      await tester.pump();
      expect(c.read(favoritesProvider).containsKey(songs[0].id), isTrue);
      expect(find.byTooltip('Remove from Favorites'), findsOneWidget);
    });

    testWidgets('the header cover cross-fades when the song changes', (
      tester,
    ) async {
      final c = await open(tester);
      await c
          .read(playerProvider.notifier)
          .playSong(songs[1], contextList: songs);
      await tester.pump();
      expect(find.byType(PlayerCover), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PlayerCover), findsOneWidget);
    });
  });

  group('lyrics', () {
    testWidgets('the current line is emphasized and follows the song', (
      tester,
    ) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 0),
      );
      final before = sizeOf(tester, 'third line');
      expect(sizeOf(tester, 'first line'), greaterThan(before));
      lyrics.put(LyricsState(lyrics: _synced(), currentIndex: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(sizeOf(tester, 'third line'), greaterThan(before));
      expect(sizeOf(tester, 'third line'), 28);
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

    testWidgets('plain lyrics are shown as text', (tester) async {
      await open(
        tester,
        state: LyricsState(lyrics: [Lyric(Duration.zero, 'la la la')]),
      );
      expect(find.text('la la la'), findsOneWidget);
      expect(find.text('Lyrics are not synced to the music'), findsOneWidget);
    });

    testWidgets('loading shows a spinner', (tester) async {
      await open(tester, state: const LyricsState(isLoading: true));
      expect(find.text('No lyrics available'), findsNothing);
      expect(find.byType(ScrollablePositionedList), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty lyrics offer Try again and Show the cover', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('No lyrics available'), findsOneWidget);
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      expect(lyrics.fetches, ['Track 1']);
      await tester.ensureVisible(find.text('Show the cover'));
      await tester.tap(find.text('Show the cover'));
      await tester.pump();
      expect(find.text('No lyrics available'), findsNothing);
      expect(find.text('Show lyrics'), findsOneWidget);
      expect(find.byType(PlayerCover), findsNWidgets(2));
      await tester.ensureVisible(find.text('Show lyrics'));
      await tester.tap(find.text('Show lyrics'));
      await tester.pump();
      expect(find.text('No lyrics available'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('errors show the message and the cover button', (tester) async {
      await open(tester, state: const LyricsState(error: 'Network down'));
      expect(find.text('Lyrics unavailable'), findsOneWidget);
      expect(find.text('Network down'), findsOneWidget);
      expect(find.text('Show the cover'), findsOneWidget);
    });

    testWidgets('the cover choice is cleared when the song changes', (
      tester,
    ) async {
      final c = await open(tester);
      await tester.ensureVisible(find.text('Show the cover'));
      await tester.tap(find.text('Show the cover'));
      await tester.pump();
      expect(find.text('Show lyrics'), findsOneWidget);
      await c
          .read(playerProvider.notifier)
          .playSong(songs[1], contextList: songs);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Show lyrics'), findsNothing);
      expect(find.text('No lyrics available'), findsOneWidget);
      expect(find.text('Track 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lyrics turned off in settings show a message and the cover', (
      tester,
    ) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
        fetching: false,
        withLyricsButton: false,
      );
      expect(find.text('Lyrics are turned off'), findsOneWidget);
      expect(find.text('second line'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      await tester.ensureVisible(find.text('Show the cover'));
      await tester.tap(find.text('Show the cover'));
      await tester.pump();
      expect(find.text('Show lyrics'), findsOneWidget);
      await tester.ensureVisible(find.text('Show lyrics'));
      await tester.tap(find.text('Show lyrics'));
      await tester.pump();
      expect(find.text('Lyrics are turned off'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('controls', () {
    testWidgets('transport and modes work', (tester) async {
      final c = await open(tester);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(handler.pauses, 1);
      await tester.tap(find.byTooltip('Shuffle'));
      await tester.pump();
      expect(c.read(playerProvider).isShuffleModeEnabled, isTrue);
      expect(find.byTooltip('Shuffle on'), findsOneWidget);
      await tester.tap(find.byTooltip('Repeat'));
      await tester.pump();
      expect(c.read(playerProvider).loopMode.name, 'all');
      expect(find.byTooltip('Sound'), findsOneWidget);
      expect(find.byTooltip('Next'), findsOneWidget);
      expect(find.byTooltip('Previous'), findsOneWidget);
    });

    testWidgets('the seek bar is there and shows the times', (tester) async {
      await open(tester);
      expect(find.text('0:50'), findsOneWidget);
      expect(find.text('3:00'), findsOneWidget);
    });

    testWidgets('the extras row shows only when there is room', (tester) async {
      await open(tester, size: const Size(360, 900), height: 800);
      expect(find.byKey(const Key('ab_loop')), findsOneWidget);
    });

    testWidgets('the extras row is left out on a short page', (tester) async {
      await open(tester, height: 470);
      expect(find.byKey(const Key('ab_loop')), findsNothing);
    });
  });

  group('sheet', () {
    testWidgets('choosing the layout shows it, and Lyrics tab does not clash', (
      tester,
    ) async {
      await open(
        tester,
        sheet: true,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
      );
      expect(find.byType(LyricsFirstLayout), findsOneWidget);
      expect(find.byType(ScrollablePositionedList), findsOneWidget);
      await tester.tap(find.byTooltip('Lyrics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      expect(find.text('second line'), findsOneWidget);
      await tester.tap(find.byTooltip('Player'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(LyricsFirstLayout), findsOneWidget);
      expect(find.text('second line'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the picker shows the preview and selecting sets the layout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              () => _Settings(const SettingsState(playerLayout: 0)),
            ),
          ],
          child: MaterialApp(
            theme: WavvyTheme.light(WvAppearance.aqua),
            home: const Scaffold(body: PlayerLayoutPicker()),
          ),
        ),
      );
      expect(find.byType(LyricsFirstLayoutPreview), findsOneWidget);
      await tester.tap(find.byType(LyricsFirstLayoutPreview));
      await tester.pump();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(PlayerLayoutPicker)),
      );
      expect(c.read(settingsProvider).playerLayout, PlayerLayout.lyrics.index);
      expect(tester.takeException(), isNull);
    });
  });

  group('sizes and looks', () {
    final sizes = [const Size(320, 568), const Size(360, 640)];
    for (final size in sizes) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final dark in [false, true]) {
          testWidgets(
            'no overflow at ${size.width.toInt()}x${size.height.toInt()} '
            'scale $scale dark=$dark',
            (tester) async {
              await open(
                tester,
                state: LyricsState(lyrics: _synced(), currentIndex: 1),
                size: size,
                scale: scale,
                dark: dark,
                height: size.height - 100,
              );
              expect(tester.takeException(), isNull);
              expect(find.byTooltip('Pause'), findsOneWidget);
              await tester.ensureVisible(find.byTooltip('Sound'));
              expect(tester.takeException(), isNull);
            },
          );
          testWidgets('empty lyrics and big cover fit at ${size.width.toInt()}x'
              '${size.height.toInt()} scale $scale dark=$dark', (tester) async {
            await open(
              tester,
              size: size,
              scale: scale,
              dark: dark,
              height: size.height - 100,
            );
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.text('Show the cover'));
            await tester.tap(find.text('Show the cover'));
            await tester.pump();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    for (final appearance in [
      WvAppearance.aqua,
      WvAppearance.graphite,
      WvAppearance.pinstripe,
      WvAppearance.brushedMetal,
    ]) {
      for (final dark in [false, true]) {
        testWidgets('${appearance.name} dark=$dark', (tester) async {
          await open(
            tester,
            state: LyricsState(lyrics: _synced(), currentIndex: 1),
            appearance: appearance,
            dark: dark,
            scale: 1.5,
            size: const Size(320, 568),
            height: 480,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('short heights scroll the page; controls stay reachable', (
      tester,
    ) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
        size: const Size(740, 360),
        height: 260,
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      final play = find.byTooltip('Pause');
      await tester.ensureVisible(play);
      await tester.tap(play);
      await tester.pump();
      expect(handler.pauses, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the lyrics area shrinks before the page scrolls', (
      tester,
    ) async {
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
        height: 560,
      );
      expect(
        find.descendant(
          of: find.byType(LyricsFirstLayout),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      expect(
        tester.getSize(find.byType(ScrollablePositionedList)).height,
        greaterThanOrEqualTo(kLyricsFirstMinLyrics),
      );
    });

    testWidgets('reduced motion works', (tester) async {
      final c = await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 0),
        still: true,
      );
      lyrics.put(LyricsState(lyrics: _synced(), currentIndex: 3));
      await tester.pump();
      expect(sizeOf(tester, 'fourth line'), 28);
      await c
          .read(playerProvider.notifier)
          .playSong(songs[1], contextList: songs);
      await tester.pump();
      expect(find.byType(PlayerCover), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('custom controls have semantics labels', (tester) async {
      final handle = tester.ensureSemantics();
      await open(
        tester,
        state: LyricsState(lyrics: _synced(), currentIndex: 1),
      );
      final seen = <String>[];
      void walk(SemanticsNode n) {
        final d = n.getSemanticsData();
        seen.add('${d.label} ${d.tooltip}');
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }

      walk(tester.getSemantics(find.byType(Scaffold).first));
      final all = seen.join('|');
      for (final label in [
        'Full-screen lyrics',
        'Shuffle',
        'Repeat',
        'Sound',
        'Pause',
        'Add to Favorites',
      ]) {
        expect(all, contains(label), reason: label);
      }
      expect(find.bySemanticsLabel('second line'), findsOneWidget);
      handle.dispose();
    });
  });

  testWidgets('the preview paints in every appearance', (tester) async {
    for (final appearance in WvAppearance.values) {
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark
                ? WavvyTheme.dark(appearance)
                : WavvyTheme.light(appearance),
            home: const Scaffold(
              body: SizedBox(
                width: 150,
                height: 190,
                child: LyricsFirstLayoutPreview(),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    }
  });
}
