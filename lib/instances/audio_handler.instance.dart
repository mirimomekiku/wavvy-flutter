import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/instances/crossfader.dart';
import 'package:wavvy/playback/focus.dart';

class WavvyAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AndroidEqualizer _equalizer;
  final AudioSession? _session;
  final _enhancer = AndroidLoudnessEnhancer();

  late final AudioPipeline pipeline = AudioPipeline(
    androidAudioEffects: [_enhancer, _equalizer],
  );

  // With an audio session the focus rules are Wavvy's own (see FocusController,
  // so pausing, ducking and resuming follow the user's settings); without one
  // the player does the default thing.
  late final AudioPlayer _player = AudioPlayer(
    audioPipeline: pipeline,
    handleInterruptions: _session == null,
  );

  late final Crossfader crossfader = Crossfader(
    primary: _player,
    primaryEqualizer: _equalizer,
    setPrimaryLevel: (v) {
      _crossfadeLevel = v;
      unawaited(_pushVolume());
    },
    baseVolume: () => _gain * _duck * _preamp,
    loudnessDb: () => _loudnessDb,
  );

  /// Decides what to do about calls, notifications and headphones. Set by the
  /// app once the audio session is available.
  FocusController? focus;

  /// A fetched cover (a file URI) for a song's album, if the app has one; it
  /// is used instead of the MediaStore album art for the notification.
  Uri? Function(SongModel song)? cachedArtUri;

  /// Handles taps on the notification's Like / Shuffle / Repeat buttons. Set by
  /// Fade the volume in on play and out on pause (Settings > Playback).
  bool fadeEnabled = false;
  int _fadeId = 0;
  static const _fadeDuration = Duration(milliseconds: 350);
  static const _fadeSteps = 10;

  // The player's volume is the product of several independent levels, so that
  // each feature can change its own without undoing another's.
  double _fade = 1; // play / pause / sleep fades
  double _gain = 1; // ReplayGain reduction
  double _duck = 1; // lowered for a short interruption
  double _preamp = 1; // headroom for equalizer boosts
  double _crossfadeLevel = 1;
  static const _duckLevel = 0.35;

  // Loudness boost: the user's volume boost plus any ReplayGain lift.
  double _userBoostDb = 0;
  double _replayGainDb = 0;
  double get _loudnessDb => _userBoostDb + math.max(0, _replayGainDb);

  WavvyAudioHandler({
    required AndroidEqualizer equalizer,
    AudioSession? session,
  }) : _equalizer = equalizer,
       _session = session {
    _init();
  }

  Future<void> _init() async {
    // Neutral until the user turns on the volume boost (Sound > Effects).
    unawaited(_enhancer.setEnabled(true));
    unawaited(_enhancer.setTargetGain(0.0));

    unawaited(_equalizer.setEnabled(true));

    _player.positionStream.listen(crossfader.onPosition);
    // A seek (or a new track) can bring a crossfade back into range.
    _player.currentIndexStream.listen((_) => crossfader.reset());

    // Playback can start without going through play() (a tap on a song calls
    // the player directly), so take the focus whenever it starts.
    _player.playingStream.distinct().listen((playing) {
      if (playing) unawaited(_ensureFocus());
    });

    _player.playbackEventStream.listen((PlaybackEvent event) {
      if (event.processingState == ProcessingState.ready) _failedInARow = 0;
      final playing = _player.playing;
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: event.currentIndex,
        ),
      );
    }, onError: _onPlaybackError);

    // Broadcast Current Song Metadata to System Notification
    _player.sequenceStateStream.listen((state) {
      if (state.currentSource == null) return;

      final tag = state.currentSource!.tag;
      if (tag is! SongModel) return;
      final song = tag;
      Uri? artUri = cachedArtUri?.call(song);
      if (artUri == null && song.albumId != null) {
        artUri = Uri.parse(
          "content://media/external/audio/albumart/${song.albumId}",
        );
      }

      mediaItem.add(
        MediaItem(
          id: song.id.toString(),
          album: song.album ?? "Unknown Album",
          title: song.title,
          artist: song.artist ?? "Unknown Artist",
          duration: Duration(milliseconds: song.duration ?? 0),
          artUri: artUri,
        ),
      );
    }, onError: (Object e) => debugPrint('sequence state error: $e'));
  }

  int _failedInARow = 0;

  /// A file that cannot be played (deleted, corrupt, unreadable): move on to
  /// the next song instead of stalling, but give up once a whole queue's worth
  /// has failed in a row.
  void _onPlaybackError(Object error, StackTrace stack) {
    debugPrint('playback error: $error');
    final queueLength = _player.sequence.length;
    if (!_player.hasNext || ++_failedInARow >= queueLength) return;
    unawaited(
      _player.seekToNext().catchError((Object e) {
        debugPrint('could not skip the unplayable song: $e');
      }),
    );
  }

  /// Takes the audio focus for playback that began without [play]; pauses if
  /// another app refuses to give it up.
  Future<void> _ensureFocus() async {
    try {
      if (!await _takeFocus() && _player.playing) await _player.pause();
    } catch (e) {
      debugPrint('could not take audio focus: $e');
    }
  }

  AudioPlayer get player => _player;
  AndroidLoudnessEnhancer get enhancer => _enhancer;

  /// The player as the focus controller sees it.
  late final FocusTarget focusTarget = _HandlerFocusTarget(this);

  // ------------------------------------------------------------- Levels

  double get _volume =>
      (_fade * _gain * _duck * _preamp * _crossfadeLevel).clamp(0, 1);

  Future<void> _pushVolume() => _player.setVolume(_volume);

  Future<void> _setFade(double v) {
    _fade = v;
    return _pushVolume();
  }

  Future<void> _pushLoudness() => _enhancer.setTargetGain(_loudnessDb);

  /// The user's volume boost, in dB (Sound > Effects).
  Future<void> setUserBoost(double db) {
    _userBoostDb = db;
    return _pushLoudness();
  }

  /// The ReplayGain for the current track, in dB. A cut lowers the volume; a
  /// lift goes through the loudness enhancer, since a player's volume cannot
  /// go above full.
  Future<void> setReplayGain(double db) async {
    _replayGainDb = db;
    _gain = db < 0 ? math.pow(10, db / 20).toDouble() : 1;
    await _pushVolume();
    await _pushLoudness();
  }

  /// Headroom for the equalizer: a cut of [db] (zero or negative) so boosted
  /// bands do not clip. A player's volume cannot go above full, so a positive
  /// value does nothing.
  Future<void> setPreamp(double db) {
    _preamp = db >= 0 ? 1 : math.pow(10, db / 20).toDouble();
    return _pushVolume();
  }

  /// Lowers or restores the volume for a short interruption.
  Future<void> setDucked(bool ducked) {
    _duck = ducked ? _duckLevel : 1;
    return _pushVolume();
  }

  /// Takes the audio focus. False if another app refused to give it up.
  Future<bool> _takeFocus() async {
    final session = _session;
    if (session == null) return true;
    return session.setActive(true);
  }

  // --------------------------------------------------------------- Fades

  /// Moves the fade level from [from] to [to]; a newer play/pause (a different
  /// [id]) cancels it.
  Future<void> _ramp(
    double from,
    double to,
    int id, {
    Duration duration = _fadeDuration,
    int steps = _fadeSteps,
  }) async {
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(duration ~/ steps);
      if (id != _fadeId) return;
      await _setFade(from + (to - from) * i / steps);
    }
  }

  @override
  Future<void> play() async {
    focus?.userChangedPlayback();
    if (!await _takeFocus()) return;
    final id = ++_fadeId;
    if (fadeEnabled) {
      unawaited(_setFade(0));
      unawaited(_ramp(0, 1, id));
    } else {
      unawaited(_setFade(1));
    }
    return _player.play();
  }

  @override
  Future<void> pause() async {
    focus?.userChangedPlayback();
    crossfader.cancel();
    final id = ++_fadeId;
    if (fadeEnabled && _player.playing) {
      await _ramp(_fade, 0, id);
      if (id != _fadeId) return;
    }
    await _player.pause();
    await _setFade(1);
  }

  /// Fades out slowly and pauses: for the sleep timer, which should not cut the
  /// music off. Works whether or not the play/pause fade is on.
  Future<void> fadeOutAndPause({
    Duration duration = const Duration(seconds: 4),
  }) async {
    crossfader.cancel();
    final id = ++_fadeId;
    await _ramp(_fade, 0, id, duration: duration, steps: 20);
    if (id != _fadeId) return;
    await _player.pause();
    await _setFade(1);
  }

  @override
  Future<void> stop() {
    crossfader.cancel();
    _fadeId++;
    unawaited(_setFade(1));
    return _player.stop();
  }

  @override
  Future<void> seek(Duration position) {
    crossfader.cancel();
    return _player.seek(position);
  }

  @override
  Future<void> skipToNext() {
    crossfader.cancel();
    return _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() {
    crossfader.cancel();
    return _player.seekToPrevious();
  }
}

class _HandlerFocusTarget implements FocusTarget {
  _HandlerFocusTarget(this._h);
  final WavvyAudioHandler _h;

  @override
  bool get playing => _h._player.playing;

  @override
  Future<void> pause() {
    // A call or unplugged headphones: stop the incoming crossfade track too.
    _h.crossfader.cancel();
    return _h._player.pause();
  }

  @override
  Future<void> play() => _h.play();

  @override
  Future<void> setDucked(bool ducked) => _h.setDucked(ducked);
}
