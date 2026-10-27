import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// The AndroidEqualizer that is part of the just_audio pipeline. Created in
/// main() (before the handler) and overridden here.
final equalizerInstanceProvider = Provider<AndroidEqualizer>(
  (ref) => throw UnimplementedError('override in main'),
);

/// Plain MethodChannel wrapper (no state). Used by the audio handler
/// (outside Riverpod) and by [EffectsNotifier]. Overridden in main() with the
/// same instance the handler holds.
class NativeEffectsChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.mirimomekiku.wavvy/audio_effects',
  );

  Future<void> initEffects(int sessionId) =>
      _channel.invokeMethod('initEffects', {'sessionId': sessionId});
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

  const EqualizerState({
    this.isEnabled = false,
    this.bands = const [],
    this.minDecibels = -15.0,
    this.maxDecibels = 15.0,
    this.currentPreset = 'Custom',
  });

  EqualizerState copyWith({
    bool? isEnabled,
    List<AndroidEqualizerBand>? bands,
    double? minDecibels,
    double? maxDecibels,
    String? currentPreset,
  }) => EqualizerState(
    isEnabled: isEnabled ?? this.isEnabled,
    bands: bands ?? this.bands,
    minDecibels: minDecibels ?? this.minDecibels,
    maxDecibels: maxDecibels ?? this.maxDecibels,
    currentPreset: currentPreset ?? this.currentPreset,
  );
}

final equalizerProvider = NotifierProvider<EqualizerNotifier, EqualizerState>(
  EqualizerNotifier.new,
);

/// Port of EqualizerService.
class EqualizerNotifier extends Notifier<EqualizerState> {
  /// Same preset table as before (Flat, Bass Boost, Rock, Pop, Jazz, Voice,
  /// Treble), values in dB.
  static const Map<String, List<double>> presets = {
    'Flat': [0, 0, 0, 0, 0],
    'Bass Boost': [0.06, 0.04, 0, 0, 0],
    'Rock': [0.05, 0.03, -0.01, 0.03, 0.05],
    'Pop': [-0.01, 0.02, 0.04, 0.02, -0.01],
    'Jazz': [0.03, 0.02, -0.01, 0.02, 0.03],
    'Voice': [-0.02, -0.01, 0.03, 0.03, 0.01],
    'Treble': [0, 0, 0, 0.04, 0.06],
  };

  /// Kicks off async init (read parameters: bands, min/max dB from millibels
  /// / 100, enabled) and returns the defaults immediately.
  @override
  EqualizerState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _init();
    return const EqualizerState();
  }

  bool _disposed = false;

  AndroidEqualizer get _eq => ref.read(equalizerInstanceProvider);

  Future<void> _init() async {
    try {
      final params = await _eq.parameters;
      if (_disposed) return;

      final double? minDb = params.minDecibels;
      final double? maxDb = params.maxDecibels;

      state = state.copyWith(
        bands: List<AndroidEqualizerBand>.from(params.bands),
        minDecibels: minDb != null ? minDb / 100.0 : null,
        maxDecibels: maxDb != null ? maxDb / 100.0 : null,
        isEnabled: _eq.enabled,
      );
    } catch (e) {}
  }

  Future<void> toggleEnabled(bool value) async {
    try {
      await _eq.setEnabled(value);
      state = state.copyWith(isEnabled: value);
    } catch (e) {}
  }

  /// gainDb * 100 millibels, bounds-checked.
  Future<void> setBandGain(int bandIndex, double gainDb) async {
    try {
      if (bandIndex < 0 || bandIndex >= state.bands.length) return;
      final band = state.bands[bandIndex];
      await band.setGain(gainDb * 100.0);
    } catch (e) {}
  }

  Future<void> resetToFlat() async {
    for (int i = 0; i < state.bands.length; i++) {
      await setBandGain(i, 0.0);
    }
  }

  /// Clamps each value to [minDecibels, maxDecibels]; sets currentPreset.
  Future<void> applyPreset(String presetName) async {
    if (!presets.containsKey(presetName)) return;

    final values = presets[presetName]!;
    final bands = state.bands;
    final count = values.length < bands.length ? values.length : bands.length;

    for (int i = 0; i < count; i++) {
      final double clampedDb = values[i].clamp(
        state.minDecibels,
        state.maxDecibels,
      );
      await bands[i].setGain(clampedDb * 100.0);
    }

    state = state.copyWith(currentPreset: presetName);
  }
}

// ------------------------------------------------------------------ Effects

class EffectsState {
  final bool isBassBoostEnabled;
  final double bassBoostStrength; // 0..1000
  final bool isVirtualizerEnabled;
  final double virtualizerStrength; // 0..1000
  final String currentReverbPreset;

  const EffectsState({
    this.isBassBoostEnabled = false,
    this.bassBoostStrength = 0.0,
    this.isVirtualizerEnabled = false,
    this.virtualizerStrength = 0.0,
    this.currentReverbPreset = "None",
  });

  EffectsState copyWith({
    bool? isBassBoostEnabled,
    double? bassBoostStrength,
    bool? isVirtualizerEnabled,
    double? virtualizerStrength,
    String? currentReverbPreset,
  }) => EffectsState(
    isBassBoostEnabled: isBassBoostEnabled ?? this.isBassBoostEnabled,
    bassBoostStrength: bassBoostStrength ?? this.bassBoostStrength,
    isVirtualizerEnabled: isVirtualizerEnabled ?? this.isVirtualizerEnabled,
    virtualizerStrength: virtualizerStrength ?? this.virtualizerStrength,
    currentReverbPreset: currentReverbPreset ?? this.currentReverbPreset,
  );
}

final effectsProvider = NotifierProvider<EffectsNotifier, EffectsState>(
  EffectsNotifier.new,
);

/// Port of NativeEffectsService. setBassBoost/setVirtualizer take 0.0..1.0
/// (mapped to 0..1000 natively, state stores the 0..1000 double).
class EffectsNotifier extends Notifier<EffectsState> {
  @override
  EffectsState build() => const EffectsState();

  NativeEffectsChannel get _channel => ref.read(nativeEffectsChannelProvider);

  Future<void> setBassBoost(double strength) async {
    try {
      final int val = (strength * 1000).toInt();
      await _channel.setBassBoost(val);
      state = state.copyWith(
        isBassBoostEnabled: val > 0,
        bassBoostStrength: val.toDouble(),
      );
    } catch (e) {}
  }

  Future<void> setVirtualizer(double strength) async {
    try {
      final int val = (strength * 1000).toInt();
      await _channel.setVirtualizer(val);
      state = state.copyWith(
        isVirtualizerEnabled: val > 0,
        virtualizerStrength: val.toDouble(),
      );
    } catch (e) {}
  }

  Future<void> setReverb(String preset) async {
    try {
      await _channel.setReverb(preset);
      state = state.copyWith(currentReverbPreset: preset);
    } catch (e) {}
  }

  /// Resets Dart-side state to defaults (native effects are recreated
  /// disabled on every audio-session change) — called by the coordinator.
  void resetState() => state = const EffectsState();
}
