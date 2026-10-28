import 'dart:async';
import 'dart:math' as math;

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
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/playback/visualizer_math.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/providers/visualizer_provider.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/aqua_visualizer.dart';

import 'helpers/fake_engine.dart';
import 'helpers/fake_player.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
  void put(SettingsState s) => state = s;
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

/// Lets the notifier's async work finish inside a widget test, where the
/// fake clock does not run stream cancellation.
Future<void> _flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
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

  group('band math', () {
    test('a silent frame is flat and a loud bin lights the right band', () {
      expect(fftToBands(List.filled(1024, 0)).every((v) => v == 0), isTrue);

      final fft = List<int>.filled(1024, 0);
      // Loud tone in bin 40 of 512 (log-spaced, so a middle band).
      fft[80] = 100;
      fft[81] = 60;
      final bands = fftToBands(fft);
      expect(bands.length, kVisualizerBands);
      final top = bands.indexOf(bands.reduce(math.max));
      expect(top, greaterThan(8));
      expect(top, lessThan(24));
      expect(bands[top], greaterThan(0.5));
      expect(bands.first, 0);
      expect(bands.last, 0);
    });

    test('values stay in 0..1 and unsigned bytes read as signed', () {
      final loud = List<int>.filled(1024, 255); // -1 as signed
      for (final v in fftToBands(loud)) {
        expect(v, inInclusiveRange(0, 1));
      }
      final fft = List<int>.filled(1024, 0)..[80] = 0xE0; // -32
      expect(
        fftToBands(fft).reduce(math.max),
        fftToBands(List<int>.filled(1024, 0)..[80] = 32).reduce(math.max),
      );
    });

    test('normalizing is monotonic and clamped', () {
      expect(normalizeMagnitude(0), 0);
      expect(normalizeMagnitude(1e6), 1);
      expect(normalizeMagnitude(40), greaterThan(normalizeMagnitude(10)));
      expect(
        normalizeMagnitude(10, tiltDb: 10),
        greaterThan(normalizeMagnitude(10)),
      );
    });

    test('too short a frame gives silence, not an error', () {
      expect(fftToBands([1, 2, 3]), List.filled(kVisualizerBands, 0.0));
    });

    test('smoothing rises fast and falls slowly', () {
      final up = smoothBands([0, 0], [1, 1], attack: 0.7, decay: 0.2);
      expect(up, [0.7, 0.7]);
      final down = smoothBands([1, 0.5], [0, 0.5], attack: 0.7, decay: 0.2);
      expect(down[0], closeTo(0.8, 1e-9));
      expect(down[1], 0.5);
      // Missing history counts as silence; input is clamped.
      expect(smoothBands(const [], [2.0], attack: 1), [1.0]);
    });

    test('peak caps jump up, fall slowly and never sit below the bar', () {
      var peaks = updatePeaks(const [], [0.6]);
      expect(peaks, [0.6]);
      peaks = updatePeaks(peaks, [0.1], fall: 0.1);
      expect(peaks[0], closeTo(0.5, 1e-9));
      peaks = updatePeaks(peaks, [0.9], fall: 0.1);
      expect(peaks[0], 0.9);
      expect(updatePeaks([0.0], [0.3])[0], 0.3);
    });

    test('the still frame is quiet', () {
      final still = stillBands();
      expect(still.length, kVisualizerBands);
      expect(still.every((v) => v > 0 && v < 0.35), isTrue);
    });
  });

  group('notifier', () {
    late _Channel channel;
    late StreamController<int?> session;
    late StateProvider<bool> playing;
    late ProviderContainer c;
    late _Settings settings;

    Future<void> build({
      bool enabled = true,
      StorageAccess access = StorageAccess.granted,
    }) async {
      channel = _Channel()..access = access;
      session = StreamController<int?>.broadcast();
      playing = StateProvider<bool>((ref) => true);
      c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () =>
                settings = _Settings(SettingsState(enableVisualizer: enabled)),
          ),
          visualizerChannelProvider.overrideWithValue(channel),
          visualizerSessionProvider.overrideWith((ref) => session.stream),
          visualizerPlayingProvider.overrideWith((ref) => ref.watch(playing)),
        ],
      );
      c.listen(visualizerProvider, (_, _) {});
      c.listen(visualizerSessionProvider, (_, _) {});
      session.add(7);
      await _settle();
    }

    tearDown(() async {
      c.dispose();
      await session.close();
    });

    test('starts when visible and playing, and reports running', () async {
      await build();
      expect(channel.calls, isEmpty); // not visible yet
      c.read(visualizerProvider.notifier).setVisible(true);
      await _settle();
      expect(channel.calls, ['start:7']);
      expect(c.read(visualizerProvider).status, VisualizerStatus.running);
    });

    test('frames are smoothed into bands and peaks', () async {
      await build();
      c.read(visualizerProvider.notifier).setVisible(true);
      await _settle();
      channel.controller.add([1.0, 0.0]);
      var s = c.read(visualizerProvider);
      expect(s.bands[0], closeTo(0.7, 1e-9));
      expect(s.peaks[0], closeTo(0.7, 1e-9));
      channel.controller.add([0.0, 0.0]);
      s = c.read(visualizerProvider);
      expect(s.bands[0], closeTo(0.56, 1e-9));
      expect(s.peaks[0], greaterThanOrEqualTo(s.bands[0]));
    });

    test('stops when hidden and starts again when shown', () async {
      await build();
      final n = c.read(visualizerProvider.notifier);
      n.setVisible(true);
      await _settle();
      n.setVisible(false);
      await _settle();
      expect(channel.calls, ['start:7', 'stop']);
      n.setVisible(true);
      await _settle();
      expect(channel.calls, ['start:7', 'stop', 'start:7']);
    });

    test('stops on pause and resumes on play', () async {
      await build();
      c.read(visualizerProvider.notifier).setVisible(true);
      await _settle();
      channel.controller.add([1.0]);
      c.read(playing.notifier).state = false;
      await _settle();
      expect(channel.calls, ['start:7', 'stop']);
      expect(c.read(visualizerProvider).bands, isEmpty);
      expect(c.read(visualizerProvider).status, VisualizerStatus.running);
      // Frames that arrive after the stop are ignored.
      channel.controller.add([1.0]);
      expect(c.read(visualizerProvider).bands, isEmpty);
      c.read(playing.notifier).state = true;
      await _settle();
      expect(channel.calls.last, 'start:7');
    });

    test('stops when the setting is turned off', () async {
      await build();
      c.read(visualizerProvider.notifier).setVisible(true);
      await _settle();
      settings.put(const SettingsState(enableVisualizer: false));
      await _settle();
      expect(channel.calls, ['start:7', 'stop']);
      expect(c.read(visualizerProvider).status, VisualizerStatus.off);
    });

    test('does nothing while the setting is off', () async {
      await build(enabled: false);
      c.read(visualizerProvider.notifier).setVisible(true);
      await _settle();
      expect(channel.calls, isEmpty);
      expect(c.read(visualizerProvider).status, VisualizerStatus.off);
    });

    test('re-attaches when the audio session changes', () async {
      await build();
      c.read(visualizerProvider.notifier).setVisible(true);
      await _settle();
      session.add(9);
      await _settle();
      expect(channel.calls, ['start:7', 'stop', 'start:9']);
      // The same id again changes nothing.
      session.add(9);
      await _settle();
      expect(channel.calls.length, 3);
    });

    test('a failing start means unavailable', () async {
      await build();
      channel.startError = PlatformException(code: 'visualizer_unavailable');
      c.read(visualizerProvider.notifier).setVisible(true);
      await _settle();
      expect(c.read(visualizerProvider).status, VisualizerStatus.unavailable);
      expect(channel.calls, ['start:7', 'stop']); // and no retry loop
    });

    test(
      'a missing permission means needsPermission, then grant works',
      () async {
        await build(access: StorageAccess.denied);
        final n = c.read(visualizerProvider.notifier);
        n.setVisible(true);
        await _settle();
        expect(channel.calls, isEmpty);
        expect(
          c.read(visualizerProvider).status,
          VisualizerStatus.needsPermission,
        );
        expect(c.read(visualizerProvider).blocked, isFalse);

        await n.grantPermission();
        await _settle();
        expect(channel.calls, ['start:7']);
        expect(c.read(visualizerProvider).status, VisualizerStatus.running);
      },
    );

    test('a permanent refusal is blocked and points to Settings', () async {
      await build(access: StorageAccess.blocked);
      final n = c.read(visualizerProvider.notifier);
      n.setVisible(true);
      await _settle();
      final s = c.read(visualizerProvider);
      expect(s.status, VisualizerStatus.needsPermission);
      expect(s.blocked, isTrue);
      await n.openSystemSettings();
      expect(channel.calls, ['settings']);
    });

    test(
      'the native side reporting a permission error is needsPermission',
      () async {
        await build();
        channel.startError = PlatformException(code: 'permission');
        c.read(visualizerProvider.notifier).setVisible(true);
        await _settle();
        expect(
          c.read(visualizerProvider).status,
          VisualizerStatus.needsPermission,
        );
      },
    );

    test('a stream error means unavailable and releases it', () async {
      await build();
      c.read(visualizerProvider.notifier).setVisible(true);
      await _settle();
      channel.controller.addError(PlatformException(code: 'boom'));
      await _settle();
      expect(c.read(visualizerProvider).status, VisualizerStatus.unavailable);
      expect(channel.calls.last, 'stop');
    });

    test('disposing releases the native visualizer', () async {
      await build();
      c.read(visualizerProvider.notifier).setVisible(true);
      await _settle();
      c.dispose();
      expect(channel.calls.last, 'stop');
      // tearDown disposes again; make that harmless.
      c = ProviderContainer();
    });
  });

  group('AquaVisualizer', () {
    Widget host({
      required Size size,
      bool dark = false,
      double scale = 1,
      bool still = false,
      List<double> bands = const [],
      List<double> peaks = const [],
    }) => MaterialApp(
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
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: size,
            child: AquaVisualizer(bands: bands, peaks: peaks),
          ),
        ),
      ),
    );

    final loud = [for (var i = 0; i < kVisualizerBands; i++) i / 31];

    for (final size in const [Size(40, 40), Size(200, 120), Size(400, 300)]) {
      for (final dark in [false, true]) {
        testWidgets('paints at $size, dark $dark, 1.5x', (tester) async {
          await tester.pumpWidget(
            host(size: size, dark: dark, scale: 1.5, bands: loud, peaks: loud),
          );
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
          expect(find.byType(CustomPaint), findsWidgets);
        });
      }
    }

    testWidgets('paints with no levels and with a different bar count', (
      tester,
    ) async {
      await tester.pumpWidget(host(size: const Size(200, 100)));
      await tester.pump();
      await tester.pumpWidget(
        host(size: const Size(200, 100), bands: const [0.5, 1.0]),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion draws one still frame and no ticker', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(size: const Size(200, 120), still: true, bands: loud),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Nothing keeps scheduling frames.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the easing settles instead of animating forever', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(size: const Size(200, 120), bands: loud, peaks: loud),
      );
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('player sheet page', () {
    final songs = [for (var i = 1; i <= 3; i++) testSong(i, albumId: 100)];

    Future<ProviderContainer> open(
      WidgetTester tester, {
      required bool enabled,
      _Channel? channel,
    }) async {
      tester.view.physicalSize = const Size(411, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = channel ?? _Channel();
      final player = MemoryPlayer();
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
            settingsProvider.overrideWith(
              () => _Settings(SettingsState(enableVisualizer: enabled)),
            ),
            ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
            downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
            visualizerChannelProvider.overrideWithValue(fake),
            visualizerSessionProvider.overrideWith(
              (ref) => Stream<int?>.value(5),
            ),
            visualizerPlayingProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: WavvyTheme.light(WvAppearance.aqua),
            home: const FullPlayerSheet(),
          ),
        ),
      );
      final c = ProviderScope.containerOf(
        tester.element(find.byType(FullPlayerSheet)),
      );
      await c
          .read(playerProvider.notifier)
          .playSong(songs[1], contextList: songs);
      await tester.pump();
      await tester.pump();
      return c;
    }

    testWidgets('has no visualizer tab when the setting is off', (
      tester,
    ) async {
      await open(tester, enabled: false);
      expect(find.byTooltip('Visualizer'), findsNothing);
      expect(find.byTooltip('About'), findsOneWidget);
    });

    testWidgets('adds the tab last when on, and runs only while it shows', (
      tester,
    ) async {
      final channel = _Channel();
      await open(tester, enabled: true, channel: channel);
      expect(find.byTooltip('Visualizer'), findsOneWidget);
      await tester.pump();
      expect(channel.calls, isEmpty); // another page is showing

      await tester.tap(find.byTooltip('Visualizer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(find.byType(AquaVisualizer), findsOneWidget);
      expect(channel.calls, ['start:5']);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Player'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(channel.calls, ['start:5', 'stop']);
    });

    testWidgets('offers Grant permission when it is missing', (tester) async {
      final channel = _Channel()..access = StorageAccess.denied;
      await open(tester, enabled: true, channel: channel);
      await tester.tap(find.byTooltip('Visualizer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(find.text('Grant permission'), findsOneWidget);
      await tester.tap(find.text('Grant permission'));
      await _flush(tester);
      await _flush(tester);
      expect(find.text('Grant permission'), findsNothing);
      expect(channel.calls, contains('start:5'));
    });

    testWidgets('says so when the device has no visualizer', (tester) async {
      final channel = _Channel()
        ..startError = PlatformException(code: 'visualizer_unavailable');
      await open(tester, enabled: true, channel: channel);
      await tester.tap(find.byTooltip('Visualizer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      await _flush(tester);
      expect(find.text('Visualizer unavailable'), findsOneWidget);
    });
  });
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
