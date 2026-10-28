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
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/player_sheets/layouts/cd_disc.dart';
import 'package:wavvy/player_sheets/layouts/cd_layout.dart';
import 'package:wavvy/player_sheets/layouts/cd_segment_display.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
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

class _Handler extends Fake implements WavvyAudioHandler {
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
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

final _songs = [for (var i = 1; i <= 3; i++) testSong(i, albumId: 100)];

const _longTitle =
    'An extremely long song title that will never fit on one line of a phone';

SongModel _longSong() => SongModel({
  '_id': 9,
  '_data': '/music/9.mp3',
  '_uri': 'content://media/9',
  'title': _longTitle,
  'artist': 'Artist',
  'duration': 180000,
});

enum _Host { layout, sheet, picker }

SettingsState get _cdSettings => SettingsState(
  playerLayout: PlayerLayout.cd.index,
  playerLayoutAdaptive: false,
);

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
  bool direct = false,
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
        settingsProvider.overrideWith(() => _Settings(settings ?? _cdSettings)),
        ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
        downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
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
          _Host.layout => Scaffold(
            body: direct ? CdLayout(data: data) : PlayerLayoutHost(data: data),
          ),
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

AnimationController _spin(WidgetTester tester) {
  final t = tester.widget<RotationTransition>(
    find.descendant(
      of: find.byType(CdDisc),
      matching: find.byType(RotationTransition),
    ),
  );
  return t.turns as AnimationController;
}

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

  group('segment math', () {
    test('digits light the right segments', () {
      expect(cdSegmentMask('0'), kSegA | kSegB | kSegC | kSegD | kSegE | kSegF);
      expect(cdSegmentMask('1'), kSegB | kSegC);
      expect(cdSegmentMask('7'), kSegA | kSegB | kSegC);
      expect(cdSegmentMask('8'), 127);
      expect(cdSegmentMask('9'), 127 & ~kSegE);
      expect(cdSegmentMask('6'), 127 & ~kSegB);
      expect(cdSegmentMask('-'), kSegG);
      expect(cdSegmentMask(':'), 0);
      expect(cdSegmentMask(' '), 0);
      expect(cdSegmentMask('ab'), 0);
      // Every digit is different, and 8 contains all of them.
      final masks = [for (var i = 0; i < 10; i++) cdSegmentMask('$i')];
      expect(masks.toSet(), hasLength(10));
      for (final m in masks) {
        expect(m & 127, m);
      }
    });

    test('times: mm:ss, h:mm:ss from an hour, zero, never negative', () {
      expect(cdTimeText(Duration.zero), '00:00');
      expect(cdTimeText(const Duration(seconds: 50)), '00:50');
      expect(cdTimeText(const Duration(minutes: 3, seconds: 5)), '03:05');
      expect(cdTimeText(const Duration(minutes: 59, seconds: 59)), '59:59');
      expect(cdTimeText(const Duration(hours: 1)), '1:00:00');
      expect(
        cdTimeText(const Duration(hours: 2, minutes: 3, seconds: 4)),
        '2:03:04',
      );
      expect(cdTimeText(const Duration(hours: 12, minutes: 59)), '12:59:00');
      expect(cdTimeText(const Duration(seconds: -4)), '00:00');
      expect(cdTimeText(const Duration(milliseconds: 999)), '00:00');
    });

    test(
      'track numbers: one-based out of the queue, padded, dashes if none',
      () {
        expect(cdTrackText(2, 12), '03/12');
        expect(cdTrackText(0, 3), '01/03');
        expect(cdTrackText(11, 12), '12/12');
        expect(cdTrackText(99, 120), '100/120');
        expect(cdTrackText(4, 100), '005/100');
        expect(cdTrackText(-1, 0), '--/--');
        expect(cdTrackText(-1, 5), '--/--');
        expect(cdTrackText(0, 0), '--/--');
      },
    );

    test('the text is as wide as its characters', () {
      expect(cdSegmentWidth('', 30), 0);
      expect(cdSegmentWidth('00:00', 30), greaterThan(cdSegmentWidth('0', 30)));
      expect(
        cdSegmentWidth('1:00:00', 30),
        greaterThan(cdSegmentWidth('00:00', 30)),
      );
    });
  });

  group('layout', () {
    testWidgets('shows the song, the time, the track and the transport', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(find.byType(CdLayout), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
      expect(find.bySemanticsLabel('Elapsed 0:50'), findsOneWidget);
      expect(find.bySemanticsLabel('No track'), findsOneWidget);
      expect(find.byTooltip('Previous'), findsOneWidget);
      expect(find.byTooltip('Next'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byTooltip('View lyrics'), findsOneWidget);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('built directly as well', (tester) async {
      await _pump(tester, direct: true);
      expect(find.byType(CdLayout), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
    });

    testWidgets('the artist opens About', (tester) async {
      var opened = 0;
      tester.view.physicalSize = const Size(411, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioPlayerProvider.overrideWithValue(MemoryPlayer()),
            audioHandlerProvider.overrideWithValue(_handler),
            positionProvider.overrideWith(_Position.new),
            durationProvider.overrideWith(_Duration.new),
            favoritesStoreProvider.overrideWithValue(_FavStore()),
          ],
          child: MaterialApp(
            theme: WavvyTheme.light(WvAppearance.aqua),
            home: Scaffold(
              body: CdLayout(
                data: PlayerLayoutData(
                  song: _songs[0],
                  onArtist: () => opened++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Artist'));
      expect(opened, 1);
      // No lyrics callback: no lyrics button.
      expect(find.byTooltip('View lyrics'), findsNothing);
    });

    testWidgets('the seek row and extras work', (tester) async {
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

    testWidgets('track number and lamps follow the player', (tester) async {
      final handle = tester.ensureSemantics();
      final player = await _pump(tester, host: _Host.sheet);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(FullPlayerSheet)),
      );
      await c
          .read(playerProvider.notifier)
          .playSong(_songs[1], contextList: _songs);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CdLayout), findsOneWidget);
      expect(find.text('Track 2'), findsWidgets);
      expect(find.bySemanticsLabel('Track 2 of 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Shuffle off'), findsOneWidget);
      expect(find.bySemanticsLabel('Repeat off'), findsOneWidget);
      await c.read(playerProvider.notifier).toggleShuffle();
      await c.read(playerProvider.notifier).cycleLoopMode();
      await tester.pump();
      // (The mode dock's tooltip says the same, so it is found twice.)
      expect(find.bySemanticsLabel('Shuffle on'), findsWidgets);
      expect(find.bySemanticsLabel('Shuffle off'), findsNothing);
      expect(find.bySemanticsLabel('Repeat on'), findsOneWidget);
      player.setPlaying(true);
      await tester.pump();
      expect(find.bySemanticsLabel('Playing'), findsOneWidget);
      expect(find.bySemanticsLabel('Paused'), findsNothing);
      player.setPlaying(false);
      await tester.pump();
      expect(find.bySemanticsLabel('Paused'), findsOneWidget);
      handle.dispose();
    });
  });

  group('disc', () {
    testWidgets('spins while playing, eases to a stop, goes on from there', (
      tester,
    ) async {
      final player = await _pump(tester);
      final spin = _spin(tester);
      expect(spin.isAnimating, isFalse);
      expect(spin.value, 0);

      player.setPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(spin.isAnimating, isTrue);
      final first = spin.value;
      expect(first, closeTo(0.5 / 3, 0.02)); // one turn takes 3 seconds
      await tester.pump(const Duration(milliseconds: 500));
      expect(spin.value, greaterThan(first));

      player.setPlaying(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(spin.isAnimating, isFalse);
      final stopped = spin.value;
      expect(stopped, greaterThan(first));
      await tester.pump(const Duration(seconds: 1));
      expect(spin.value, stopped);

      // Playing again goes on from the same angle, not from zero.
      player.setPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(spin.isAnimating, isTrue);
      expect(spin.value, closeTo(stopped + 0.05, 0.03));
    });

    testWidgets('the cover sits in a clipped circle in its own layer', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        find.descendant(
          of: find.byType(CdDisc),
          matching: find.byType(ClipOval),
        ),
        findsOneWidget,
      );
      final boundary = find.descendant(
        of: find.descendant(
          of: find.byType(CdDisc),
          matching: find.byType(RotationTransition),
        ),
        matching: find.byType(RepaintBoundary),
      );
      expect(boundary, findsWidgets);
    });

    testWidgets('reduced motion: static even while playing', (tester) async {
      final player = await _pump(tester, reduced: true);
      player.setPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final spin = _spin(tester);
      expect(spin.isAnimating, isFalse);
      expect(spin.value, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('stops when the page is not showing', (tester) async {
      final player = await _pump(tester);
      player.setPlaying(true);
      await tester.pump();
      expect(_spin(tester).isAnimating, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });

  group('marquee', () {
    testWidgets('a long title scrolls, a short one does not', (tester) async {
      await _pump(tester, size: const Size(320, 568), song: _longSong());
      await tester.pump();
      final text = tester.widget<Text>(find.text(_longTitle));
      expect(text.overflow, TextOverflow.visible);
      expect(text.softWrap, isFalse);
      expect(tester.binding.hasScheduledFrame, isTrue);
      final before = tester.getTopLeft(find.text(_longTitle)).dx;
      await tester.pump(const Duration(seconds: 3));
      expect(tester.getTopLeft(find.text(_longTitle)).dx, lessThan(before));
      expect(tester.takeException(), isNull);

      await _pump(tester);
      final short = tester.widget<Text>(find.text('Track 1'));
      expect(short.overflow, TextOverflow.ellipsis);
    });

    testWidgets('reduced motion: an ellipsis, nothing moving', (tester) async {
      await _pump(
        tester,
        size: const Size(320, 568),
        song: _longSong(),
        reduced: true,
      );
      await tester.pump();
      final text = tester.widget<Text>(find.text(_longTitle));
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
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
              await _pump(
                tester,
                size: size,
                scale: scale,
                dark: dark,
                appearance: appearance,
                song: scale == 2.0 ? _longSong() : null,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '${appearance.name} dark=$dark $size x$scale',
              );
              expect(find.byType(CdLayout), findsOneWidget);
              await tester.drag(find.byType(CdLayout), const Offset(0, -2000));
              await tester.pump();
              expect(tester.takeException(), isNull);
            }
          }
        }
      });
    }

    testWidgets('long tracks and a long queue still fit the display', (
      tester,
    ) async {
      await _pump(tester, size: const Size(320, 568), scale: 2);
      expect(tester.takeException(), isNull);
      await _pump(tester, size: const Size(900, 700), direct: true);
      expect(tester.takeException(), isNull);
    });
  });

  group('picker and settings', () {
    testWidgets('the preview paints and the picker shows it', (tester) async {
      await _pump(tester, host: _Host.picker, settings: SettingsState());
      expect(find.byType(CdLayoutPreview), findsOneWidget);
      expect(find.text('CD player'), findsOneWidget);
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
          expect(find.byType(CdLayoutPreview), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('the preview is registered', (tester) async {
      expect(kPlayerLayoutPreviews.containsKey(PlayerLayout.cd), isTrue);
      expect(kPlayerLayoutBuilders.containsKey(PlayerLayout.cd), isTrue);
    });

    testWidgets('choosing it in the picker saves the choice', (tester) async {
      await _pump(tester, host: _Host.picker, settings: SettingsState());
      await tester.ensureVisible(find.text('CD player'));
      await tester.pump();
      await tester.tap(find.text('CD player'));
      await tester.pump();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(PlayerLayoutPicker)),
      );
      expect(c.read(settingsProvider).playerLayout, PlayerLayout.cd.index);
    });

    testWidgets('the sheet shows the CD player when it is chosen', (
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
      expect(find.byType(CdLayout), findsOneWidget);
      expect(find.text('Track 2'), findsWidgets);
    });
  });
}
