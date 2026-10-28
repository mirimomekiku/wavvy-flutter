import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/downloader/engine.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/downloader/models.dart';
import 'package:wavvy/downloader/search_provider.dart';
import 'package:wavvy/providers/player_provider.dart';

import 'helpers/fake_engine.dart';
import 'helpers/fake_player.dart';

SongModel _song(int id) => SongModel({
  '_id': id,
  '_data': '/music/$id.mp3',
  '_uri': 'content://media/$id',
  'title': 'Track $id',
  'duration': 180000,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('live queue and audio source stay aligned', () {
    late MemoryPlayer player;
    late ProviderContainer container;
    late PlayerNotifier queue;
    setUp(() async {
      // PlayerNotifier reads the settings (smart shuffle).
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      player = MemoryPlayer();
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
    test('clear upcoming follows shuffle order, not queue order', () async {
      // Queue is 1 2 3 4 with 2 playing; shuffle plays 2, then 4, then 1, 3.
      player.shuffled = true;
      player.shuffleOrder = [1, 3, 0, 2];
      player.emit(1);
      await queue.clearUpcoming();
      expect(player.nativeOrder, [2]);
      expect(container.read(playerProvider).queue.map((s) => s.id), [2]);
    });
    test('play next inserts after the current track', () async {
      await queue.playNext(_song(9));
      expect(player.nativeOrder, [1, 2, 9, 3, 4]);
      expect(
        container.read(playerProvider).queue.map((s) => s.id),
        player.nativeOrder,
      );
    });
    test('add to queue appends and keeps both lists aligned', () async {
      await queue.addToQueue(_song(9));
      expect(player.nativeOrder, [1, 2, 3, 4, 9]);
      expect(
        container.read(playerProvider).queue.map((s) => s.id),
        player.nativeOrder,
      );
    });
    test('a rejected change rolls the visible queue back', () async {
      player.failNextEdit = true;
      await queue.addToQueue(_song(9));
      expect(player.nativeOrder, [1, 2, 3, 4]);
      expect(container.read(playerProvider).queue.map((s) => s.id), [
        1,
        2,
        3,
        4,
      ]);
    });
    test('quick successive edits are applied in order, none dropped', () async {
      await Future.wait([
        queue.removeFromQueue(3),
        queue.addToQueue(_song(8)),
        queue.addToQueue(_song(9)),
      ]);
      expect(player.nativeOrder, [1, 2, 3, 8, 9]);
      expect(
        container.read(playerProvider).queue.map((s) => s.id),
        player.nativeOrder,
      );
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

  group('online search request state', () {
    late FakeYtDlpEngine engine;
    late ProviderContainer container;
    setUp(() {
      engine = FakeYtDlpEngine();
      container = ProviderContainer(
        overrides: [ytDlpEngineProvider.overrideWithValue(engine)],
      );
    });
    tearDown(() => container.dispose());

    OnlineSearchState state() => container.read(onlineSearchProvider);
    OnlineSearchNotifier search() =>
        container.read(onlineSearchProvider.notifier);

    test('older responses cannot replace a newer request', () async {
      final first = Completer<List<MediaInfo>>();
      engine.searchGate = first;
      final older = search().submit('older');
      final second = Completer<List<MediaInfo>>();
      engine.searchGate = second;
      final newer = search().submit('newer');

      first.complete([fakeMedia('old')]);
      await older;
      expect(state().query, 'newer');
      expect(state().isLoading, isTrue);
      expect(state().results, isEmpty);

      second.complete([fakeMedia('new')]);
      await newer;
      expect(state().isLoading, isFalse);
      expect(state().results.single.id, 'new');
      expect(state().hasSearched, isTrue);
    });

    test('failure leaves a retryable query and no loading state', () async {
      engine.lookupError = const DownloaderException('Could not reach it.');
      await search().submit('music');
      expect(state().error, 'Could not reach it.');
      expect(state().query, 'music');
      expect(state().isLoading, isFalse);
    });

    test('a link is resolved; anything else is searched', () async {
      engine.resolved = fakeMedia('abc', title: 'Linked');
      await search().submit('https://youtu.be/abc');
      expect(engine.resolves, ['https://youtu.be/abc']);
      expect(engine.searches, isEmpty);
      expect(state().results.single.title, 'Linked');

      engine.searchResults = [fakeMedia('s1'), fakeMedia('s2')];
      await search().submit('some words');
      expect(engine.searches, ['some words']);
      expect(state().results, hasLength(2));
    });

    test('results without an id are dropped', () async {
      engine.searchResults = [fakeMedia('ok'), fakeMedia('')];
      await search().submit('x');
      expect(state().results.map((r) => r.id), ['ok']);
    });

    test('empty input does nothing', () async {
      await search().submit('   ');
      expect(engine.searches, isEmpty);
      expect(state().hasSearched, isFalse);
    });

    test('disposing a pending search prevents late state writes', () async {
      final gate = Completer<List<MediaInfo>>();
      engine.searchGate = gate;
      final request = search().submit('music');
      container.dispose();
      gate.complete([fakeMedia('a')]);
      await request;
    });
  });
}
