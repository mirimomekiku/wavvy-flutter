import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/player_sheets/layouts/hifi_jog.dart';
import 'package:wavvy/player_sheets/layouts/hifi_layout.dart';
import 'package:wavvy/player_sheets/layouts/hifi_meters.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/downloader/flavor.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/playback/visualizer_math.dart';
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
  final calls = <String>[];
  // ignore: close_sinks
  final controller = StreamController<List<double>>.broadcast(sync: true);
  StorageAccess access = StorageAccess.granted;
  Object? startError;

  @override
  Future<void> start(int sessionId, {int bands = kVisualizerBands}) async {
    calls.add('start:$sessionId');
    if (startError != null) throw startError!;
  }

  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Stream<List<double>> frames() => controller.stream;
  @override
  Future<StorageAccess> permission({bool request = false}) async {
    if (request && access == StorageAccess.denied) {
      access = StorageAccess.granted;
    }
    return access;
  }

  @override
  Future<void> openSettings() async => calls.add('settings');
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

/// Lets the notifier's async work finish inside a widget test.
Future<void> _flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

final _songs = [for (var i = 1; i <= 3; i++) testSong(i, albumId: 100)];

class _Rig {
  _Rig(this.player, this.channel);
  final MemoryPlayer player;
  final _Channel channel;
}

enum _Host { layout, sheet, picker }

Future<_Rig> _pump(
  WidgetTester tester, {
  Size size = const Size(411, 900),
  double scale = 1,
  bool dark = false,
  WvAppearance appearance = WvAppearance.aqua,
  SettingsState? settings,
  _Channel? channel,
  _Host host = _Host.layout,
  bool reduced = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = channel ?? _Channel();
  final player = MemoryPlayer();
  final data = PlayerLayoutData(song: _songs[0], onLyrics: () {});
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
            settings ?? SettingsState(playerLayout: PlayerLayout.hifi.index),
          ),
        ),
        ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
        downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
        visualizerChannelProvider.overrideWithValue(fake),
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
          _Host.sheet => const FullPlayerSheet(),
          _Host.picker => const Scaffold(body: PlayerLayoutPicker()),
        },
      ),
    ),
  );
  await tester.pump();
  await _flush(tester);
  return _Rig(player, fake);
}

List<HifiMeterPainter> _meters(WidgetTester tester) => [
  for (final p in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
    if (p.painter is HifiMeterPainter) p.painter! as HifiMeterPainter,
];

/// Low bands loud, high bands quiet.
List<double> get _bassHeavy => [
  for (var i = 0; i < kVisualizerBands; i++) i < 8 ? 0.9 : 0.05,
];

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
    test('needle angle follows the level, within the sweep', () {
      expect(hifiNeedleAngle(0.5), closeTo(-1.5707963, 1e-6));
      expect(hifiNeedleAngle(0) < hifiNeedleAngle(0.5), isTrue);
      expect(hifiNeedleAngle(1) > hifiNeedleAngle(0.5), isTrue);
      expect(hifiNeedleAngle(7), hifiNeedleAngle(1));
      expect(hifiNeedleAngle(-3), hifiNeedleAngle(0));
    });

    test('band levels: bass from the low end, treble from the high end', () {
      final l = hifiBandLevels(_bassHeavy);
      expect(l.bass, greaterThan(0.8));
      expect(l.treble, lessThan(0.1));
      final none = hifiBandLevels(const []);
      expect(none.bass, 0);
      expect(none.treble, 0);
    });

    test('the spring approaches its target, overshoots a little, settles', () {
      var x = 0.0, v = 0.0;
      var peak = 0.0;
      for (var i = 0; i < 600; i++) {
        final s = hifiSpringStep(x, v, 1, 1 / 60);
        x = s.x;
        v = s.v;
        if (x > peak) peak = x;
      }
      expect(peak, greaterThan(1));
      expect(peak, lessThan(1.25));
      expect(x, closeTo(1, 0.001));
      // One short frame moves it only part of the way.
      expect(hifiSpringStep(0, 0, 1, 1 / 60).x, lessThan(0.2));
    });

    test('a turn across the left edge is short, not a full circle', () {
      expect(jogDelta(3.0, -3.0), closeTo(2 * 3.141592653589793 - 6, 1e-9));
      expect(jogDelta(-3.0, 3.0), lessThan(0));
      expect(jogDelta(0, 1), 1);
    });
  });

  group('layout', () {
    testWidgets('shows the song, its times and the transport', (tester) async {
      await _pump(tester);
      expect(find.byType(HifiLayout), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
      expect(find.text('0:50'), findsWidgets);
      expect(find.text('-2:10'), findsOneWidget);
      expect(find.byTooltip('Previous'), findsOneWidget);
      expect(find.byTooltip('Next'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byTooltip('View lyrics'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the shared seek row and extras still work', (tester) async {
      final rig = await _pump(tester);
      await tester.ensureVisible(find.byTooltip('Forward 15 seconds'));
      await tester.tap(find.byTooltip('Forward 15 seconds'));
      await tester.pump();
      expect(rig.player.seeks.last, const Duration(seconds: 65));
      // The shared seek bar below the wheel seeks to where it is tapped.
      final bar = find.byType(AquaSeekBar);
      expect(bar, findsOneWidget);
      await tester.ensureVisible(bar);
      await tester.tapAt(tester.getCenter(bar));
      await tester.pump();
      expect(rig.player.seeks.last.inSeconds, closeTo(90, 3));
      expect(find.byKey(const Key('ab_loop')), findsOneWidget);
    });

    testWidgets('transport buttons drive the player', (tester) async {
      final rig = await _pump(tester, host: _Host.sheet);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(FullPlayerSheet)),
      );
      await c
          .read(playerProvider.notifier)
          .playSong(_songs[1], contextList: _songs);
      await tester.pump();
      await tester.pump();
      expect(find.byType(HifiLayout), findsOneWidget);
      expect(find.text('Track 2'), findsWidgets);
      final before = _handler.plays + _handler.pauses;
      final toggle = find.byTooltip('Play').evaluate().isNotEmpty
          ? find.byTooltip('Play')
          : find.byTooltip('Pause');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(_handler.plays + _handler.pauses, before + 1);
      expect(rig.player.sources, isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('meters', () {
    testWidgets('follow the bass and treble bands and ease toward them', (
      tester,
    ) async {
      final channel = _Channel();
      await _pump(
        tester,
        settings: SettingsState(
          playerLayout: PlayerLayout.hifi.index,
          enableVisualizer: true,
        ),
        channel: channel,
      );
      expect(channel.calls, ['start:5']); // on while the layout shows
      expect(find.text('BASS'), findsOneWidget);
      expect(find.text('TREBLE'), findsOneWidget);
      expect(find.text('ELAPSED'), findsNothing);
      expect(_meters(tester).map((m) => m.level), [0, 0]);

      for (var i = 0; i < 6; i++) {
        channel.controller.add(_bassHeavy);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final early = _meters(tester).map((m) => m.level).toList();
      // Moving, but not there yet: the needle is on a spring.
      expect(early[0], greaterThan(0));
      expect(early[0], lessThan(0.6));

      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      final late = _meters(tester).map((m) => m.level).toList();
      expect(late[0], greaterThan(0.7));
      expect(late[1], lessThan(0.15));
      expect(late[0], greaterThan(late[1]));
      expect(hifiNeedleAngle(late[0]), greaterThan(hifiNeedleAngle(late[1])));
    }, skip: !kVisualizerAvailable);

    testWidgets('leaving the layout releases the visualizer', (tester) async {
      final channel = _Channel();
      await _pump(
        tester,
        settings: SettingsState(
          playerLayout: PlayerLayout.hifi.index,
          enableVisualizer: true,
        ),
        channel: channel,
      );
      expect(channel.calls, ['start:5']);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(channel.calls.last, 'stop');
    }, skip: !kVisualizerAvailable);

    testWidgets(
      'time gauges when the setting is off, with a Live meters button',
      (tester) async {
        final channel = _Channel();
        await _pump(tester, channel: channel);
        expect(find.text('ELAPSED'), findsOneWidget);
        expect(find.text('REMAINING'), findsOneWidget);
        expect(find.text('BASS'), findsNothing);
        // Only the full build has a visualizer to offer.
        expect(
          find.text('Live meters'),
          kVisualizerAvailable ? findsOneWidget : findsNothing,
        );
        expect(channel.calls, isEmpty);
        final levels = _meters(tester).map((m) => m.level).toList();
        expect(levels[0], closeTo(50 / 180, 0.001));
        expect(levels[1], closeTo(130 / 180, 0.001));
      },
    );

    testWidgets('the Live meters button runs the enable flow', (tester) async {
      final channel = _Channel();
      await _pump(tester, channel: channel);
      await tester.ensureVisible(find.text('Live meters'));
      await tester.tap(find.text('Live meters'));
      await _flush(tester);
      await _flush(tester);
      expect(find.text('BASS'), findsOneWidget);
      expect(find.text('Live meters'), findsNothing);
      expect(tester.takeException(), isNull);
    }, skip: !kVisualizerAvailable);

    testWidgets('gauges again when the device cannot give levels', (
      tester,
    ) async {
      final channel = _Channel()
        ..startError = PlatformException(code: 'unsupported');
      await _pump(
        tester,
        settings: SettingsState(
          playerLayout: PlayerLayout.hifi.index,
          enableVisualizer: true,
        ),
        channel: channel,
      );
      await _flush(tester);
      expect(find.text('ELAPSED'), findsOneWidget);
      expect(find.text('BASS'), findsNothing);
      expect(find.text('Live meters'), findsNothing);
    });

    testWidgets('gauges and a permission button when the permission is gone', (
      tester,
    ) async {
      final channel = _Channel()..access = StorageAccess.denied;
      await _pump(
        tester,
        settings: SettingsState(
          playerLayout: PlayerLayout.hifi.index,
          enableVisualizer: true,
        ),
        channel: channel,
      );
      await _flush(tester);
      expect(find.text('ELAPSED'), findsOneWidget);
      expect(find.text('Allow meters'), findsOneWidget);
      await tester.ensureVisible(find.text('Allow meters'));
      await tester.tap(find.text('Allow meters'));
      await _flush(tester);
      await _flush(tester);
      expect(find.text('BASS'), findsOneWidget);
    }, skip: !kVisualizerAvailable);

    testWidgets('the Play build has only the time gauges', (tester) async {
      final channel = _Channel();
      await _pump(
        tester,
        settings: SettingsState(
          playerLayout: PlayerLayout.hifi.index,
          enableVisualizer: true,
        ),
        channel: channel,
      );
      await _flush(tester);
      if (kVisualizerAvailable) {
        expect(find.text('BASS'), findsOneWidget);
      } else {
        expect(find.text('ELAPSED'), findsOneWidget);
        expect(find.text('BASS'), findsNothing);
        expect(find.text('Live meters'), findsNothing);
        expect(channel.calls, isEmpty);
      }
    });

    testWidgets('reduced motion: the needle jumps', (tester) async {
      final channel = _Channel();
      await _pump(
        tester,
        reduced: true,
        settings: SettingsState(
          playerLayout: PlayerLayout.hifi.index,
          enableVisualizer: true,
        ),
        channel: channel,
      );
      for (var i = 0; i < 6; i++) {
        channel.controller.add(_bassHeavy);
      }
      await tester.pump();
      final target = hifiBandLevels(
        ProviderScope.containerOf(
          tester.element(find.byType(HifiLayout)),
        ).read(visualizerProvider).bands,
      );
      await tester.pump();
      expect(_meters(tester)[0].level, closeTo(target.bass, 1e-9));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }, skip: !kVisualizerAvailable);
  });

  group('jog wheel', () {
    testWidgets('has slider semantics and steps by 5 seconds', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _pump(tester);
      final wheel = find.bySemanticsLabel('Jog wheel, seek');
      expect(wheel, findsOneWidget);
      final data = tester.getSemantics(wheel);
      expect(data.flagsCollection.isSlider, isTrue);
      expect(data.value, '0:50 of 3:00');
      expect(data.increasedValue, '0:55');
      expect(data.decreasedValue, '0:45');
      tester.semantics.performAction(
        find.semantics.byLabel("Jog wheel, seek"),
        SemanticsAction.increase,
      );
      await tester.pump();
      expect(rig.player.seeks.last, const Duration(seconds: 55));
      tester.semantics.performAction(
        find.semantics.byLabel("Jog wheel, seek"),
        SemanticsAction.decrease,
      );
      await tester.pump();
      expect(rig.player.seeks.last, const Duration(seconds: 45));
      handle.dispose();
    });

    testWidgets('dragging around turns it and seeks once, on release', (
      tester,
    ) async {
      final rig = await _pump(tester);
      final wheel = find.byType(HifiJogWheel);
      await tester.ensureVisible(wheel);
      await tester.pump();
      final center = tester.getCenter(wheel);
      final r = tester.getSize(wheel).width * 0.4;
      final g = await tester.startGesture(center + Offset(r, 0));
      await tester.pump();
      // A quarter turn clockwise (right, then down) is a quarter minute.
      await g.moveTo(center + Offset(r * 0.7, r * 0.7));
      await g.moveTo(center + Offset(0, r));
      await tester.pump();
      expect(rig.player.seeks, isEmpty); // nothing native while dragging
      await g.up();
      await tester.pump();
      expect(rig.player.seeks, hasLength(1));
      expect(rig.player.seeks.single.inMilliseconds, closeTo(65000, 400));
      // The painted knob moved with the finger, not back.
      expect(tester.takeException(), isNull);
    });

    testWidgets('a touch without turning does not seek', (tester) async {
      final rig = await _pump(tester);
      final wheel = find.byType(HifiJogWheel);
      await tester.ensureVisible(wheel);
      await tester.tap(wheel);
      await tester.pump();
      expect(rig.player.seeks, isEmpty);
    });

    testWidgets('turning backwards past the start stops at zero', (
      tester,
    ) async {
      final rig = await _pump(tester);
      final wheel = find.byType(HifiJogWheel);
      await tester.ensureVisible(wheel);
      final center = tester.getCenter(wheel);
      final r = tester.getSize(wheel).width * 0.4;
      final g = await tester.startGesture(center + Offset(r, 0));
      // Three quarter turns counter-clockwise, in steps: 45 s back from 50 s.
      for (final p in [
        Offset(0, -r),
        Offset(-r, 0),
        Offset(0, r),
        Offset(r, 0),
        Offset(0, -r),
      ]) {
        await g.moveTo(center + p);
      }
      await g.up();
      await tester.pump();
      expect(rig.player.seeks.single, Duration.zero);
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
                settings: SettingsState(
                  playerLayout: PlayerLayout.hifi.index,
                  enableVisualizer: scale == 2.0,
                ),
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '${appearance.name} dark=$dark $size x$scale',
              );
              expect(find.byType(HifiLayout), findsOneWidget);
              // Whatever does not fit scrolls rather than clips.
              await tester.drag(
                find.byType(HifiLayout),
                const Offset(0, -2000),
              );
              await tester.pump();
              expect(tester.takeException(), isNull);
            }
          }
        }
      });
    }

    testWidgets('a tablet width', (tester) async {
      await _pump(tester, size: const Size(900, 700));
      expect(tester.takeException(), isNull);
    });
  });

  group('picker and settings', () {
    testWidgets('the preview paints and the picker shows it', (tester) async {
      await _pump(tester, host: _Host.picker, settings: SettingsState());
      expect(find.byType(HifiLayoutPreview), findsOneWidget);
      expect(find.text('Hi-Fi deck'), findsOneWidget);
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
          expect(find.byType(HifiLayoutPreview), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('choosing it in the picker saves the choice', (tester) async {
      await _pump(tester, host: _Host.picker, settings: SettingsState());
      await tester.tap(find.text('Hi-Fi deck'));
      await tester.pump();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(PlayerLayoutPicker)),
      );
      expect(c.read(settingsProvider).playerLayout, PlayerLayout.hifi.index);
    });

    testWidgets('the sheet shows the Hi-Fi deck when it is chosen', (
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
      expect(find.byType(HifiLayout), findsOneWidget);
      expect(find.text('Track 2'), findsWidgets);
    });
  });
}
