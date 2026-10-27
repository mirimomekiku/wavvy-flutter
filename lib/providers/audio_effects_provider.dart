import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wavvy/providers/player_provider.dart';

/// The AndroidEqualizer that is part of the just_audio pipeline. Created in
/// main() (before the handler) and overridden here.
final equalizerInstanceProvider = Provider<AndroidEqualizer>(
  (ref) => throw UnimplementedError('override in main'),
);

/// Which native effects this device could create for the current audio session.
class EffectSupport {
  final bool bassBoost;
  final bool virtualizer;
  final bool reverb;

  const EffectSupport({
    this.bassBoost = true,
    this.virtualizer = true,
    this.reverb = true,
  });

  static const none = EffectSupport(
    bassBoost: false,
    virtualizer: false,
    reverb: false,
  );
}

/// Plain MethodChannel wrapper (no state). Overridden in main() so tests can
/// substitute a fake. Calls throw [PlatformException] when an effect is
/// unavailable or rejects a value.
class NativeEffectsChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.mirimomekiku.wavvy/audio_effects',
  );

  /// (Re)creates the effects for the audio session, all switched off, and
  /// reports which of them the device supports.
  Future<EffectSupport> initEffects(int sessionId) async {
    final result = await _channel.invokeMapMethod<String, bool>('initEffects', {
      'sessionId': sessionId,
    });
    return EffectSupport(
      bassBoost: result?['bassBoost'] ?? false,
      virtualizer: result?['virtualizer'] ?? false,
      reverb: result?['reverb'] ?? false,
    );
  }

  Future<void> setBassBoost(int strength) =>
      _channel.invokeMethod('setBassBoost', {'strength': strength});
  Future<void> setVirtualizer(int strength) =>
      _channel.invokeMethod('setVirtualizer', {'strength': strength});
  Future<void> setReverb(String preset) =>
      _channel.invokeMethod('setReverb', {'preset': preset});
  Future<void> release() => _channel.invokeMethod('releaseEffects');
}

final nativeEffectsChannelProvider = Provider<NativeEffectsChannel>(
  (ref) => throw UnimplementedError('override in main'),
);

// ---------------------------------------------------------------- Equalizer

class EqualizerState {
  final bool isEnabled;
  final List<AndroidEqualizerBand> bands;
  final double minDecibels;
  final double maxDecibels;
  final String currentPreset;

  /// Why the equalizer can't be used, or empty.
  final String error;

  const EqualizerState({
    this.isEnabled = false,
    this.bands = const [],
    this.minDecibels = -15.0,
    this.maxDecibels = 15.0,
    this.currentPreset = 'Custom',
    this.error = '',
  });

  EqualizerState copyWith({
    bool? isEnabled,
    List<AndroidEqualizerBand>? bands,
    double? minDecibels,
    double? maxDecibels,
    String? currentPreset,
    String? error,
  }) => EqualizerState(
    isEnabled: isEnabled ?? this.isEnabled,
    bands: bands ?? this.bands,
    minDecibels: minDecibels ?? this.minDecibels,
    maxDecibels: maxDecibels ?? this.maxDecibels,
    currentPreset: currentPreset ?? this.currentPreset,
    error: error ?? this.error,
  );
}

final equalizerProvider = NotifierProvider<EqualizerNotifier, EqualizerState>(
  EqualizerNotifier.new,
);

/// Drives the just_audio AndroidEqualizer. just_audio reports and accepts band
/// gains in decibels, so every value here is in dB.
class EqualizerNotifier extends Notifier<EqualizerState> {
  /// Preset curves in dB, low to high frequency. A device may have a different
  /// number of bands, so a curve is interpolated across them ([_curveAt]).
  static const Map<String, List<double>> presets = {
    'Flat': [0, 0, 0, 0, 0],
    'Bass Boost': [6, 4, 0, 0, 0],
    'Rock': [5, 3, -1, 3, 5],
    'Pop': [-1, 2, 4, 2, -1],
    'Jazz': [3, 2, -1, 2, 3],
    'Voice': [-2, -1, 3, 3, 1],
    'Treble': [0, 0, 0, 4, 6],
  };

  /// The gain, in dB, of preset [name] at band [index] out of [count] bands.
  static double presetGain(String name, int index, int count) =>
      _curveAt(presets[name]!, index, count);

  static double _curveAt(List<double> curve, int index, int count) {
    if (count <= 1 || curve.length == 1) return curve.first;
    final t = index * (curve.length - 1) / (count - 1);
    final low = t.floor();
    final high = t.ceil();
    return curve[low] + (curve[high] - curve[low]) * (t - low);
  }

  bool _disposed = false;

  /// Reads the band layout and returns the defaults immediately.
  @override
  EqualizerState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // After build returns, so a failure can be written to state.
    Future.microtask(_init);
    return const EqualizerState();
  }

  AndroidEqualizer get _eq => ref.read(equalizerInstanceProvider);

  Future<void> _init() async {
    try {
      final params = await _eq.parameters;
      if (_disposed) return;
      if (params.bands.isEmpty) {
        state = state.copyWith(error: 'This device has no equalizer.');
        return;
      }
      state = state.copyWith(
        bands: List<AndroidEqualizerBand>.from(params.bands),
        minDecibels: params.minDecibels,
        maxDecibels: params.maxDecibels,
        isEnabled: _eq.enabled,
        error: '',
      );
    } catch (e) {
      debugPrint('equalizer init failed: $e');
      if (_disposed) return;
      state = state.copyWith(error: 'The equalizer could not be started.');
    }
  }

  Future<void> toggleEnabled(bool value) async {
    try {
      await _eq.setEnabled(value);
      state = state.copyWith(isEnabled: value, error: '');
    } catch (e) {
      debugPrint('equalizer toggle failed: $e');
      state = state.copyWith(error: 'The equalizer could not be switched.');
    }
  }

  Future<void> _setGain(int bandIndex, double gainDb) async {
    final band = state.bands[bandIndex];
    await band.setGain(gainDb.clamp(state.minDecibels, state.maxDecibels));
  }

  /// Sets one band, in dB (clamped to the device range).
  Future<void> setBandGain(int bandIndex, double gainDb) async {
    if (bandIndex < 0 || bandIndex >= state.bands.length) return;
    try {
      await _setGain(bandIndex, gainDb);
      state = state.copyWith(currentPreset: 'Custom', error: '');
    } catch (e) {
      debugPrint('equalizer band $bandIndex failed: $e');
      state = state.copyWith(error: 'That band could not be changed.');
    }
  }

  Future<void> resetToFlat() => applyPreset('Flat');

  Future<void> applyPreset(String presetName) async {
    final curve = presets[presetName];
    if (curve == null || state.bands.isEmpty) return;
    try {
      for (var i = 0; i < state.bands.length; i++) {
        await _setGain(i, _curveAt(curve, i, state.bands.length));
      }
      state = state.copyWith(currentPreset: presetName, error: '');
    } catch (e) {
      debugPrint('equalizer preset $presetName failed: $e');
      state = state.copyWith(error: 'That preset could not be applied.');
    }
  }
}

// ------------------------------------------------------------------ Effects

class EffectsState {
  final bool isBassBoostEnabled;
  final double bassBoostStrength; // 0..1000
  final bool isVirtualizerEnabled;
  final double virtualizerStrength; // 0..1000
  final String currentReverbPreset;
  final bool isLoudnessBoosted;

  /// What the device supports; assumed until the audio session reports.
  final EffectSupport support;

  /// Why the last change failed, or empty.
  final String error;

  const EffectsState({
    this.isBassBoostEnabled = false,
    this.bassBoostStrength = 0.0,
    this.isVirtualizerEnabled = false,
    this.virtualizerStrength = 0.0,
    this.currentReverbPreset = "None",
    this.isLoudnessBoosted = false,
    this.support = const EffectSupport(),
    this.error = '',
  });

  EffectsState copyWith({
    bool? isBassBoostEnabled,
    double? bassBoostStrength,
    bool? isVirtualizerEnabled,
    double? virtualizerStrength,
    String? currentReverbPreset,
    bool? isLoudnessBoosted,
    EffectSupport? support,
    String? error,
  }) => EffectsState(
    isBassBoostEnabled: isBassBoostEnabled ?? this.isBassBoostEnabled,
    bassBoostStrength: bassBoostStrength ?? this.bassBoostStrength,
    isVirtualizerEnabled: isVirtualizerEnabled ?? this.isVirtualizerEnabled,
    virtualizerStrength: virtualizerStrength ?? this.virtualizerStrength,
    currentReverbPreset: currentReverbPreset ?? this.currentReverbPreset,
    isLoudnessBoosted: isLoudnessBoosted ?? this.isLoudnessBoosted,
    support: support ?? this.support,
    error: error ?? this.error,
  );
}

final effectsProvider = NotifierProvider<EffectsNotifier, EffectsState>(
  EffectsNotifier.new,
);

/// Bass boost, virtualizer, reverb and the volume boost. setBassBoost and
/// setVirtualizer take 0.0..1.0 (mapped to 0..1000 natively; state keeps the
/// 0..1000 value). A change the device rejects leaves the effect off and sets
/// [EffectsState.error] instead of pretending it worked.
class EffectsNotifier extends Notifier<EffectsState> {
  /// Volume boost applied by the loudness enhancer, in dB.
  static const double loudnessBoostDb = 6.0;

  @override
  EffectsState build() => const EffectsState();

  NativeEffectsChannel get _channel => ref.read(nativeEffectsChannelProvider);

  /// Creates the native effects for a new audio session and puts the user's
  /// settings back on them (the platform creates them switched off).
  Future<void> attachToSession(int sessionId) async {
    try {
      final support = await _channel.initEffects(sessionId);
      state = state.copyWith(support: support, error: '');
    } on PlatformException catch (e) {
      debugPrint('initEffects failed: $e');
      state = state.copyWith(
        support: EffectSupport.none,
        error: 'Sound effects are not available on this device.',
      );
      return;
    } on MissingPluginException {
      state = state.copyWith(support: EffectSupport.none);
      return;
    }
    final s = state;
    if (s.bassBoostStrength > 0 && s.support.bassBoost) {
      await setBassBoost(s.bassBoostStrength / 1000);
    }
    if (s.virtualizerStrength > 0 && s.support.virtualizer) {
      await setVirtualizer(s.virtualizerStrength / 1000);
    }
    if (s.currentReverbPreset != 'None' && s.support.reverb) {
      await setReverb(s.currentReverbPreset);
    }
  }

  Future<void> setBassBoost(double strength) async {
    final val = (strength.clamp(0.0, 1.0) * 1000).round();
    try {
      await _channel.setBassBoost(val);
      state = state.copyWith(
        isBassBoostEnabled: val > 0,
        bassBoostStrength: val.toDouble(),
        error: '',
      );
    } on PlatformException catch (e) {
      debugPrint('setBassBoost failed: $e');
      state = state.copyWith(
        isBassBoostEnabled: false,
        bassBoostStrength: 0,
        error: 'Bass boost is not available right now.',
      );
    }
  }

  Future<void> setVirtualizer(double strength) async {
    final val = (strength.clamp(0.0, 1.0) * 1000).round();
    try {
      await _channel.setVirtualizer(val);
      state = state.copyWith(
        isVirtualizerEnabled: val > 0,
        virtualizerStrength: val.toDouble(),
        error: '',
      );
    } on PlatformException catch (e) {
      debugPrint('setVirtualizer failed: $e');
      state = state.copyWith(
        isVirtualizerEnabled: false,
        virtualizerStrength: 0,
        error: 'Virtualizer is not available right now.',
      );
    }
  }

  Future<void> setReverb(String preset) async {
    try {
      await _channel.setReverb(preset);
      state = state.copyWith(currentReverbPreset: preset, error: '');
    } on PlatformException catch (e) {
      debugPrint('setReverb failed: $e');
      state = state.copyWith(
        currentReverbPreset: 'None',
        error: 'Reverb is not available right now.',
      );
    }
  }

  /// Raises the overall volume by [loudnessBoostDb] (the loudness enhancer).
  Future<void> setLoudnessBoost(bool enabled) async {
    try {
      await ref
          .read(audioHandlerProvider)
          .setUserBoost(enabled ? loudnessBoostDb : 0.0);
      state = state.copyWith(isLoudnessBoosted: enabled, error: '');
    } catch (e) {
      debugPrint('loudness boost failed: $e');
      state = state.copyWith(error: 'Volume boost is not available.');
    }
  }

  /// Switches bass boost, virtualizer and reverb off.
  Future<void> resetAll() async {
    if (state.support.bassBoost) await setBassBoost(0);
    if (state.support.virtualizer) await setVirtualizer(0);
    if (state.support.reverb) await setReverb('None');
  }
}
