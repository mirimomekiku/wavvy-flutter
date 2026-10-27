import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/media_store.dart';
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/startup/startup_failure.screen.dart';
import 'package:wavvy/theme/aqua_widgets.dart';

class _FakeChannel extends NativeEffectsChannel {
  EffectSupport support = const EffectSupport();
  bool failBass = false;
  final calls = <String>[];

  @override
  Future<EffectSupport> initEffects(int sessionId) async {
    calls.add('init:$sessionId');
    return support;
  }

  @override
  Future<void> setBassBoost(int strength) async {
    calls.add('bass:$strength');
    if (failBass) throw PlatformException(code: 'effect_unavailable');
  }

  @override
  Future<void> setVirtualizer(int strength) async =>
      calls.add('virt:$strength');

  @override
  Future<void> setReverb(String preset) async => calls.add('reverb:$preset');
}

class _FakeMediaStore extends MediaStoreChannel {
  _FakeMediaStore(this.deleted);
  final bool deleted;
  @override
  Future<bool> deleteAudio(int id) async => deleted;
}

class _NoopPlayer extends Fake implements audio.AudioPlayer {
  @override
  Stream<audio.PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<audio.SequenceState> get sequenceStateStream => const Stream.empty();
}

class _FakeLibrary extends LibraryNotifier {
  @override
  LibraryState build() => const LibraryState();
  @override
  Future<void> fetchAllSongs({bool silent = false}) async {}
}

Widget _app(Widget child, {bool dark = false, double scale = 1}) => MaterialApp(
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('startup failure advice', () {
    test('names the Android service restriction', () {
      final advice = describeStartupFailure(
        PlatformException(
          code: 'x',
          message: 'ForegroundServiceStartNotAllowedException',
        ),
      );
      expect(advice.summary, contains('playback service'));
      expect(advice.steps.join(' '), contains('Battery'));
    });
    test('names a busy audio session', () {
      final advice = describeStartupFailure(
        StateError('AudioSession configure failed'),
      );
      expect(advice.summary, contains('busy'));
    });
    test('falls back to general steps', () {
      final advice = describeStartupFailure(Exception('boom'));
      expect(advice.steps, isNotEmpty);
      expect(advice.steps.first, contains('Try Again'));
    });
  });

  group('startup failure screen', () {
    for (final dark in [false, true]) {
      testWidgets('renders at 320 wide with large text (dark: $dark)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(
            StartupFailureScreen(
              error: Exception('boom'),
              onRetry: () async {},
              onRestart: () async {},
            ),
            dark: dark,
            scale: 1.5,
          ),
        );
        expect(find.text('Playback could not start'), findsOneWidget);
        expect(find.text('Try Again'), findsOneWidget);
        expect(find.text('Restart Wavvy'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Try Again shows progress and runs the retry', (tester) async {
      var retries = 0;
      final done = Completer<void>();
      await tester.pumpWidget(
        _app(
          StartupFailureScreen(
            error: Exception('boom'),
            onRetry: () {
              retries++;
              return done.future;
            },
            onRestart: () async {},
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('startup_retry')));
      await tester.pump();
      expect(retries, 1);
      expect(find.byType(AquaSpinner), findsOneWidget);
      // Both buttons are disabled while retrying.
      await tester.tap(find.byKey(const Key('startup_retry')));
      await tester.pump();
      expect(retries, 1);
      done.complete();
      await tester.pump();
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('Restart Wavvy calls the restart hook', (tester) async {
      var restarted = false;
      await tester.pumpWidget(
        _app(
          StartupFailureScreen(
            error: Exception('boom'),
            onRetry: () async {},
            onRestart: () async => restarted = true,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('startup_restart')));
      await tester.pump();
      expect(restarted, isTrue);
    });

    testWidgets('Details reveals the raw error', (tester) async {
      await tester.pumpWidget(
        _app(
          StartupFailureScreen(
            error: Exception('very specific failure'),
            onRetry: () async {},
            onRestart: () async {},
          ),
        ),
      );
      expect(find.textContaining('very specific failure'), findsNothing);
      await tester.tap(find.byKey(const Key('startup_details_toggle')));
      await tester.pump();
      expect(find.textContaining('very specific failure'), findsOneWidget);
    });
  });

  group('native effects', () {
    late _FakeChannel channel;
    late ProviderContainer container;
    setUp(() {
      channel = _FakeChannel();
      container = ProviderContainer(
        overrides: [nativeEffectsChannelProvider.overrideWithValue(channel)],
      );
    });
    tearDown(() => container.dispose());

    test('reports what the device supports', () async {
      channel.support = const EffectSupport(virtualizer: false);
      await container.read(effectsProvider.notifier).attachToSession(7);
      final state = container.read(effectsProvider);
      expect(state.support.bassBoost, isTrue);
      expect(state.support.virtualizer, isFalse);
    });

    test('puts the user\'s settings back on a new audio session', () async {
      final fx = container.read(effectsProvider.notifier);
      await fx.attachToSession(1);
      await fx.setBassBoost(0.5);
      await fx.setReverb('Plate');
      channel.calls.clear();

      await fx.attachToSession(2);
      expect(channel.calls, ['init:2', 'bass:500', 'reverb:Plate']);
      expect(container.read(effectsProvider).bassBoostStrength, 500);
    });

    test('a rejected effect is switched off and reported', () async {
      channel.failBass = true;
      await container.read(effectsProvider.notifier).setBassBoost(0.8);
      final state = container.read(effectsProvider);
      expect(state.isBassBoostEnabled, isFalse);
      expect(state.bassBoostStrength, 0);
      expect(state.error, isNotEmpty);
    });

    test('reset switches every effect off', () async {
      final fx = container.read(effectsProvider.notifier);
      await fx.attachToSession(1);
      await fx.setBassBoost(1);
      await fx.setVirtualizer(1);
      await fx.resetAll();
      final state = container.read(effectsProvider);
      expect(state.bassBoostStrength, 0);
      expect(state.virtualizerStrength, 0);
      expect(state.currentReverbPreset, 'None');
    });
  });

  group('equalizer presets', () {
    test('use real decibel values', () {
      expect(EqualizerNotifier.presetGain('Bass Boost', 0, 5), 6);
      expect(EqualizerNotifier.presetGain('Treble', 4, 5), 6);
    });
    test('spread across devices with a different band count', () {
      expect(EqualizerNotifier.presetGain('Bass Boost', 0, 3), 6);
      expect(EqualizerNotifier.presetGain('Bass Boost', 2, 3), 0);
      expect(EqualizerNotifier.presetGain('Bass Boost', 0, 10), 6);
      expect(EqualizerNotifier.presetGain('Treble', 9, 10), 6);
      expect(EqualizerNotifier.presetGain('Flat', 3, 7), 0);
      // Halfway between the first two points of [6, 4, 0, 0, 0].
      expect(
        EqualizerNotifier.presetGain('Bass Boost', 1, 9),
        closeTo(5, 1e-9),
      );
    });
  });

  group('deleting a song (system prompt declined)', () {
    final songs = [
      for (var i = 1; i <= 2; i++)
        SongModel({
          '_id': i,
          '_data': '/music/$i.mp3',
          '_uri': 'content://media/$i',
          'title': 'Track $i',
        }),
    ];

    Future<ProviderContainer> start(bool deleted) async {
      final container = ProviderContainer(
        overrides: [
          mediaStoreProvider.overrideWithValue(_FakeMediaStore(deleted)),
          libraryProvider.overrideWith(_FakeLibrary.new),
          audioPlayerProvider.overrideWithValue(_NoopPlayer()),
        ],
      );
      return container;
    }

    test('a declined delete leaves playback state alone', () async {
      final container = await start(false);
      addTearDown(container.dispose);
      final player = container.read(playerProvider.notifier);
      await player.deleteSong(songs.first);
      // No audio source was ever loaded, so nothing was removed either way;
      // the point is that a declined delete doesn't throw or change state.
      expect(container.read(playerProvider).queue, isEmpty);
    });
  });
}
