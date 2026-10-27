import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/playback/crossfade.dart';

/// Overlaps the end of one track with the start of the next.
///
/// A single just_audio player can only play one track at a time, so a second
/// one plays the incoming track while the first fades out. When the fade is
/// done the first player is moved into the next track at the same point and the
/// second one is stopped, so the rest of the app (queue, notification, effects)
/// only ever deals with the first player.
///
/// The second player has its own equalizer and loudness enhancer, copied from
/// the first when a crossfade starts. Bass boost, virtualizer and reverb are
/// bound to the first player's audio session, so they are not heard on the
/// incoming track until the hand-over, a few seconds at most.
class Crossfader {
  Crossfader({
    required this.primary,
    required this.primaryEqualizer,
    required this.setPrimaryLevel,
    required this.baseVolume,
    required this.loudnessDb,
  });

  final AudioPlayer primary;
  final AndroidEqualizer primaryEqualizer;

  /// Sets the first player's crossfade level (0 to 1).
  final void Function(double level) setPrimaryLevel;

  /// The volume the user's settings call for, before any fading.
  final double Function() baseVolume;
  final double Function() loudnessDb;

  /// Crossfade length; zero is off.
  Duration fade = Duration.zero;

  AudioPlayer? _secondary;
  AndroidEqualizer? _secondaryEqualizer;
  AndroidLoudnessEnhancer? _secondaryEnhancer;
  int? _startedFor;
  int _token = 0;
  bool get running => _running;
  bool _running = false;

  /// Call as playback moves; starts a crossfade when it is time.
  void onPosition(Duration position) {
    final next = primary.nextIndex;
    final index = primary.currentIndex;
    if (next == null || index == null || _running) return;
    final sequence = primary.sequence;
    if (next >= sequence.length) return;
    final nextTag = sequence[next].tag;
    final plan = CrossfadePlan(fade);
    if (!plan.shouldStart(
      position: position,
      duration: primary.duration,
      nextDuration: nextTag is SongModel && nextTag.duration != null
          ? Duration(milliseconds: nextTag.duration!)
          : null,
      playing: primary.playing,
      hasNext: true,
      repeatOne: primary.loopMode == LoopMode.one,
      currentIndex: index,
      alreadyFor: _startedFor,
    )) {
      return;
    }
    final source = sequence[next];
    if (source is! UriAudioSource) return;
    _startedFor = index;
    unawaited(_run(++_token, next, source.uri, nextTag));
  }

  /// Forget that a crossfade ran for the current track (after a seek back, so
  /// it can run again).
  void reset() => _startedFor = null;

  /// Stops a crossfade in progress and puts the first player back to full.
  void cancel() {
    _token++;
    if (_running) {
      _running = false;
      unawaited(_secondary?.stop() ?? Future<void>.value());
      setPrimaryLevel(1);
    }
  }

  Future<void> _prepare() async {
    if (_secondary == null) {
      _secondaryEnhancer = AndroidLoudnessEnhancer();
      _secondaryEqualizer = AndroidEqualizer();
      _secondary = AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects: [_secondaryEnhancer!, _secondaryEqualizer!],
        ),
        handleInterruptions: false,
      );
    }
    final enhancer = _secondaryEnhancer!;
    final equalizer = _secondaryEqualizer!;
    await enhancer.setEnabled(true);
    await enhancer.setTargetGain(loudnessDb());
    await equalizer.setEnabled(primaryEqualizer.enabled);
    // Copy the equalizer curve, so the incoming track sounds the same.
    try {
      final from = (await primaryEqualizer.parameters).bands;
      final to = (await equalizer.parameters).bands;
      for (var i = 0; i < from.length && i < to.length; i++) {
        await to[i].setGain(from[i].gain);
      }
    } catch (e) {
      debugPrint('crossfade: could not copy the equalizer: $e');
    }
  }

  Future<void> _run(int token, int nextIndex, Uri uri, Object? tag) async {
    _running = true;
    try {
      await _prepare();
      final player = _secondary!;
      if (token != _token) return;
      await player.setAudioSource(AudioSource.uri(uri, tag: tag));
      await player.setSpeed(primary.speed);
      await player.setPitch(primary.pitch);
      await player.setVolume(0);
      if (token != _token) return;
      unawaited(player.play());

      // Fade out the old track and in the new one, in step.
      final total = fade;
      final clock = Stopwatch()..start();
      while (clock.elapsed < total) {
        if (token != _token) return;
        final t = clock.elapsedMilliseconds / total.inMilliseconds;
        final level = crossfadeLevels(t);
        setPrimaryLevel(level.outgoing);
        await player.setVolume((level.incoming * baseVolume()).clamp(0, 1));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      if (token != _token) return;

      // Hand over: move the first player to where the second has got to.
      await player.setVolume(baseVolume().clamp(0, 1));
      await primary.seek(player.position, index: nextIndex);
      await primary.processingStateStream
          .firstWhere((s) => s == ProcessingState.ready)
          .timeout(const Duration(seconds: 3));
      if (token != _token) return;
      final overlap = clock..reset();
      const handOver = Duration(milliseconds: 160);
      while (overlap.elapsed < handOver) {
        final t = overlap.elapsedMilliseconds / handOver.inMilliseconds;
        final level = crossfadeLevels(t);
        setPrimaryLevel(level.incoming);
        await player.setVolume((level.outgoing * baseVolume()).clamp(0, 1));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      setPrimaryLevel(1);
      await player.stop();
    } catch (e) {
      debugPrint('crossfade failed, falling back to a normal change: $e');
      setPrimaryLevel(1);
      await _secondary?.stop();
    } finally {
      if (token == _token) _running = false;
    }
  }

  Future<void> dispose() async {
    cancel();
    await _secondary?.dispose();
    _secondary = null;
  }
}
