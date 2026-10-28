import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:wavvy/core/storage_permissions.dart';
import 'package:wavvy/playback/visualizer_math.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

/// Plain channel wrapper (no state), so tests can substitute a fake. Calls
/// throw [PlatformException]: code `permission` when the microphone permission
/// is missing, anything else when the device cannot provide a spectrum.
class VisualizerChannel {
  static const MethodChannel _method = MethodChannel(
    'com.mirimomekiku.wavvy/visualizer',
  );
  static const EventChannel _events = EventChannel(
    'com.mirimomekiku.wavvy/visualizer_frames',
  );

  /// Attaches a native Visualizer to the audio session, replacing any other.
  Future<void> start(int sessionId, {int bands = kVisualizerBands}) => _method
      .invokeMethod<void>('start', {'sessionId': sessionId, 'bands': bands});

  /// Releases the native Visualizer.
  Future<void> stop() => _method.invokeMethod<void>('stop');

  /// Band levels (0..1, low to high), one list per native frame.
  Stream<List<double>> frames() => _events.receiveBroadcastStream().map((e) {
    if (e is Float32List) return e.toList();
    if (e is List) return [for (final v in e) (v as num).toDouble()];
    throw const FormatException('Unexpected visualizer frame');
  });

  /// The microphone permission, optionally asking for it.
  Future<StorageAccess> permission({bool request = false}) =>
      StoragePermissions.microphone(request: request);

  Future<void> openSettings() async {
    await ph.openAppSettings();
  }
}

final visualizerChannelProvider = Provider<VisualizerChannel>(
  (ref) => VisualizerChannel(),
);

/// The player's audio session id; null until the player has one. Overridable
/// in tests.
final visualizerSessionProvider = StreamProvider<int?>(
  (ref) => ref.watch(audioPlayerProvider).androidAudioSessionIdStream,
);

/// Whether music is playing. Overridable in tests.
final visualizerPlayingProvider = Provider<bool>(
  (ref) => ref.watch(playerProvider.select((s) => s.isPlaying)),
);

enum VisualizerStatus {
  /// The setting is off.
  off,

  /// The microphone permission is missing ([VisualizerState.blocked] says
  /// whether Android will still show its prompt).
  needsPermission,

  /// The device could not provide a spectrum.
  unavailable,

  /// Attached, or waiting for something to play.
  running,
}

class VisualizerState {
  final VisualizerStatus status;

  /// Smoothed levels, 0..1, low to high.
  final List<double> bands;

  /// Peak caps, one per band.
  final List<double> peaks;

  /// The permission was refused for good: only the system settings help.
  final bool blocked;

  const VisualizerState({
    this.status = VisualizerStatus.off,
    this.bands = const [],
    this.peaks = const [],
    this.blocked = false,
  });

  VisualizerState copyWith({
    VisualizerStatus? status,
    List<double>? bands,
    List<double>? peaks,
    bool? blocked,
  }) => VisualizerState(
    status: status ?? this.status,
    bands: bands ?? this.bands,
    peaks: peaks ?? this.peaks,
    blocked: blocked ?? this.blocked,
  );
}

/// Runs the native visualizer for the current audio session, only while the
/// setting is on, the visualizer page is [setVisible] and music is playing.
/// Everything else (hidden, paused, setting off, a new session, an error)
/// releases it. Frames are smoothed here: fast attack, slow decay, peak caps.
class VisualizerNotifier extends Notifier<VisualizerState> {
  bool _visible = false;
  int? _attached;

  // The session a start already failed for; not retried until something
  // changes (shown again, new session, permission), so a device that cannot
  // do it is not hammered.
  int? _failedSession;
  StreamSubscription<List<double>>? _frames;
  bool _applying = false;
  bool _again = false;
  bool _disposed = false;

  // Kept from build: a provider cannot be read while it is being disposed.
  late VisualizerChannel _channel;

  @override
  VisualizerState build() {
    _disposed = false;
    _channel = ref.read(visualizerChannelProvider);
    ref.onDispose(() {
      _disposed = true;
      _frames?.cancel();
      _frames = null;
      if (_attached != null) {
        _attached = null;
        // Best effort: the channel may already be gone.
        unawaited(_channel.stop().catchError((_) {}));
      }
    });
    ref.listen(settingsProvider.select((s) => s.enableVisualizer), (_, _) {
      _apply();
    });
    ref.listen(visualizerSessionProvider, (_, _) => _apply());
    ref.listen(visualizerPlayingProvider, (_, _) => _apply());
    final enabled = ref.read(settingsProvider).enableVisualizer;
    return VisualizerState(
      status: enabled ? VisualizerStatus.running : VisualizerStatus.off,
    );
  }

  /// The visualizer page is on screen (true) or not (false).
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _failedSession = null;
    // Not inside a build or dispose, which is where the page calls this.
    scheduleMicrotask(_apply);
  }

  /// Asks for the microphone permission (the "Grant permission" button).
  /// Returns what the user decided; a permanent refusal is [blocked].
  Future<StorageAccess> grantPermission() async {
    final access = await _channel.permission(request: true);
    if (_disposed) return access;
    _failedSession = null;
    state = state.copyWith(blocked: access == StorageAccess.blocked);
    await _apply();
    return access;
  }

  Future<void> openSystemSettings() => _channel.openSettings();

  Future<void> _apply() async {
    if (_applying) {
      _again = true;
      return;
    }
    _applying = true;
    try {
      do {
        _again = false;
        if (_disposed) return;
        await _applyOnce();
      } while (_again && !_disposed);
    } finally {
      _applying = false;
    }
  }

  Future<void> _applyOnce() async {
    final enabled = ref.read(settingsProvider).enableVisualizer;
    if (!enabled) {
      await _detach();
      _set(status: VisualizerStatus.off, quiet: true, blocked: false);
      return;
    }
    if (!_visible) {
      await _detach();
      return;
    }
    final access = await _channel.permission();
    if (_disposed) return;
    if (!access.isGranted) {
      await _detach();
      _set(
        status: VisualizerStatus.needsPermission,
        quiet: true,
        blocked: access == StorageAccess.blocked,
      );
      return;
    }
    final session = ref.read(visualizerSessionProvider).value;
    if (session == null || session <= 0) {
      await _detach();
      _set(status: VisualizerStatus.running, quiet: true, blocked: false);
      return;
    }
    if (_failedSession == session) {
      await _detach();
      return;
    }
    if (!ref.read(visualizerPlayingProvider)) {
      await _detach();
      _set(status: VisualizerStatus.running, quiet: true, blocked: false);
      return;
    }
    if (_attached == session && _frames != null) {
      if (state.status != VisualizerStatus.running) {
        _set(status: VisualizerStatus.running, blocked: false);
      }
      return;
    }
    await _detach();
    // Listen first so the first native frame is not lost.
    _frames = _channel.frames().listen(_onFrame, onError: _onError);
    try {
      await _channel.start(session);
      if (_disposed) return;
      _attached = session;
      _set(status: VisualizerStatus.running, blocked: false);
    } on PlatformException catch (e) {
      _failedSession = session;
      await _detach();
      _set(
        status: e.code == 'permission'
            ? VisualizerStatus.needsPermission
            : VisualizerStatus.unavailable,
        quiet: true,
      );
    } catch (_) {
      _failedSession = session;
      await _detach();
      _set(status: VisualizerStatus.unavailable, quiet: true);
    }
  }

  void _onFrame(List<double> raw) {
    if (_disposed || _attached == null) return;
    final bands = smoothBands(state.bands, raw);
    state = state.copyWith(
      bands: bands,
      peaks: updatePeaks(state.peaks, bands),
    );
  }

  void _onError(Object error) {
    if (_disposed) return;
    unawaited(
      _detach().whenComplete(() {
        if (!_disposed) _set(status: VisualizerStatus.unavailable, quiet: true);
      }),
    );
  }

  Future<void> _detach() async {
    final frames = _frames;
    final wasAttached = _attached != null;
    _frames = null;
    _attached = null;
    await frames?.cancel();
    // Also release when start() failed half way; stop() is harmless.
    if (wasAttached || frames != null) {
      try {
        await _channel.stop();
      } catch (_) {}
    }
  }

  /// Updates the status. [quiet] also lets the bars fall to rest, since no
  /// more frames are coming.
  void _set({
    required VisualizerStatus status,
    bool quiet = false,
    bool? blocked,
  }) {
    if (_disposed) return;
    state = state.copyWith(
      status: status,
      blocked: blocked,
      bands: quiet && state.bands.isNotEmpty ? const [] : null,
      peaks: quiet && state.peaks.isNotEmpty ? const [] : null,
    );
  }
}

final visualizerProvider =
    NotifierProvider<VisualizerNotifier, VisualizerState>(
      VisualizerNotifier.new,
    );
