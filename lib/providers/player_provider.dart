import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/utils/player.utils.dart';
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

final loudnessEnhancerProvider = Provider<AndroidLoudnessEnhancer>(
  (ref) => ref.watch(audioHandlerProvider).enhancer,
);

/// Playback state (replaces AudioController's queue / currentSong /
/// currentIndex / isPlaying / shuffle / loop / sleepTimerMinutes).
class PlayerState {
  final List<SongModel> queue;
  final SongModel? currentSong;
  final int currentIndex; // -1 when nothing is loaded
  final bool isPlaying;
  final bool isShuffleModeEnabled;
  final LoopMode loopMode;
  final int? sleepTimerMinutes;

  const PlayerState({
    this.queue = const [],
    this.currentSong,
    this.currentIndex = -1,
    this.isPlaying = false,
    this.isShuffleModeEnabled = false,
    this.loopMode = LoopMode.off,
    this.sleepTimerMinutes,
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
  );
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

/// Port of the playback half of AudioController.
class PlayerNotifier extends Notifier<PlayerState> {
  // ignore: deprecated_member_use
  ConcatenatingAudioSource? _effectivePlaylist;
  Timer? _sleepTimer;

  AudioPlayer get _player => ref.read(audioPlayerProvider);

  @override
  PlayerState build() {
    final player = ref.read(audioPlayerProvider);

    final stateSub = player.playerStateStream.listen((s) {
      if (state.isPlaying != s.playing) {
        state = state.copyWith(isPlaying: s.playing);
      }
    });

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
    });

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

      final sources = newQueue.map((s) => _createAudioSource(s)).toList();
      // ignore: deprecated_member_use
      final playlist = ConcatenatingAudioSource(children: sources);
      _effectivePlaylist = playlist;

      await _player.setAudioSource(playlist, initialIndex: index);
      _player.play();
    } catch (e) {
      debugPrint("playSong failed: $e");
      AppSnackbar.showErrorSnackBar(
        "Playback error",
        "Could not play ${song.title}.",
      );
    }
  }

  Future<void> addToQueue(SongModel song) async {
    final playlist = _effectivePlaylist;
    if (playlist == null) {
      playSong(song, contextList: [song]);
      return;
    }
    state = state.copyWith(queue: [...state.queue, song]);
    await playlist.add(_createAudioSource(song));

    AppSnackbar.showSnackbar("Added to Queue", song.title);
  }

  Future<void> playNext(SongModel song) async {
    final playlist = _effectivePlaylist;
    if (playlist == null || state.currentIndex == -1) {
      playSong(song, contextList: [song]);
      return;
    }

    final insertIndex = state.currentIndex + 1;
    final newQueue = List<SongModel>.from(state.queue)
      ..insert(insertIndex, song);
    state = state.copyWith(queue: newQueue);
    await playlist.insert(insertIndex, _createAudioSource(song));

    AppSnackbar.showSnackbar("Will play next", song.title);
  }

  AudioSource _createAudioSource(SongModel song) {
    return AudioSource.uri(Uri.parse(song.uri!), tag: song);
  }

  // ---------------------------------------------------------------- Controls

  void togglePlay() => state.isPlaying ? _player.pause() : _player.play();

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

  Future<void> toggleShuffle() async {
    final enable = !state.isShuffleModeEnabled;
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

  void setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();

    if (minutes == null) {
      state = state.copyWith(clearSleepTimer: true);
      AppSnackbar.showSnackbar("Sleep Timer", "Timer cancelled");
      return;
    }

    state = state.copyWith(sleepTimerMinutes: minutes);

    AppSnackbar.showSnackbar(
      "Sleep Timer",
      "Music will stop in $minutes minutes",
    );

    _sleepTimer = Timer(Duration(minutes: minutes), () {
      _player.pause();
      state = state.copyWith(clearSleepTimer: true);
    });
  }

  void toggleVolumeBoost() {
    final enhancer = ref.read(loudnessEnhancerProvider);
    if (enhancer.targetGain == 1.0) {
      enhancer.setTargetGain(12.0);
    } else {
      enhancer.setTargetGain(1.0);
    }
  }

  Future<void> deleteSong(SongModel song) async {
    try {
      final file = File(song.data);
      if (!await file.exists()) {
        AppSnackbar.showErrorSnackBar(
          "Not found",
          "${song.title} no longer exists on the device.",
        );
        return;
      }

      await file.delete();

      // Remove from the live player queue too, so the player and the UI
      // queue stay in sync. Removing the playing source makes just_audio
      // advance on its own.
      for (int i = state.queue.length - 1; i >= 0; i--) {
        if (state.queue[i].id != song.id) continue;
        state = state.copyWith(
          queue: List<SongModel>.from(state.queue)..removeAt(i),
        );
        final playlist = _effectivePlaylist;
        if (playlist != null && i < playlist.length) {
          await playlist.removeAt(i);
        }
      }
      if (state.queue.isEmpty) {
        await _player.stop();
        state = state.copyWith(clearCurrentSong: true, currentIndex: -1);
      }

      ref.read(libraryProvider.notifier).removeSongLocally(song.id);

      AppSnackbar.showSnackbar("Deleted", "${song.title} removed from device.");

      // MediaStore may keep a stale row for the deleted file.
      await ref.read(libraryProvider.notifier).fetchAllSongs();
    } catch (e) {
      debugPrint("deleteSong failed: $e");
      AppSnackbar.showErrorSnackBar(
        "Permission Denied",
        "Cannot delete file on this Android version.",
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

  String getSongInfo(SongModel song) {
    return """
Title: ${song.title}
Artist: ${song.artist ?? '<unknown>'}
Album: ${song.album ?? '<unknown>'}
Duration: ${PlayerUtils.formatDuration(Duration(milliseconds: song.duration ?? 0))}
Size: ${PlayerUtils.formatBytes(song.size, 2)}
Path: ${song.data}
Format: ${song.fileExtension}
    """;
  }
}
