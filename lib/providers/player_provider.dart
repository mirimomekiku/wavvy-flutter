import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/media_store.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/db/db.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/session.dart';
import 'package:wavvy/playback/smart_shuffle.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

/// Overridden in main() with the initialized audio handler.
final audioHandlerProvider = Provider<WavvyAudioHandler>(
  (ref) => throw UnimplementedError('override audioHandlerProvider in main'),
);

/// The underlying just_audio player (for speedStream, setSpeed,
/// androidAudioSessionIdStream, etc.).
final audioPlayerProvider = Provider<AudioPlayer>(
  (ref) => ref.watch(audioHandlerProvider).player,
);

/// What the sleep timer is waiting for.
enum SleepMode { off, minutes, endOfTrack, endOfQueue, afterTracks }

/// How often each song was played (song id to count), for the smart shuffle.
/// Overridden in tests.
final playCountsLoaderProvider = Provider<Future<Map<int, int>> Function()>(
  (ref) => () async {
    final rows = await DbHelper().getMostPlayed(100000);
    return {
      for (final r in rows) r['song_id'] as int: (r['play_count'] as int?) ?? 0,
    };
  },
);

/// Playback state: queue, current song and index, play/shuffle/repeat and the
/// sleep timer.
class PlayerState {
  final List<SongModel> queue;
  final SongModel? currentSong;
  final int currentIndex; // -1 when nothing is loaded
  final bool isPlaying;
  final bool isShuffleModeEnabled;
  final LoopMode loopMode;
  final int? sleepTimerMinutes;
  final SleepMode sleepMode;

  /// When a minutes timer will stop playback.
  final DateTime? sleepEndsAt;

  /// For [SleepMode.afterTracks]: tracks still to play, counting the current one.
  final int? sleepTracksLeft;

  const PlayerState({
    this.queue = const [],
    this.currentSong,
    this.currentIndex = -1,
    this.isPlaying = false,
    this.isShuffleModeEnabled = false,
    this.loopMode = LoopMode.off,
    this.sleepTimerMinutes,
    this.sleepMode = SleepMode.off,
    this.sleepEndsAt,
    this.sleepTracksLeft,
  });

  PlayerState copyWith({
    List<SongModel>? queue,
    SongModel? currentSong,
    bool clearCurrentSong = false,
    int? currentIndex,
    bool? isPlaying,
    bool? isShuffleModeEnabled,
    LoopMode? loopMode,
    int? sleepTimerMinutes,
    SleepMode? sleepMode,
    DateTime? sleepEndsAt,
    int? sleepTracksLeft,
    bool clearSleepTimer = false,
  }) => PlayerState(
    queue: queue ?? this.queue,
    currentSong: clearCurrentSong ? null : (currentSong ?? this.currentSong),
    currentIndex: currentIndex ?? this.currentIndex,
    isPlaying: isPlaying ?? this.isPlaying,
    isShuffleModeEnabled: isShuffleModeEnabled ?? this.isShuffleModeEnabled,
    loopMode: loopMode ?? this.loopMode,
    sleepTimerMinutes: clearSleepTimer
        ? null
        : (sleepTimerMinutes ?? this.sleepTimerMinutes),
    sleepMode: clearSleepTimer ? SleepMode.off : (sleepMode ?? this.sleepMode),
    sleepEndsAt: clearSleepTimer ? null : (sleepEndsAt ?? this.sleepEndsAt),
    sleepTracksLeft: clearSleepTimer
        ? null
        : (sleepTracksLeft ?? this.sleepTracksLeft),
  );
}

/// One planned change to the queue: the queue it results in, and the call that
/// makes the player match.
class _QueueEdit {
  final List<SongModel> queue;
  final Future<void> Function() apply;

  const _QueueEdit(this.queue, this.apply);
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);

/// Current playback position / total duration. Separate from [playerProvider]
/// so the high-frequency position updates don't rebuild everything that reads
/// player state. Fed from audioPlayer.positionStream / durationStream.
final positionProvider = NotifierProvider<PositionNotifier, Duration>(
  PositionNotifier.new,
);
final durationProvider = NotifierProvider<DurationNotifier, Duration>(
  DurationNotifier.new,
);

class PositionNotifier extends Notifier<Duration> {
  @override
  Duration build() {
    final sub = ref.read(audioPlayerProvider).positionStream.listen((p) {
      state = p;
    });
    ref.onDispose(sub.cancel);
    return Duration.zero;
  }
}

class DurationNotifier extends Notifier<Duration> {
  @override
  Duration build() {
    final sub = ref.read(audioPlayerProvider).durationStream.listen((d) {
      state = d ?? Duration.zero;
    });
    ref.onDispose(sub.cancel);
    return Duration.zero;
  }
}

/// Playback: the queue, transport, shuffle/repeat, sleep timer and deletion.
///
/// The queue is kept in the same order as the player's audio sources, so a
/// queue index is also an audio-source index (shuffle only changes the order
/// the player visits them in). Every queue change goes through [_edit], which
/// runs one change at a time, updates [PlayerState.queue] first and rolls it
/// back if the player rejects the change.
class PlayerNotifier extends Notifier<PlayerState> {
  bool _hasSources = false;
  Timer? _sleepTimer;
  Future<void> _editTail = Future.value();

  AudioPlayer get _player => ref.read(audioPlayerProvider);

  @override
  PlayerState build() {
    final player = ref.read(audioPlayerProvider);

    final stateSub = player.playerStateStream.listen(
      (s) {
        if (state.isPlaying != s.playing) {
          state = state.copyWith(isPlaying: s.playing);
        }
      },
      onError: (Object e) {
        // The handler skips to the next song; this is just the notice.
        debugPrint('player error: $e');
        AppSnackbar.showErrorSnackBar(
          'Playback error',
          'A song could not be played.',
        );
      },
    );

    final seqSub = player.sequenceStateStream.listen((seq) {
      final source = seq.currentSource;
      if (source == null) return;
      final tag = source.tag;
      if (tag is! SongModel) return;

      var next = state;
      if (next.currentSong?.id != tag.id) {
        next = next.copyWith(currentSong: tag);
      }
      final idx = seq.currentIndex;
      if (idx != null && next.currentIndex != idx) {
        next = next.copyWith(currentIndex: idx);
      }
      next = next.copyWith(
        isShuffleModeEnabled: seq.shuffleModeEnabled,
        loopMode: seq.loopMode,
      );
      state = next;
      _countSleepTrack();
    }, onError: (Object e) => debugPrint('sequence error: $e'));

    ref.onDispose(() {
      stateSub.cancel();
      seqSub.cancel();
      _sleepTimer?.cancel();
    });

    return const PlayerState();
  }

  Future<void> playSong(SongModel song, {List<SongModel>? contextList}) async {
    try {
      final List<SongModel> newQueue =
          contextList ?? List.from(ref.read(libraryProvider).filteredSongs);
      final index = newQueue.indexWhere((s) => s.id == song.id);

      if (index == -1) return;

      state = state.copyWith(queue: List<SongModel>.from(newQueue));

      await _player.setAudioSources(
        [for (final s in newQueue) _createAudioSource(s)],
        initialIndex: index,
        shuffleOrder: _newShuffleOrder(),
      );
      _hasSources = true;
      // play() completes when playback stops, so it is deliberately not awaited.
      unawaited(_player.play());
    } catch (e) {
      debugPrint("playSong failed: $e");
      AppSnackbar.showErrorSnackBar(
        "Playback error",
        "Could not play ${song.title}.",
      );
    }
  }

  Future<void> addToQueue(SongModel song) async {
    if (!_hasSources) {
      await playSong(song, contextList: [song]);
      return;
    }
    final added = await _edit(
      (queue) => _QueueEdit([
        ...queue,
        song,
      ], () => _player.addAudioSource(_createAudioSource(song))),
    );
    if (added) AppSnackbar.showSuccess("Added to Queue", song.title);
  }

  /// Inserts [song] right after the current one. With shuffle on, just_audio
  /// decides where an inserted track falls in the shuffled order, so the song
  /// is queued but not guaranteed to be the very next to play.
  Future<void> playNext(SongModel song) async {
    if (!_hasSources || state.currentIndex == -1) {
      await playSong(song, contextList: [song]);
      return;
    }
    final added = await _edit((queue) {
      final at = (state.currentIndex + 1).clamp(0, queue.length);
      return _QueueEdit(
        [...queue]..insert(at, song),
        () => _player.insertAudioSource(at, _createAudioSource(song)),
      );
    });
    if (added) AppSnackbar.showSuccess("Will play next", song.title);
  }

  /// Runs queue changes one at a time. [plan] sees the queue as it is when the
  /// change's turn comes, and returns null to do nothing. Resolves true when
  /// the change was applied.
  Future<bool> _edit(_QueueEdit? Function(List<SongModel> queue) plan) {
    final done = _editTail.then((_) async {
      final edit = plan(state.queue);
      if (edit == null) return false;
      final previous = state.queue;
      state = state.copyWith(queue: edit.queue);
      try {
        await edit.apply();
        if (edit.queue.isEmpty) {
          await _player.stop();
          _hasSources = false;
          state = state.copyWith(clearCurrentSong: true, currentIndex: -1);
        }
        return true;
      } catch (e) {
        debugPrint("queue edit failed: $e");
        state = state.copyWith(queue: previous);
        AppSnackbar.showErrorSnackBar(
          'Queue unchanged',
          'Could not update the play queue.',
        );
        return false;
      }
    });
    _editTail = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<void> removeFromQueue(int index) => _edit((queue) {
    if (!_hasSources || index < 0 || index >= queue.length) return null;
    return _QueueEdit(
      [...queue]..removeAt(index),
      () => _player.removeAudioSourceAt(index),
    );
  });

  /// Removes everything that will play after the current track, in the order
  /// the player will visit it (which differs from queue order when shuffled).
  Future<void> clearUpcoming() => _edit((queue) {
    final upcoming = _upcomingIndices(queue.length);
    if (!_hasSources || upcoming.isEmpty) return null;
    final doomed = upcoming.toSet();
    return _QueueEdit([
      for (var i = 0; i < queue.length; i++)
        if (!doomed.contains(i)) queue[i],
    ], () => _removeIndices(upcoming));
  });

  List<int> _upcomingIndices(int length) {
    final current = state.currentIndex;
    if (current < 0) return const [];
    if (!state.isShuffleModeEnabled) {
      return [for (var i = current + 1; i < length; i++) i];
    }
    final order = _player.effectiveIndices;
    final at = order.indexOf(current);
    return at < 0 ? const [] : order.sublist(at + 1);
  }

  Future<void> _removeIndices(Iterable<int> indices) async {
    // Highest first so earlier removals don't shift the later ones.
    for (final i in indices.toList()..sort((a, b) => b.compareTo(a))) {
      await _player.removeAudioSourceAt(i);
    }
  }

  Future<void> moveQueueItem(int from, int to) => _edit((queue) {
    if (!_hasSources ||
        from < 0 ||
        from >= queue.length ||
        to < 0 ||
        to >= queue.length ||
        from == to) {
      return null;
    }
    final next = [...queue];
    next.insert(to, next.removeAt(from));
    return _QueueEdit(next, () => _player.moveAudioSource(from, to));
  });

  AudioSource _createAudioSource(SongModel song) {
    return AudioSource.uri(Uri.parse(song.uri!), tag: song);
  }

  // ---------------------------------------------------------------- Controls

  void togglePlay() {
    final handler = ref.read(audioHandlerProvider);
    unawaited(state.isPlaying ? handler.pause() : handler.play());
  }

  void next() {
    if (_player.hasNext) _player.seekToNext();
  }

  void previous() {
    if (_player.hasPrevious) _player.seekToPrevious();
  }

  Future<void> seek(Duration position, {bool relative = false}) async {
    if (relative) {
      final current = ref.read(positionProvider).inMilliseconds;
      final delta = position.inMilliseconds;
      final newPos = current + delta;

      final max = ref.read(durationProvider).inMilliseconds;
      final clamped = newPos.clamp(0, max);

      await _player.seek(Duration(milliseconds: clamped));
    } else {
      await _player.seek(position);
    }
  }

  /// The order the player shuffles in: smart (artists apart, liked and less
  /// played songs earlier) unless the setting is off.
  ShuffleOrder _newShuffleOrder() {
    if (!ref.read(settingsProvider).smartShuffle) return DefaultShuffleOrder();
    return SmartShuffleOrder(
      describe: (index) {
        final queue = state.queue;
        if (index < 0 || index >= queue.length) {
          return ShuffleCandidate(index: index);
        }
        final song = queue[index];
        final artist = (song.artist ?? '').trim().toLowerCase();
        return ShuffleCandidate(
          index: index,
          artist: artist == '<unknown>' ? '' : artist,
          weight: shuffleWeight(
            plays: _playCounts[song.id] ?? 0,
            liked: ref.read(favoritesProvider).containsKey(song.id),
          ),
        );
      },
    );
  }

  Map<int, int> _playCounts = const {};

  Future<void> _loadPlayCounts() async {
    if (!ref.read(settingsProvider).smartShuffle) return;
    try {
      _playCounts = await ref.read(playCountsLoaderProvider)();
    } catch (e) {
      // Without play counts the shuffle still keeps artists apart.
      debugPrint('could not load play counts: $e');
    }
  }

  Future<void> toggleShuffle() async {
    final enable = !state.isShuffleModeEnabled;
    if (enable && _hasSources) {
      // A fresh order each time shuffle is turned on, with the current song
      // first.
      await _loadPlayCounts();
      await _player.shuffle();
    }
    await _player.setShuffleModeEnabled(enable);
    state = state.copyWith(isShuffleModeEnabled: enable);
  }

  Future<void> cycleLoopMode() async {
    switch (state.loopMode) {
      case LoopMode.off:
        await _player.setLoopMode(LoopMode.all);
        break;
      case LoopMode.all:
        await _player.setLoopMode(LoopMode.one);
        break;
      case LoopMode.one:
        await _player.setLoopMode(LoopMode.off);
        break;
    }
    state = state.copyWith(loopMode: _player.loopMode);
  }

  // ------------------------------------------------------------------ Extras

  /// Stops playback after [minutes], or cancels the timer when null.
  void setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    _sleepFiring = false;

    if (minutes == null) {
      state = state.copyWith(clearSleepTimer: true);
      AppSnackbar.showSnackbar("Sleep Timer", "Timer cancelled");
      return;
    }

    state = state.copyWith(
      sleepTimerMinutes: minutes,
      sleepMode: SleepMode.minutes,
      sleepEndsAt: DateTime.now().add(Duration(minutes: minutes)),
    );

    AppSnackbar.showSnackbar(
      "Sleep Timer",
      "Music will stop in $minutes minutes",
    );

    _sleepTimer = Timer(Duration(minutes: minutes), () => _sleepNow());
  }

  /// Stops at the end of the [count]th track from now, counting the one that
  /// is playing.
  void setSleepAfterTracks(int count) {
    assert(count >= 1);
    _sleepTimer?.cancel();
    _sleepFiring = false;
    _sleepTrackKey = (state.currentIndex, state.currentSong?.id);
    state = state
        .copyWith(clearSleepTimer: true)
        .copyWith(sleepMode: SleepMode.afterTracks, sleepTracksLeft: count);
    AppSnackbar.showSnackbar(
      "Sleep Timer",
      count == 1
          ? "Music will stop after this track"
          : "Music will stop after $count tracks",
    );
  }

  /// The track the "after N tracks" timer last counted.
  (int, int?)? _sleepTrackKey;

  /// Counts a track change for "after N tracks", and stops if that was the last.
  void _countSleepTrack() {
    if (state.sleepMode != SleepMode.afterTracks) return;
    final key = (state.currentIndex, state.currentSong?.id);
    if (key == _sleepTrackKey) return;
    _sleepTrackKey = key;
    final left = (state.sleepTracksLeft ?? 1) - 1;
    if (left <= 0) {
      // The last track was skipped (or ended before the fade began).
      _sleepNow(fade: const Duration(seconds: 2));
      return;
    }
    state = state.copyWith(sleepTracksLeft: left);
  }

  /// Whether a shake should add sleep time now: the timer is in its last
  /// minute, or has just stopped the music.
  bool get sleepNearEnd {
    if (_sleepFiring) return true;
    switch (state.sleepMode) {
      case SleepMode.off || SleepMode.endOfQueue:
        return false;
      case SleepMode.minutes:
        final ends = state.sleepEndsAt;
        return ends != null &&
            ends.difference(DateTime.now()) <= const Duration(minutes: 1);
      case SleepMode.endOfTrack || SleepMode.afterTracks:
        if ((state.sleepTracksLeft ?? 1) > 1) return false;
        final duration = ref.read(durationProvider);
        final remaining = duration - ref.read(positionProvider);
        return duration > Duration.zero &&
            remaining <= const Duration(minutes: 1);
    }
  }

  /// Adds time to the sleep timer: [minutes] more on a minutes timer, one more
  /// track on a track timer. If the timer has only just stopped the music,
  /// resumes it with a new timer. Returns false when there is nothing to add
  /// to (no timer, or "end of the queue").
  bool extendSleep({int minutes = 10}) {
    if (_sleepFiring) {
      _sleepFiring = false;
      unawaited(ref.read(audioHandlerProvider).play());
      setSleepTimer(minutes);
      return true;
    }
    switch (state.sleepMode) {
      case SleepMode.off || SleepMode.endOfQueue:
        return false;
      case SleepMode.minutes:
        final ends = (state.sleepEndsAt ?? DateTime.now()).add(
          Duration(minutes: minutes),
        );
        _sleepTimer?.cancel();
        _sleepTimer = Timer(ends.difference(DateTime.now()), _sleepNow);
        state = state.copyWith(sleepEndsAt: ends);
        AppSnackbar.showSnackbar("Sleep Timer", "Added $minutes minutes");
        return true;
      case SleepMode.endOfTrack:
        _sleepTrackKey = (state.currentIndex, state.currentSong?.id);
        state = state.copyWith(
          sleepMode: SleepMode.afterTracks,
          sleepTracksLeft: 2,
        );
        AppSnackbar.showSnackbar("Sleep Timer", "One more track");
        return true;
      case SleepMode.afterTracks:
        state = state.copyWith(
          sleepTracksLeft: (state.sleepTracksLeft ?? 1) + 1,
        );
        AppSnackbar.showSnackbar("Sleep Timer", "One more track");
        return true;
    }
  }

  /// Stops at the end of the current track, or of the queue.
  void setSleepAtEnd(SleepMode mode) {
    assert(mode == SleepMode.endOfTrack || mode == SleepMode.endOfQueue);
    _sleepTimer?.cancel();
    _sleepFiring = false;
    state = state.copyWith(clearSleepTimer: true).copyWith(sleepMode: mode);
    AppSnackbar.showSnackbar(
      "Sleep Timer",
      mode == SleepMode.endOfTrack
          ? "Music will stop after this track"
          : "Music will stop after the last track in the queue",
    );
  }

  bool _sleepFiring = false;

  /// Ends playback now with a slow fade, and clears the timer.
  void _sleepNow({Duration fade = const Duration(seconds: 4)}) {
    if (_sleepFiring) return;
    _sleepFiring = true;
    state = state.copyWith(clearSleepTimer: true);
    unawaited(ref.read(audioHandlerProvider).fadeOutAndPause(duration: fade));
    // Ready for the next timer.
    Future<void>.delayed(fade + const Duration(milliseconds: 500), () {
      _sleepFiring = false;
    });
  }

  /// Whether the current track is the last one that will play: the last in the
  /// queue, or the last in the shuffled order.
  bool get _onLastTrack {
    final index = state.currentIndex;
    if (index < 0 || state.queue.isEmpty) return false;
    if (state.isShuffleModeEnabled) {
      final order = _player.effectiveIndices;
      return order.isNotEmpty && order.last == index;
    }
    return index == state.queue.length - 1;
  }

  /// Called as playback moves, to end an "end of track" or "end of queue" sleep
  /// timer with a fade as the track runs out. [lead] is extra time to start
  /// early, so a crossfade that is about to begin does not get in the way.
  void onPosition(
    Duration position,
    Duration duration, {
    Duration lead = Duration.zero,
  }) {
    final mode = state.sleepMode;
    if (_sleepFiring || !state.isPlaying || duration <= Duration.zero) return;
    if (mode == SleepMode.off || mode == SleepMode.minutes) return;
    if (mode == SleepMode.endOfQueue && !_onLastTrack) return;
    if (mode == SleepMode.afterTracks && (state.sleepTracksLeft ?? 1) > 1) {
      return;
    }
    final remaining = duration - position;
    const fade = Duration(seconds: 4);
    if (remaining > fade + lead) return;
    _sleepNow(
      fade: remaining < fade && remaining > const Duration(seconds: 1)
          ? remaining
          : fade,
    );
  }

  // ----------------------------------------------------------- Last session

  /// Where playback is now, for saving; null when nothing is queued.
  PlaybackSnapshot? snapshot(Duration position) {
    if (state.queue.isEmpty || state.currentIndex < 0) return null;
    return PlaybackSnapshot(
      songIds: [for (final s in state.queue) s.id],
      index: state.currentIndex,
      positionMs: position.inMilliseconds,
      shuffle: state.isShuffleModeEnabled,
      loopMode: state.loopMode.index,
    );
  }

  /// Reopens a saved session, paused. Songs that are no longer in [library] are
  /// dropped. Returns false when nothing could be restored.
  Future<bool> restoreSession(
    PlaybackSnapshot saved,
    List<SongModel> library,
  ) async {
    final byId = {for (final s in library) s.id: s};
    final queue = [
      for (final id in saved.songIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (queue.isEmpty) return false;
    final wasPlaying = saved.currentId;
    var index = queue.indexWhere((s) => s.id == wasPlaying);
    // The song that was playing is gone: start the next one that is left.
    final position = index < 0
        ? Duration.zero
        : Duration(milliseconds: saved.positionMs);
    if (index < 0) index = 0;
    try {
      state = state.copyWith(queue: List<SongModel>.from(queue));
      await _player.setAudioSources(
        [for (final s in queue) _createAudioSource(s)],
        initialIndex: index,
        initialPosition: position,
        shuffleOrder: _newShuffleOrder(),
      );
      _hasSources = true;
      await _player.setLoopMode(
        LoopMode.values[saved.loopMode.clamp(0, LoopMode.values.length - 1)],
      );
      await _player.setShuffleModeEnabled(saved.shuffle);
      return true;
    } catch (e) {
      debugPrint("restoreSession failed: $e");
      // The queue loaded but the loop or shuffle mode did not: keep the queue,
      // which still matches the player's sources.
      if (_hasSources) return true;
      state = state.copyWith(queue: const [], clearCurrentSong: true);
      return false;
    }
  }

  /// Deletes the file through the system's delete confirmation, then removes
  /// the song from the queue and library. Nothing changes if the user declines.
  Future<void> deleteSong(SongModel song) async {
    try {
      final deleted = await ref.read(mediaStoreProvider).deleteAudio(song.id);
      if (!deleted) {
        AppSnackbar.showSnackbar(
          "Not deleted",
          "${song.title} is still on your device.",
        );
        return;
      }

      // Drop every queue entry for the song so the player and the visible
      // queue stay in sync. Removing the playing source makes just_audio
      // advance on its own.
      await _edit((queue) {
        final doomed = [
          for (var i = 0; i < queue.length; i++)
            if (queue[i].id == song.id) i,
        ];
        if (!_hasSources || doomed.isEmpty) return null;
        return _QueueEdit([
          for (final s in queue)
            if (s.id != song.id) s,
        ], () => _removeIndices(doomed));
      });

      ref.read(libraryProvider.notifier).removeSongLocally(song.id);

      AppSnackbar.showSuccess("Deleted", "${song.title} removed from device.");

      // MediaStore may keep a stale row for the deleted file.
      await ref.read(libraryProvider.notifier).fetchAllSongs(silent: true);
    } catch (e) {
      debugPrint("deleteSong failed: $e");
      AppSnackbar.showErrorSnackBar(
        "Could not delete",
        "Android did not allow deleting ${song.title}.",
      );
    }
  }

  /// Replaces a song's model in the queue and, if it is playing, the current
  /// song (used after editing tags so the UI shows the new metadata).
  void replaceSong(SongModel updated) {
    state = state.copyWith(
      queue: [for (final s in state.queue) s.id == updated.id ? updated : s],
      currentSong: state.currentSong?.id == updated.id
          ? updated
          : state.currentSong,
    );
  }
}
