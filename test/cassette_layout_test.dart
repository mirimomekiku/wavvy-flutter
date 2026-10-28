import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/core/storage_permissions.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/playback/visualizer_math.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/player_sheets/layouts/cassette_layout.dart';
import 'package:wavvy/player_sheets/layouts/cassette_painter.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/providers/visualizer_provider.dart';
import 'package:wavvy/screens/settings/player_layout_setting.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

import 'helpers/fake_engine.dart';
import 'helpers/fake_player.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
}

class _Channel extends VisualizerChannel {
  // ignore: close_sinks
  final controller = StreamController<List<double>>.broadcast(sync: true);
  @override
  Future<void> start(int sessionId, {int bands = kVisualizerBands}) async {}
  @override
  Future<void> stop() async {}
  @override
  Stream<List<double>> frames() => controller.stream;
  @override
  Future<StorageAccess> permission({bool request = false}) async =>
      StorageAccess.granted;
  @override
  Future<void> openSettings() async {}
}

class _Handler extends Fake implements WavvyAudioHandler {
  int plays = 0, pauses = 0;
  @override
  Future<void> play() async => plays++;
  @override
  Future<void> pause() async => pauses++;
}

final _handler = _Handler();

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
  void set(Duration d) => state = d;
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

Future<void> _flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

final _songs = [
  for (var i = 1; i <= 3; i++) testSong(i, albumId: 100),
  testSong(4), // no album: a plain label
];

enum _Host { layout, direct, sheet, picker }

Future<MemoryPlayer> _pump(
  WidgetTester tester, {
  Size size = const Size(411, 900),
  double scale = 1,
  bool dark = false,
  WvAppearance appearance = WvAppearance.aqua,
  SettingsState? settings,
  _Host host = _Host.layout,
  bool reduced = false,
  SongModel? song,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final player = MemoryPlayer();
  final data = PlayerLayoutData(song: song ?? _songs[0], onLyrics: () {});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioPlayerProvider.overrideWithValue(player),
        audioHandlerProvider.overrideWithValue(_handler),
        libraryProvider.overrideWith(() => _Library(_songs)),
        playlistsProvider.overrideWith(_Playlists.new),
        positionProvider.overrideWith(_Position.new),
        durationProvider.overrideWith(_Duration.new),
        favoritesStoreProvider.overrideWithValue(_FavStore()),
        rateStoreProvider.overrideWithValue(_Rates()),
        settingsProvider.overrideWith(
          () => _Settings(
            settings ??
                SettingsState(
                  playerLayout: PlayerLayout.cassette.index,
                  playerLayoutAdaptive: false,
                ),
          ),
        ),
        ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
        downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
        visualizerChannelProvider.overrideWithValue(_Channel()),
        visualizerSessionProvider.overrideWith((ref) => Stream<int?>.value(5)),
        visualizerPlayingProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: dark
            ? WavvyTheme.dark(appearance)
            : WavvyTheme.light(appearance),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: switch (host) {
          _Host.layout => Scaffold(body: PlayerLayoutHost(data: data)),
          _Host.direct => Scaffold(body: CassetteLayout(data: data)),
          _Host.sheet => const FullPlayerSheet(),
          _Host.picker => const Scaffold(body: PlayerLayoutPicker()),
        },
      ),
    ),
  );
  await tester.pump();
  await _flush(tester);
  return player;
}

CassettePainter _painter(WidgetTester tester) => [
  for (final p in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
    if (p.painter is CassettePainter) p.painter! as CassettePainter,
].single;

AnimationController _spin(WidgetTester tester) =>
    _painter(tester).spin as AnimationController;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
  });

  group('math', () {
    test('tape is all on the left reel at 0 and all on the right at 1', () {
      final start = cassetteReelRadii(0, reelMax: 10, hub: 4);
      final end = cassetteReelRadii(1, reelMax: 10, hub: 4);
      expect(start.supply, 10);
      expect(start.takeUp, closeTo(4.6, 1e-9));
      expect(end.takeUp, 10);
      expect(end.supply, closeTo(4.6, 1e-9));
    });

    test('the radii change linearly with progress and clamp', () {
      final mid = cassetteReelRadii(0.5, reelMax: 10, hub: 4);
      expect(mid.supply, closeTo(7.3, 1e-9));
      expect(mid.takeUp, closeTo(7.3, 1e-9));
      final quarter = cassetteReelRadii(0.25, reelMax: 10, hub: 4);
      expect(quarter.supply, closeTo(10 - 5.4 * 0.25, 1e-9));
      expect(cassetteReelRadii(-3, reelMax: 10, hub: 4).supply, 10);
      expect(cassetteReelRadii(9, reelMax: 10, hub: 4).takeUp, 10);
      expect(cassetteReelRadii(double.nan, reelMax: 10, hub: 4).supply, 10);
    });

    test('a full reel fits in the window', () {
      const g = CassetteGeometry(300);
      expect(g.window.contains(g.supply + Offset(0, g.reelMax - 1)), isTrue);
      expect(g.supply.dy - g.reelMax, greaterThanOrEqualTo(g.window.top));
      expect(g.supply.dy + g.reelMax, lessThanOrEqualTo(g.window.bottom));
    });

    test('the supply spool turns a little faster than the take-up', () {
      expect(kCassetteSupplyTurns, greaterThan(kCassetteTakeUpTurns));
      // One turn per 1.5 s for the take-up spool.
      expect(kCassetteSpinCycle.inMilliseconds / kCassetteTakeUpTurns, 1500);
    });
  });

  group('layout', () {
    testWidgets('shows the song, the counter and the keys', (tester) async {
      await _pump(tester);
      expect(find.byType(CassetteLayout), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('0:50'), findsWidgets);
      expect(find.byTooltip('Previous'), findsOneWidget);
      expect(find.byTooltip('Next'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byTooltip('View lyrics'), findsOneWidget);
      expect(find.byTooltip('Add to Favorites'), findsOneWidget);
      expect(find.byType(AquaSeekBar), findsOneWidget);
      expect(find.byKey(const Key('ab_loop')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('builds directly too, and the counter follows the time', (
      tester,
    ) async {
      await _pump(tester, host: _Host.direct);
      expect(find.text('0:50'), findsWidgets);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(CassetteLayout)),
      );
      (c.read(positionProvider.notifier) as _Position).set(
        const Duration(seconds: 75),
      );
      await tester.pump();
      expect(find.text('1:15'), findsWidgets);
    });

    testWidgets('the seek bar and extras still work', (tester) async {
      final player = await _pump(tester);
      await tester.ensureVisible(find.byTooltip('Forward 15 seconds'));
      await tester.tap(find.byTooltip('Forward 15 seconds'));
      await tester.pump();
      expect(player.seeks.last, const Duration(seconds: 65));
      final bar = find.byType(AquaSeekBar);
      await tester.ensureVisible(bar);
      await tester.tapAt(tester.getCenter(bar));
      await tester.pump();
      expect(player.seeks.last.inSeconds, closeTo(90, 3));
    });

    testWidgets(
      'an album-less song gets a plain label, a long title ellipsizes',
      (tester) async {
        await _pump(tester, song: _songs[3]);
        expect(find.text('Track 4'), findsOneWidget);
        expect(find.byType(CassetteLayout), findsOneWidget);
        expect(tester.takeException(), isNull);
        final long = SongModel({
          '_id': 9,
          '_data': '/music/9.mp3',
          '_uri': 'content://media/9',
          'title': 'A very long song title ' * 12,
          'artist': 'An artist with a rather long name ' * 6,
          'album_id': 100,
          'duration': 1000,
        });
        await _pump(tester, song: long, size: const Size(320, 568));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the sheet keys drive the player', (tester) async {
      final player = await _pump(tester, host: _Host.sheet);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(FullPlayerSheet)),
      );
      await c
          .read(playerProvider.notifier)
          .playSong(_songs[1], contextList: _songs);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CassetteLayout), findsOneWidget);
      expect(find.text('Track 2'), findsWidgets);
      // Second of four: both neighbours exist.
      final before = _handler.plays + _handler.pauses;
      final toggle = find.byTooltip('Play').evaluate().isNotEmpty
          ? find.byTooltip('Play')
          : find.byTooltip('Pause');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(_handler.plays + _handler.pauses, before + 1);
      expect(player.sources, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('previous and next are off at the ends, like the transport', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, host: _Host.sheet);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(FullPlayerSheet)),
      );
      await c
          .read(playerProvider.notifier)
          .playSong(_songs[0], contextList: _songs);
      await tester.pump();
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Previous')),
        isSemantics(label: 'Previous', isButton: true, isEnabled: false),
      );
      handle.dispose();
    });
  });

  group('the cassette', () {
    testWidgets('the spools turn while playing and stop when paused', (
      tester,
    ) async {
      final player = await _pump(tester);
      expect(_spin(tester).isAnimating, isFalse);
      player.setPlaying(true);
      await tester.pump();
      await tester.pump();
      expect(_spin(tester).isAnimating, isTrue);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      final turned = _spin(tester).value;
      expect(turned, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_spin(tester).value, isNot(turned));
      player.setPlaying(false);
      await tester.pump();
      expect(_spin(tester).isAnimating, isFalse);
      final held = _spin(tester).value;
      await tester.pump(const Duration(seconds: 1));
      expect(_spin(tester).value, held);
      expect(find.byTooltip('Play'), findsOneWidget);
    });

    testWidgets('the tape amount follows the position', (tester) async {
      await _pump(tester);
      expect(_painter(tester).progress.value, closeTo(50 / 180, 1e-9));
      final c = ProviderScope.containerOf(
        tester.element(find.byType(CassetteLayout)),
      );
      final position = c.read(positionProvider.notifier) as _Position;
      position.set(Duration.zero);
      await tester.pump();
      expect(_painter(tester).progress.value, 0);
      position.set(const Duration(minutes: 3));
      await tester.pump();
      expect(_painter(tester).progress.value, 1);
      position.set(const Duration(seconds: 90));
      await tester.pump();
      expect(_painter(tester).progress.value, closeTo(0.5, 1e-9));
    });

    testWidgets('reduced motion: the spools stay still', (tester) async {
      final player = await _pump(tester, reduced: true);
      player.setPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_spin(tester).isAnimating, isFalse);
      expect(_spin(tester).value, 0);
      // Pressing play still shows (the key is pressed in).
      expect(find.byTooltip('Pause'), findsOneWidget);
    });

    testWidgets('leaving the layout stops the animation', (tester) async {
      final player = await _pump(tester);
      player.setPlaying(true);
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('semantics: the cassette, the counter and the keys', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(find.bySemanticsLabel('Cassette tape'), findsOneWidget);
      final counter = tester.getSemantics(
        find.bySemanticsLabel('Tape counter'),
      );
      expect(counter.value, '0:50');
      for (final label in ['Previous', 'Play', 'Next']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(label: label, isButton: true),
        );
      }
      handle.dispose();
    });
  });

  group('no overflow', () {
    const sizes = [Size(320, 568), Size(360, 640)];
    for (final appearance in WvAppearance.values) {
      testWidgets('${appearance.name}: 320x568 and 360x640, 1x to 2x, both '
          'brightnesses', (tester) async {
        for (final dark in [false, true]) {
          for (final size in sizes) {
            for (final scale in [1.0, 1.5, 2.0]) {
              final player = await _pump(
                tester,
                size: size,
                scale: scale,
                dark: dark,
                appearance: appearance,
              );
              player.setPlaying(scale == 1.5);
              await tester.pump();
              expect(
                tester.takeException(),
                isNull,
                reason: '${appearance.name} dark=$dark $size x$scale',
              );
              expect(find.byType(CassetteLayout), findsOneWidget);
              // Whatever does not fit scrolls rather than clips.
              await tester.drag(
                find.byType(CassetteLayout),
                const Offset(0, -2000),
              );
              await tester.pump();
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
            }
          }
        }
      });
    }

    testWidgets('a tablet width and a short, wide screen', (tester) async {
      await _pump(tester, size: const Size(900, 700));
      expect(tester.takeException(), isNull);
      await _pump(tester, size: const Size(640, 300));
      expect(tester.takeException(), isNull);
    });
  });

  group('picker and settings', () {
    testWidgets('the preview paints and the picker shows it', (tester) async {
      await _pump(tester, host: _Host.picker, settings: SettingsState());
      expect(find.byType(CassetteLayoutPreview), findsOneWidget);
      expect(find.text('Cassette deck'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the preview fits in every look, light and dark', (
      tester,
    ) async {
      for (final appearance in WvAppearance.values) {
        for (final dark in [false, true]) {
          await _pump(
            tester,
            host: _Host.picker,
            dark: dark,
            appearance: appearance,
            size: const Size(320, 640),
            settings: SettingsState(),
          );
          expect(find.byType(CassetteLayoutPreview), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('choosing it in the picker saves the choice', (tester) async {
      await _pump(
        tester,
        host: _Host.picker,
        settings: SettingsState(),
        size: const Size(411, 1600),
      );
      await tester.tap(find.text('Cassette deck'));
      await tester.pump();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(PlayerLayoutPicker)),
      );
      expect(
        c.read(settingsProvider).playerLayout,
        PlayerLayout.cassette.index,
      );
    });

    testWidgets('the sheet shows the cassette deck when it is chosen', (
      tester,
    ) async {
      await _pump(tester, host: _Host.sheet);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(FullPlayerSheet)),
      );
      await c
          .read(playerProvider.notifier)
          .playSong(_songs[1], contextList: _songs);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CassetteLayout), findsOneWidget);
      expect(find.text('Track 2'), findsWidgets);
    });
  });
}
