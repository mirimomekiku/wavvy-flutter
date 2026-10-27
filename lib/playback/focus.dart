/// What the player lets the focus controller do.
abstract class FocusTarget {
  bool get playing;
  Future<void> pause();
  Future<void> play();

  /// Lowers the volume for a short interruption, or restores it.
  Future<void> setDucked(bool ducked);
}

/// How to react to calls, notifications and headphones. Read fresh each time,
/// so a setting change applies at once.
class FocusPolicy {
  final bool pauseOnUnplug;
  final bool duck;
  final bool resumeAfterInterruption;
  final bool resumeOnReconnect;

  const FocusPolicy({
    this.pauseOnUnplug = true,
    this.duck = true,
    this.resumeAfterInterruption = true,
    this.resumeOnReconnect = false,
  });
}

enum FocusInterruption { duck, pause, unknown }

/// Decides what to do when another app wants the audio or the headphones
/// change. It knows nothing about Android: the platform events are fed to it, so
/// the rules can be tested.
class FocusController {
  FocusController({
    required this.target,
    required this.policy,
    DateTime Function()? clock,
    this.reconnectWindow = const Duration(minutes: 10),
  }) : _now = clock ?? DateTime.now;

  final FocusTarget target;
  final FocusPolicy Function() policy;
  final Duration reconnectWindow;
  final DateTime Function() _now;

  bool _ducked = false;
  bool _resumeAfterFocus = false;
  DateTime? _unpluggedAt;

  /// Another app took the audio ([begin]) or gave it back.
  Future<void> onInterruption(bool begin, FocusInterruption type) async {
    final p = policy();
    if (begin) {
      if (type == FocusInterruption.duck && p.duck) {
        _ducked = true;
        await target.setDucked(true);
        return;
      }
      if (target.playing) {
        _resumeAfterFocus = true;
        await target.pause();
      }
      return;
    }
    if (_ducked) {
      _ducked = false;
      await target.setDucked(false);
    }
    // "Unknown" means the user took over (for example started another player),
    // so playback is not resumed behind their back.
    final resume =
        _resumeAfterFocus &&
        p.resumeAfterInterruption &&
        type != FocusInterruption.unknown;
    _resumeAfterFocus = false;
    if (resume && !target.playing) await target.play();
  }

  /// Headphones were unplugged (the audio is about to go to the speaker).
  Future<void> onBecomingNoisy() async {
    if (!policy().pauseOnUnplug || !target.playing) return;
    _unpluggedAt = _now();
    await target.pause();
  }

  /// Headphones or a Bluetooth device were connected.
  Future<void> onHeadphonesConnected() async {
    final at = _unpluggedAt;
    if (at == null || !policy().resumeOnReconnect) return;
    _unpluggedAt = null;
    if (_now().difference(at) <= reconnectWindow && !target.playing) {
      await target.play();
    }
  }

  /// The user paused or started playback themselves: forget what we were going
  /// to do on their behalf.
  void userChangedPlayback() {
    _resumeAfterFocus = false;
    _unpluggedAt = null;
  }
}
