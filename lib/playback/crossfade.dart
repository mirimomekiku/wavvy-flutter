import 'dart:math' as math;

/// When a crossfade should begin. Pure, so the rules can be tested without a
/// player.
class CrossfadePlan {
  /// Crossfade length; 0 turns it off.
  final Duration fade;

  const CrossfadePlan(this.fade);

  /// Tracks shorter than this are not crossfaded: there would be hardly any of
  /// them left outside the fades.
  Duration get minTrack => fade * 2 + const Duration(seconds: 2);

  /// True when a crossfade into the next track should start now.
  ///
  /// [alreadyFor] is the queue index a crossfade was already started for, so one
  /// track only triggers it once even though the position keeps ticking.
  bool shouldStart({
    required Duration position,
    required Duration? duration,
    required Duration? nextDuration,
    required bool playing,
    required bool hasNext,
    required bool repeatOne,
    required int currentIndex,
    required int? alreadyFor,
  }) {
    if (fade <= Duration.zero || !playing || !hasNext || repeatOne) {
      return false;
    }
    if (alreadyFor == currentIndex) return false;
    if (duration == null || duration < minTrack) return false;
    if (nextDuration != null && nextDuration < minTrack) return false;
    final remaining = duration - position;
    // Not before the fade could fit, and not once the track is over anyway.
    return remaining <= fade && remaining > const Duration(milliseconds: 300);
  }
}

/// The two volumes during a crossfade at [t] (0 to 1): equal power, so the
/// loudness stays level in the middle instead of dipping.
({double outgoing, double incoming}) crossfadeLevels(double t) {
  final x = t.clamp(0.0, 1.0);
  return (
    outgoing: math.cos(x * math.pi / 2),
    incoming: math.sin(x * math.pi / 2),
  );
}
