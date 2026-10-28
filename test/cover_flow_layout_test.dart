import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:on_audio_query/on_audio_query.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/player_sheets/layouts/cover_flow_layout.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/settings/player_layout_setting.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

import 'helpers/fake_engine.dart';
import 'helpers/fake_player.dart';

/// A player that remembers which row it was asked to jump to and, like the
/// real one, reports it as playing afterwards (unless [autoEmit] is off).
class _Player extends MemoryPlayer {
  final jumps = <int>[];
  bool autoEmit = true;
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    await super.seek(position, index: index);
    if (index != null) {
      jumps.add(index);
      if (autoEmit) emit(index);
    }
  }
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

class _Settings extends SettingsNotifier {
  _Settings(this.layout);
  final int layout;
  @override
  SettingsState build() => SettingsState(playerLayout: layout);
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

/// What the sheet does around the layout: hands it the playing song.
class _Page extends ConsumerWidget {
  const _Page({required this.host, this.onLyrics});
  final bool host;
  final VoidCallback? onLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final data = PlayerLayoutData(song: song, onLyrics: onLyrics);
    return host ? PlayerLayoutHost(data: data) : CoverFlowLayout(data: data);
  }
}

List<SongModel> _songs(int n) => [for (var i = 1; i <= n; i++) testSong(i)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Player player;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
  });

  Widget app(
    Widget home, {
    List<SongModel> library = const [],
    bool dark = false,
    double scale = 1,
    bool reduce = false,
    WvAppearance appearance = WvAppearance.aqua,
    int layout = 2,
  }) => ProviderScope(
    overrides: [
      audioPlayerProvider.overrideWithValue(player),
      libraryProvider.overrideWith(() => _Library(library)),
      playlistsProvider.overrideWith(_Playlists.new),
      positionProvider.overrideWith(_Position.new),
      durationProvider.overrideWith(_Duration.new),
      favoritesStoreProvider.overrideWithValue(_FavStore()),
      rateStoreProvider.overrideWithValue(_Rates()),
      ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
      downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
      settingsProvider.overrideWith(() => _Settings(layout)),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      theme: WavvyTheme.light(appearance),
      darkTheme: WavvyTheme.dark(appearance),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduce,
        ),
        child: child!,
      ),
      home: Scaffold(body: home),
    ),
  );

  /// Shows the layout with [songs] queued and row [current] playing.
  Future<ProviderContainer> pumpFlow(
    WidgetTester tester, {
    List<SongModel>? songs,
    int current = 2,
    Size size = const Size(411, 800),
    double scale = 1,
    bool dark = false,
    bool reduce = false,
    bool host = false,
    int layout = 2,
    bool empty = false,
    VoidCallback? onLyrics,
    WvAppearance appearance = WvAppearance.aqua,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    player = _Player();
    addTearDown(player.close);
    final queue = songs ?? _songs(5);
    await tester.pumpWidget(
      app(
        _Page(host: host, onLyrics: onLyrics),
        library: queue,
        dark: dark,
        scale: scale,
        reduce: reduce,
        appearance: appearance,
        layout: layout,
      ),
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    if (!empty) {
      await c
          .read(playerProvider.notifier)
          .playSong(queue[current], contextList: queue);
      player.emit(current);
    } else {
      // Nothing queued, but the layout is still shown for a song.
      c.read(playerProvider.notifier).state = c
          .read(playerProvider)
          .copyWith(currentSong: testSong(1));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return c;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
  }

  PageController pages(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!;

  Future<void> swipeLeft(WidgetTester tester) async {
    await tester.fling(find.byType(PageView), const Offset(-110, 0), 700);
    await settle(tester);
  }

  Future<void> swipeRight(WidgetTester tester) async {
    await tester.fling(find.byType(PageView), const Offset(110, 0), 700);
    await settle(tester);
  }

  group('the carousel', () {
    testWidgets('shows the current cover and title', (tester) async {
      await pumpFlow(tester);
      expect(find.byType(CoverFlowLayout), findsOneWidget);
      expect(find.text('Track 3'), findsOneWidget);
      expect(pages(tester).page, 2);
      expect(find.byType(PlayerCover), findsWidgets);
      expect(find.byType(PlayerTransport), findsOneWidget);
      expect(find.byType(PlayerSeekRow), findsOneWidget);
      expect(find.byType(PlayerExtras), findsOneWidget);
      expect(find.byType(PlayerModeDock), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('settling on another cover jumps the player once', (
      tester,
    ) async {
      final c = await pumpFlow(tester);
      await swipeLeft(tester);
      expect(player.jumps, [3]);
      expect(c.read(playerProvider).currentIndex, 3);
      expect(pages(tester).page, 3);
      expect(find.text('Track 4'), findsOneWidget);
      await swipeRight(tester);
      expect(player.jumps, [3, 2]);
      expect(pages(tester).page, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a slow player is not asked twice and keeps playing', (
      tester,
    ) async {
      final c = await pumpFlow(tester);
      player.autoEmit = false;
      player.setPlaying(true);
      await tester.pump();
      final plays = player.playCalls;
      await swipeLeft(tester);
      // The player has not answered yet: the carousel stays, one request.
      expect(player.jumps, [3]);
      expect(player.playCalls, plays + 1);
      expect(pages(tester).page, 3);
      // Its answer changes nothing in the carousel and asks for nothing.
      player.emit(3);
      await settle(tester);
      expect(player.jumps, [3]);
      expect(pages(tester).page, 3);
      expect(c.read(playerProvider).currentIndex, 3);
    });

    testWidgets('a paused player is not started by a swipe', (tester) async {
      await pumpFlow(tester);
      player.setPlaying(false);
      await tester.pump();
      final plays = player.playCalls;
      await swipeLeft(tester);
      expect(player.jumps, [3]);
      expect(player.playCalls, plays);
    });

    testWidgets('an outside change moves the carousel, not the player', (
      tester,
    ) async {
      final c = await pumpFlow(tester);
      player.emit(3); // the next button, a track ending, the notification
      await settle(tester);
      expect(pages(tester).page, 3);
      expect(find.text('Track 4'), findsOneWidget);
      expect(player.jumps, isEmpty);
      player.emit(0);
      await settle(tester);
      expect(pages(tester).page, 0);
      expect(player.jumps, isEmpty);
      expect(c.read(playerProvider).currentIndex, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the end of the queue does not move or jump', (tester) async {
      await pumpFlow(tester, current: 4);
      await swipeLeft(tester);
      expect(player.jumps, isEmpty);
      expect(pages(tester).page, 4);
    });

    testWidgets('tapping a side cover slides to it and jumps once', (
      tester,
    ) async {
      await pumpFlow(tester);
      final box = tester.getRect(find.byType(PageView));
      // The cover on the right of the middle one.
      await tester.tapAt(
        Offset(box.center.dx + box.width * 0.36, box.center.dy),
      );
      await settle(tester);
      expect(player.jumps, [3]);
      expect(pages(tester).page, 3);
    });

    testWidgets('duplicates of a song are told apart by position', (
      tester,
    ) async {
      final songs = [testSong(1), testSong(2), testSong(1), testSong(1)];
      final c = await pumpFlow(tester, songs: songs, current: 3);
      expect(pages(tester).page, 3);
      await swipeRight(tester);
      expect(player.jumps, [2]);
      expect(c.read(playerProvider).currentIndex, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a queue edit keeps the page in range', (tester) async {
      final c = await pumpFlow(tester, current: 4);
      final notifier = c.read(playerProvider.notifier);
      await notifier.removeFromQueue(0);
      player.emit(3);
      await settle(tester);
      expect(c.read(playerProvider).queue, hasLength(4));
      expect(pages(tester).page, 3);
      await notifier.removeQueueIndices({1, 2});
      player.emit(1);
      await settle(tester);
      expect(c.read(playerProvider).queue, hasLength(2));
      expect(pages(tester).page, 1);
      expect(player.jumps, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a queue edit that shrinks past the page clamps it', (
      tester,
    ) async {
      final c = await pumpFlow(tester, current: 4);
      await c.read(playerProvider.notifier).removeQueueIndices({3, 4});
      // The player has not reported an index yet.
      await settle(tester);
      expect(pages(tester).page!.round(), lessThan(3));
      expect(tester.takeException(), isNull);
      expect(player.jumps, isEmpty);
    });

    testWidgets('repeat all does not break the row', (tester) async {
      final c = await pumpFlow(tester, current: 4);
      await c.read(playerProvider.notifier).cycleLoopMode();
      expect(c.read(playerProvider).loopMode, audio.LoopMode.all);
      await settle(tester);
      await swipeLeft(tester);
      expect(pages(tester).page, 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one song', (tester) async {
      await pumpFlow(tester, songs: _songs(1), current: 0);
      expect(find.text('Track 1'), findsOneWidget);
      await swipeLeft(tester);
      await swipeRight(tester);
      expect(player.jumps, isEmpty);
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester);
      expect(find.text('Nothing after this'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty queue does not crash', (tester) async {
      await pumpFlow(tester, empty: true);
      expect(find.byType(CoverFlowLayout), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
      await swipeLeft(tester);
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester);
      expect(player.jumps, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a huge queue builds only the covers near the middle', (
      tester,
    ) async {
      final songs = _songs(3000);
      await pumpFlow(tester, songs: songs, current: 1500);
      expect(pages(tester).page, 1500);
      // A cover and its reflection each.
      expect(find.byType(PlayerCover).evaluate().length, lessThanOrEqualTo(14));
      expect(find.text('Track 1501'), findsOneWidget);
      await swipeLeft(tester);
      expect(player.jumps, [1501]);
      expect(find.byType(PlayerCover).evaluate().length, lessThanOrEqualTo(14));
      expect(tester.takeException(), isNull);
    });
  });

  group('the back of a cover', () {
    testWidgets('tapping the middle cover lists what is next', (tester) async {
      await pumpFlow(tester);
      expect(find.text('Up next'), findsNothing);
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester);
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('Track 4'), findsOneWidget);
      expect(find.text('Track 5'), findsOneWidget);
      expect(find.text('Track 2'), findsNothing); // only what follows
      // Tapping the header turns it back.
      await tester.tap(find.text('Up next'));
      await settle(tester);
      expect(find.text('Up next'), findsNothing);
      expect(player.jumps, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a song there jumps to it once', (tester) async {
      final c = await pumpFlow(tester);
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester);
      await tester.tap(find.text('Track 5'));
      await settle(tester);
      expect(player.jumps, [4]);
      expect(c.read(playerProvider).currentIndex, 4);
      expect(pages(tester).page, 4);
      expect(find.text('Up next'), findsNothing);
    });

    testWidgets('swiping turns it back', (tester) async {
      await pumpFlow(tester);
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester);
      expect(find.text('Up next'), findsOneWidget);
      await swipeLeft(tester);
      expect(find.text('Up next'), findsNothing);
      expect(player.jumps, [3]);
    });

    testWidgets('the next button turns it back too', (tester) async {
      await pumpFlow(tester);
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester);
      player.emit(3);
      await settle(tester);
      expect(find.text('Up next'), findsNothing);
      expect(pages(tester).page, 3);
    });

    testWidgets('only the next 20 are listed', (tester) async {
      await pumpFlow(tester, songs: _songs(60), current: 5);
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester);
      expect(find.text('Track 7'), findsOneWidget);
      expect(find.text('Track 40'), findsNothing);
    });

    testWidgets('a lyrics button only when lyrics are on', (tester) async {
      await pumpFlow(tester);
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester);
      expect(find.byTooltip('View lyrics'), findsNothing);
    });

    testWidgets('the lyrics button on the back opens them', (tester) async {
      var opened = 0;
      await pumpFlow(tester, onLyrics: () => opened++);
      // The song actions have one; the back adds another.
      expect(find.byTooltip('View lyrics'), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester);
      expect(find.byTooltip('View lyrics'), findsNWidgets(2));
      await tester.tap(
        find.descendant(
          of: find.byType(PageView),
          matching: find.byTooltip('View lyrics'),
        ),
      );
      await tester.pump();
      expect(opened, 1);
    });
  });

  group('reduced motion', () {
    testWidgets('covers are flat and the page changes at once', (tester) async {
      await pumpFlow(tester, reduce: true);
      var turned = 0;
      for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
        if (t.transform.entry(0, 2).abs() > 1e-6) turned++;
      }
      expect(turned, 0);
      player.emit(3);
      await tester.pump();
      await tester.pump();
      expect(pages(tester).page, 3);
      // The flip is instant.
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await tester.pump();
      expect(find.text('Up next'), findsOneWidget);
      await tester.tap(find.text('Up next'));
      await tester.pump();
      expect(find.text('Up next'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with motion the side covers are turned', (tester) async {
      await pumpFlow(tester);
      var turned = 0;
      for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
        if (t.transform.entry(0, 2).abs() > 0.1) turned++;
      }
      expect(turned, greaterThan(0));
    });
  });

  group('fits', () {
    final cases = <(Size, double)>[
      (const Size(320, 568), 1),
      (const Size(320, 568), 1.5),
      (const Size(320, 568), 2),
      (const Size(360, 640), 1),
      (const Size(360, 640), 1.5),
      (const Size(360, 640), 2),
    ];
    for (final (size, scale) in cases) {
      for (final dark in [false, true]) {
        testWidgets('${size.width.toInt()}x${size.height.toInt()} '
            'at ${scale}x text, dark $dark', (tester) async {
          await pumpFlow(tester, size: size, scale: scale, dark: dark);
          expect(tester.takeException(), isNull);
          // Turned over, too.
          await tester.tapAt(tester.getCenter(find.byType(PageView)));
          await settle(tester);
          expect(find.text('Up next'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final appearance in [
      WvAppearance.graphite,
      WvAppearance.pinstripe,
      WvAppearance.brushedMetal,
    ]) {
      for (final dark in [false, true]) {
        testWidgets('${appearance.name}, dark $dark, 320 wide at 2x', (
          tester,
        ) async {
          await pumpFlow(
            tester,
            size: const Size(320, 568),
            scale: 2,
            dark: dark,
            appearance: appearance,
            onLyrics: () {},
          );
          expect(tester.takeException(), isNull);
          await tester.tapAt(tester.getCenter(find.byType(PageView)));
          await settle(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a tablet', (tester) async {
      await pumpFlow(tester, size: const Size(900, 1200), dark: true);
      expect(tester.takeException(), isNull);
      expect(find.text('Track 3'), findsOneWidget);
    });

    testWidgets('a short landscape phone scrolls instead of clipping', (
      tester,
    ) async {
      await pumpFlow(tester, size: const Size(640, 360));
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });

  group('semantics', () {
    testWidgets('the covers and the row are labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpFlow(tester);
      expect(
        find.bySemanticsLabel(RegExp(r'Track 3, Artist\. Turn the cover over')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Show Track 4'), findsOneWidget);
      expect(find.bySemanticsLabel('Show Track 2'), findsOneWidget);
      final row = tester.getSemantics(find.bySemanticsLabel('Cover Flow'));
      expect(row.value, '3 of 5');
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await settle(tester);
      expect(
        find.bySemanticsLabel(RegExp(r'Up next\. Turn the cover back')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('increase and decrease move through the queue', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpFlow(tester);
      tester.semantics.performAction(
        find.semantics.byLabel('Cover Flow'),
        SemanticsAction.increase,
      );
      await settle(tester);
      expect(player.jumps, [3]);
      handle.dispose();
    });
  });

  group('the picker and the sheet', () {
    testWidgets('the preview paints', (tester) async {
      expect(kPlayerLayoutPreviews[PlayerLayout.coverFlow], isNotNull);
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: WavvyTheme.light(WvAppearance.aqua),
            darkTheme: WavvyTheme.dark(WvAppearance.aqua),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: const Center(
              child: SizedBox(
                width: 120,
                height: 150,
                child: CoverFlowLayoutPreview(),
              ),
            ),
          ),
        );
        expect(
          find.descendant(
            of: find.byType(CoverFlowLayoutPreview),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the picker shows it and choosing it saves the layout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      player = _Player();
      addTearDown(player.close);
      await tester.pumpWidget(app(const PlayerLayoutPicker(), layout: 0));
      expect(find.byType(CoverFlowLayoutPreview), findsOneWidget);
      expect(find.text('Cover Flow'), findsOneWidget);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(PlayerLayoutPicker)),
      );
      expect(c.read(settingsProvider).playerLayout, 0);
      await tester.tap(find.text('Cover Flow'));
      await tester.pump();
      expect(
        c.read(settingsProvider).playerLayout,
        PlayerLayout.coverFlow.index,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('choosing it makes the sheet show it', (tester) async {
      tester.view.physicalSize = const Size(411, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      player = _Player();
      addTearDown(player.close);
      final songs = _songs(5);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FullPlayerSheet(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
          library: songs,
          layout: 0,
        ),
      );
      final c = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      );
      await c
          .read(playerProvider.notifier)
          .playSong(songs[1], contextList: songs);
      player.emit(1);
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CoverFlowLayout), findsNothing);

      await c
          .read(settingsProvider.notifier)
          .setPlayerLayout(PlayerLayout.coverFlow.index);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CoverFlowLayout), findsOneWidget);
      expect(find.text('Track 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('through the host, the chosen layout is this one', (
      tester,
    ) async {
      await pumpFlow(tester, host: true, layout: 2);
      expect(find.byType(CoverFlowLayout), findsOneWidget);
      await swipeLeft(tester);
      expect(player.jumps, [3]);
    });

    test('the registry builds it', () {
      expect(
        kPlayerLayoutBuilders[PlayerLayout.coverFlow]!(
          PlayerLayoutData(song: testSong(1)),
        ),
        isA<CoverFlowLayout>(),
      );
    });
  });
}
