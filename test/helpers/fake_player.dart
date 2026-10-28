import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:on_audio_query/on_audio_query.dart';

class MemoryPlayer extends Fake implements audio.AudioPlayer {
  final _states = StreamController<audio.PlayerState>.broadcast(sync: true);
  final _sequences = StreamController<audio.SequenceState>.broadcast(
    sync: true,
  );
  List<audio.AudioSource> sources = [];
  bool shuffled = false;
  List<int> shuffleOrder = [];

  /// The shuffle order the last [setAudioSources] was given.
  audio.ShuffleOrder? lastShuffleOrder;

  /// Makes the next source change throw, to exercise rollback.
  bool failNextEdit = false;

  bool failNextLoad = false;

  // What the tests look at.
  int? lastInitialIndex;
  Duration? lastInitialPosition;
  int playCalls = 0;
  final seeks = <Duration>[];
  bool isPlayingNow = false;
  audio.LoopMode loop = audio.LoopMode.off;
  double speedValue = 1;
  double pitchValue = 1;

  @override
  bool get playing => isPlayingNow;
  @override
  audio.LoopMode get loopMode => loop;
  @override
  double get speed => speedValue;
  @override
  double get pitch => pitchValue;

  @override
  Future<void> setLoopMode(audio.LoopMode mode) async => loop = mode;

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async => shuffled = enabled;

  /// How many times the shuffle order was remade.
  int reshuffles = 0;
  @override
  Future<void> shuffle() async => reshuffles++;

  final _speedChanges = StreamController<double>.broadcast(sync: true);
  final _pitchChanges = StreamController<double>.broadcast(sync: true);

  @override
  Stream<double> get speedStream => _speedChanges.stream;
  @override
  Stream<double> get pitchStream => _pitchChanges.stream;

  @override
  Future<void> setSpeed(double v) async {
    speedValue = v;
    _speedChanges.add(v);
  }

  @override
  Future<void> setPitch(double v) async {
    pitchValue = v;
    _pitchChanges.add(v);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) seeks.add(position);
  }

  /// Emits a play/pause state, as the real player does.
  void setPlaying(bool value) {
    isPlayingNow = value;
    _states.add(audio.PlayerState(value, audio.ProcessingState.ready));
  }

  @override
  Stream<audio.PlayerState> get playerStateStream => _states.stream;
  @override
  Stream<audio.SequenceState> get sequenceStateStream => _sequences.stream;
  @override
  List<int> get effectiveIndices =>
      shuffled ? shuffleOrder : List.generate(sources.length, (i) => i);

  @override
  Future<Duration?> setAudioSources(
    List<audio.AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    audio.ShuffleOrder? shuffleOrder,
  }) async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    sources = [...audioSources];
    lastShuffleOrder = shuffleOrder;
    lastInitialIndex = initialIndex;
    lastInitialPosition = initialPosition;
    emit(initialIndex ?? 0);
    return const Duration(minutes: 3);
  }

  void _check() {
    if (failNextEdit) {
      failNextEdit = false;
      throw StateError('rejected');
    }
  }

  @override
  Future<void> addAudioSource(audio.AudioSource audioSource) async {
    _check();
    sources.add(audioSource);
  }

  @override
  Future<void> insertAudioSource(
    int index,
    audio.AudioSource audioSource,
  ) async {
    _check();
    sources.insert(index, audioSource);
  }

  @override
  Future<void> removeAudioSourceAt(int index) async {
    _check();
    sources.removeAt(index);
  }

  @override
  Future<void> removeAudioSourceRange(int start, int end) async {
    _check();
    sources.removeRange(start, end);
  }

  @override
  Future<void> moveAudioSource(int currentIndex, int newIndex) async {
    _check();
    sources.insert(newIndex, sources.removeAt(currentIndex));
  }

  void emit(int index) => _sequences.add(
    audio.SequenceState(
      sequence: sources.cast<audio.IndexedAudioSource>(),
      currentIndex: index,
      shuffleIndices: effectiveIndices,
      shuffleModeEnabled: shuffled,
      loopMode: audio.LoopMode.off,
    ),
  );
  @override
  Future<void> play() async {
    playCalls++;
    setPlaying(true);
  }

  @override
  Future<void> stop() async =>
      _states.add(audio.PlayerState(false, audio.ProcessingState.idle));
  List<int> get nativeOrder => sources
      .cast<audio.IndexedAudioSource>()
      .map((s) => (s.tag as SongModel).id)
      .toList();
  Future<void> close() async {
    await _states.close();
    await _sequences.close();
  }
}

SongModel testSong(
  int id, {
  int? albumId,
  String? artist,
  int duration = 180000,
}) => SongModel({
  '_id': id,
  '_data': '/music/${albumId ?? 0}/$id.mp3',
  '_uri': 'content://media/$id',
  'title': 'Track $id',
  'artist': artist ?? 'Artist',
  'album_id': albumId,
  'duration': duration,
});
