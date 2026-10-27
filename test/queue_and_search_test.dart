import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/providers/player_provider.dart';

class _MemoryPlayer extends Fake implements audio.AudioPlayer {
  final _states = StreamController<audio.PlayerState>.broadcast(sync: true);
  final _sequences = StreamController<audio.SequenceState>.broadcast(
    sync: true,
  );
  // ignore: deprecated_member_use
  late audio.ConcatenatingAudioSource source;
  @override
  Stream<audio.PlayerState> get playerStateStream => _states.stream;
  @override
  Stream<audio.SequenceState> get sequenceStateStream => _sequences.stream;
  @override
  Future<Duration?> setAudioSource(
    audio.AudioSource value, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    // ignore: deprecated_member_use
    source = value as audio.ConcatenatingAudioSource;
    emit(initialIndex ?? 0);
    return const Duration(minutes: 3);
  }

  void emit(int index) => _sequences.add(
    audio.SequenceState(
      sequence: source.sequence,
      currentIndex: index,
      shuffleIndices: List.generate(source.sequence.length, (i) => i),
      shuffleModeEnabled: false,
      loopMode: audio.LoopMode.off,
    ),
  );
  @override
  Future<void> play() async =>
      _states.add(audio.PlayerState(true, audio.ProcessingState.ready));
  @override
  Future<void> stop() async =>
      _states.add(audio.PlayerState(false, audio.ProcessingState.idle));
  List<int> get nativeOrder =>
      source.sequence.map((s) => (s.tag as SongModel).id).toList();
  Future<void> close() async {
    await _states.close();
    await _sequences.close();
  }
}

SongModel _song(int id) => SongModel({
  '_id': id,
  '_data': '/music/$id.mp3',
  '_uri': 'content://media/$id',
  'title': 'Track $id',
  'duration': 180000,
});

class _NoEvents extends DownloadEventsNotifier {
  @override
  DownloadEvent? build() => null;
}

class _ControlledSearch extends YtdlpNotifier {
  final requests = <String, Completer<List<Video>>>{};
  @override
  Future<void> loadExistingDownloads() async {}
  @override
  Future<List<Video>> searchVideos(String query) =>
      (requests[query] = Completer<List<Video>>()).future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('live queue and audio source stay aligned', () {
    late _MemoryPlayer player;
    late ProviderContainer container;
    late PlayerNotifier queue;
    setUp(() async {
      player = _MemoryPlayer();
      container = ProviderContainer(
        overrides: [audioPlayerProvider.overrideWithValue(player)],
      );
      queue = container.read(playerProvider.notifier);
      final songs = [for (int i = 1; i <= 4; i++) _song(i)];
      await queue.playSong(songs[1], contextList: songs);
    });
    tearDown(() async {
      container.dispose();
      await player.close();
    });
    test(
      'reordering uses the final destination index and retains the playing track',
      () async {
        await queue.moveQueueItem(1, 3);
        player.emit(3);
        expect(player.nativeOrder, [1, 3, 4, 2]);
        expect(
          container.read(playerProvider).queue.map((s) => s.id),
          player.nativeOrder,
        );
        expect(container.read(playerProvider).currentSong?.id, 2);
        expect(container.read(playerProvider).currentIndex, 3);
      },
    );
    test('removing an upcoming track updates both lists', () async {
      await queue.removeFromQueue(2);
      expect(player.nativeOrder, [1, 2, 4]);
      expect(container.read(playerProvider).queue.map((s) => s.id), [1, 2, 4]);
      expect(container.read(playerProvider).currentSong?.id, 2);
    });
    test('clear upcoming keeps history and the current track', () async {
      await queue.clearUpcoming();
      expect(player.nativeOrder, [1, 2]);
      expect(container.read(playerProvider).queue.map((s) => s.id), [1, 2]);
    });
    test(
      'invalid edits are ignored and the last removal clears playback',
      () async {
        await queue.moveQueueItem(-1, 2);
        await queue.removeFromQueue(99);
        expect(player.nativeOrder, [1, 2, 3, 4]);
        for (int i = 3; i >= 0; i--) {
          await queue.removeFromQueue(i);
        }
        expect(player.nativeOrder, isEmpty);
        expect(container.read(playerProvider).currentSong, isNull);
        expect(container.read(playerProvider).currentIndex, -1);
        expect(container.read(playerProvider).isPlaying, isFalse);
      },
    );
  });

  group('YouTube request state', () {
    late ProviderContainer container;
    late _ControlledSearch search;
    setUp(() {
      search = _ControlledSearch();
      container = ProviderContainer(
        overrides: [
          downloadEventsProvider.overrideWith(_NoEvents.new),
          ytdlpProvider.overrideWith(() => search),
        ],
      );
      container.read(ytdlpProvider);
    });
    tearDown(() => container.dispose());
    test('older responses cannot replace a newer request', () async {
      final older = search.search('older');
      final newer = search.search('newer');
      search.requests['older']!.complete([]);
      await older;
      expect(container.read(ytdlpProvider).searchQuery, 'newer');
      expect(container.read(ytdlpProvider).isSearching, isTrue);
      search.requests['newer']!.complete([]);
      await newer;
      expect(container.read(ytdlpProvider).isSearching, isFalse);
      expect(container.read(ytdlpProvider).hasSearched, isTrue);
    });
    test('failure leaves a retryable query and no loading state', () async {
      final request = search.search('music');
      search.requests['music']!.completeError(StateError('offline'));
      await request;
      final state = container.read(ytdlpProvider);
      expect(state.searchError, isNotEmpty);
      expect(state.searchQuery, 'music');
      expect(state.isSearching, isFalse);
    });
    test('disposing a pending search prevents late state writes', () async {
      final request = search.search('music');
      container.dispose();
      search.requests['music']!.complete([]);
      await request;
    });
  });
}
