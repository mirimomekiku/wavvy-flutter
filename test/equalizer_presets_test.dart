import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart'
    show AndroidEqualizer, AndroidEqualizerBand, AndroidEqualizerParameters;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/providers/player_provider.dart';

class _Band extends Fake implements AndroidEqualizerBand {
  _Band(this.centerFrequency);
  double _gain = 0;
  @override
  final double centerFrequency;
  @override
  double get gain => _gain;
  @override
  Future<void> setGain(double gain) async => _gain = gain;
}

class _Params extends Fake implements AndroidEqualizerParameters {
  _Params(this.bands);
  @override
  final List<AndroidEqualizerBand> bands;
  @override
  double get minDecibels => -15;
  @override
  double get maxDecibels => 15;
}

class _Eq extends Fake implements AndroidEqualizer {
  final bands = [
    for (final f in [60.0, 230.0, 910.0, 3600.0, 14000.0]) _Band(f),
  ];
  bool on = false;
  @override
  bool get enabled => on;
  @override
  Future<void> setEnabled(bool value) async => on = value;
  @override
  Future<AndroidEqualizerParameters> get parameters async => _Params(bands);
}

class _Handler extends Fake implements WavvyAudioHandler {
  final preamps = <double>[];
  @override
  Future<void> setPreamp(double db) async => preamps.add(db);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late _Eq eq;
  late _Handler handler;

  ProviderContainer make() {
    final c = ProviderContainer(
      overrides: [
        equalizerInstanceProvider.overrideWithValue(eq),
        audioHandlerProvider.overrideWithValue(handler),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<ProviderContainer> ready() async {
    final c = make();
    c.read(equalizerProvider); // builds it and starts loading
    await _settle();
    return c;
  }

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    eq = _Eq();
    handler = _Handler();
  });

  group('preampFor', () {
    test('is the biggest boost as a cut, and nothing for flat or cuts', () {
      expect(EqualizerNotifier.preampFor([0, 0, 0]), 0);
      expect(EqualizerNotifier.preampFor([-4, -2, 0]), 0);
      expect(EqualizerNotifier.preampFor([5, 3, -1, 3, 5]), -5);
      expect(EqualizerNotifier.preampFor([12, 0], floor: -9), -9);
    });
  });

  group('presets', () {
    test('there are more built in, and every curve has five points', () {
      expect(EqualizerNotifier.presets.length, greaterThanOrEqualTo(15));
      for (final entry in EqualizerNotifier.presets.entries) {
        expect(entry.value, hasLength(5), reason: entry.key);
      }
    });

    test('the list has the built in presets first, then your own', () async {
      final c = await ready();
      final n = c.read(equalizerProvider.notifier);
      await n.saveCustomPreset('Mine');
      final names = c.read(equalizerProvider).presetNames;
      expect(names.first, 'Flat');
      expect(names.last, 'Mine');
    });
  });

  group('auto preamp', () {
    test(
      'lowers the volume by the biggest boost while the equalizer is on',
      () async {
        final c = await ready();
        final n = c.read(equalizerProvider.notifier);
        await n.toggleEnabled(true);
        await n.applyPreset('Rock'); // peaks at +5 dB
        expect(c.read(equalizerProvider).preampDb, -5);
        expect(handler.preamps.last, -5);

        await n.applyPreset('Flat');
        expect(c.read(equalizerProvider).preampDb, 0);
        expect(handler.preamps.last, 0);
      },
    );

    test('does nothing while the equalizer is off', () async {
      final c = await ready();
      final n = c.read(equalizerProvider.notifier);
      await n.applyPreset('Rock');
      expect(c.read(equalizerProvider).preampDb, 0);
      await n.toggleEnabled(true);
      expect(c.read(equalizerProvider).preampDb, -5);
      await n.toggleEnabled(false);
      expect(c.read(equalizerProvider).preampDb, 0);
    });

    test(
      'follows a single band, can be switched off, and is remembered',
      () async {
        var c = await ready();
        final n = c.read(equalizerProvider.notifier);
        await n.toggleEnabled(true);
        await n.setBandGain(2, 7.5);
        expect(c.read(equalizerProvider).preampDb, -7.5);

        await n.setAutoPreamp(false);
        expect(c.read(equalizerProvider).preampDb, 0);
        expect(handler.preamps.last, 0);

        // A new session reads the setting back.
        c.dispose();
        c = await ready();
        expect(c.read(equalizerProvider).autoPreamp, isFalse);
      },
    );
  });

  group('your own presets', () {
    test('saves the current bands and applies them again later', () async {
      final c = await ready();
      final n = c.read(equalizerProvider.notifier);
      await n.setBandGain(0, 4);
      await n.setBandGain(4, -3);
      expect(await n.saveCustomPreset('  Night '), isNull);
      expect(c.read(equalizerProvider).currentPreset, 'Night');
      expect(c.read(equalizerProvider).customPresets['Night'], [
        4,
        0,
        0,
        0,
        -3,
      ]);

      await n.applyPreset('Flat');
      expect(eq.bands.map((b) => b.gain), everyElement(0));
      await n.applyPreset('Night');
      expect(eq.bands.map((b) => b.gain), [4, 0, 0, 0, -3]);
    });

    test('refuses empty, long and reserved names', () async {
      final c = await ready();
      final n = c.read(equalizerProvider.notifier);
      expect(await n.saveCustomPreset('   '), isNotNull);
      expect(await n.saveCustomPreset('x' * 25), isNotNull);
      expect(await n.saveCustomPreset('rock'), isNotNull);
      expect(await n.saveCustomPreset('Custom'), isNotNull);
      expect(c.read(equalizerProvider).customPresets, isEmpty);
    });

    test('are kept between sessions, and can be deleted', () async {
      var c = await ready();
      var n = c.read(equalizerProvider.notifier);
      await n.setBandGain(1, 2);
      await n.saveCustomPreset('Keep');
      c.dispose();

      c = await ready();
      n = c.read(equalizerProvider.notifier);
      expect(c.read(equalizerProvider).customPresets.keys, ['Keep']);

      await n.applyPreset('Keep');
      await n.deleteCustomPreset('Keep');
      expect(c.read(equalizerProvider).customPresets, isEmpty);
      expect(c.read(equalizerProvider).currentPreset, 'Custom');

      c.dispose();
      c = await ready();
      expect(c.read(equalizerProvider).customPresets, isEmpty);
    });
  });
}
