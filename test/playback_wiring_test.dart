import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:on_audio_query/on_audio_query.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/core/home_widget.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/instances/crossfader.dart';
import 'package:wavvy/playback/ab_loop.dart';
import 'package:wavvy/playback/coordination.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/playback/replay_gain.dart';
import 'package:wavvy/playback/session.dart';
import 'package:wavvy/playback/smart_shuffle.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

import 'helpers/fake_player.dart';

// --------------------------------------------------------------------- fakes

class _Crossfader extends Fake implements Crossfader {
  @override
  Duration fade = Duration.zero;
  int cancels = 0;
  @override
  void cancel() => cancels++;
}

class _Handler extends Fake implements WavvyAudioHandler {
  @override
  final _Crossfader crossfader = _Crossfader();
  final gains = <double>[];
  final fadeOuts = <Duration>[];

  @override
  Future<void> setReplayGain(double db) async => gains.add(db);

  @override
  Future<void> fadeOutAndPause({
    Duration duration = const Duration(seconds: 4),
  }) async => fadeOuts.add(duration);
}

class _Store implements SessionStore {
  PlaybackSnapshot? saved;
  List<int>? queue;
  Map<String, Object>? progress;
  int clears = 0;

  @override
  Future<PlaybackSnapshot?> load() async => saved;
  @override
  Future<void> saveQueue(List<int> ids) async => queue = ids;
  @override
  Future<void> saveProgress({
    required int index,
    required int positionMs,
    required bool shuffle,
    required int loopMode,
  }) async => progress = {
    'index': index,
    'position': positionMs,
    'shuffle': shuffle,
    'loop': loopMode,
  };
  @override
  Future<void> clear() async {
    clears++;
    saved = null;
    queue = null;
    progress = null;
  }
}

class _Library extends LibraryNotifier {
  _Library(this.initial);
  List<SongModel> initial;
  @override
  LibraryState build() => LibraryState(songs: initial, filteredSongs: initial);
  void load(List<SongModel> songs) =>
      state = LibraryState(songs: songs, filteredSongs: songs);
}

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
}

class _Position extends PositionNotifier {
  @override
  Duration build() => Duration.zero;
  void to(Duration d) => state = d;
}

class _Duration extends DurationNotifier {
  @override
  Duration build() => const Duration(minutes: 3);
  void to(Duration d) => state = d;
}

class _Widget implements HomeWidgetBridge {
  final updates =
      <({String title, String artist, bool playing, Uint8List? art})>[];
  @override
  Future<void> update({
    required String title,
    required String artist,
    required bool playing,
    Uint8List? art,
  }) async =>
      updates.add((title: title, artist: artist, playing: playing, art: art));
}

class _Query extends Fake implements OnAudioQuery {
  @override
  Future<Uint8List?> queryArtwork(
    int id,
    ArtworkType type, {
    ArtworkFormat? format,
    int? size,
    int? quality,
  }) async => Uint8List.fromList([id, 2, 3]);
}

class _RateStore implements RateStore {
  final Map<String, PlaybackRate> saved = {};
  @override
  Future<Map<String, PlaybackRate>> load() async => {...saved};
  @override
  Future<void> save(Map<String, PlaybackRate> rates) async {
    saved
      ..clear()
      ..addAll(rates);
  }
}

final _wire = Provider<void>((ref) => wirePlayback(ref));

// ------------------------------------------------------------------- harness

class _H {
  _H({
    SettingsState settings = const SettingsState(),
    List<SongModel>? songs,
    Map<int, ReplayGainTags?> tags = const {},
  }) : player = MemoryPlayer(),
       handler = _Handler(),
       store = _Store(),
       widget = _Widget(),
       rateStore = _RateStore(),
       library = _Library(songs ?? const []) {
    container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWithValue(player),
        audioHandlerProvider.overrideWithValue(handler),
        playCountsLoaderProvider.overrideWithValue(() async => {3: 9}),
        mediaStoreProvider.overrideWithValue(media),
        sessionStoreProvider.overrideWithValue(store),
        libraryProvider.overrideWith(() => library),
        settingsProvider.overrideWith(() => _Settings(settings)),
        positionProvider.overrideWith(_Position.new),
        durationProvider.overrideWith(_Duration.new),
        homeWidgetProvider.overrideWithValue(widget),
        audioQueryProvider.overrideWithValue(_Query()),
        rateStoreProvider.overrideWithValue(rateStore),
        replayGainReaderProvider.overrideWithValue(
          (song) async => tags[song.id],
        ),
      ],
    );
  }

  final MemoryPlayer player;
  final _Handler handler;
  final _Store store;
  final _Widget widget;
  final _RateStore rateStore;
  final _Library library;
  late final ProviderContainer container;

  PlayerNotifier get notifier => container.read(playerProvider.notifier);
  PlayerState get state => container.read(playerProvider);
  SettingsNotifier get settings => container.read(settingsProvider.notifier);
  _Position get position =>
      container.read(positionProvider.notifier) as _Position;

  void wire() => container.read(_wire);

  Future<void> pump([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  void dispose() => container.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  final songs = [for (var i = 1; i <= 5; i++) testSong(i, albumId: 100)];

  // ============================================================ the notifier
  group('session snapshot and restore', () {
    test('there is nothing to save with an empty queue', () {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      expect(h.notifier.snapshot(Duration.zero), isNull);
    });

    test('a snapshot has the queue, song, position and modes', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      await h.notifier.playSong(songs[2], contextList: songs);
      final s = h.notifier.snapshot(const Duration(seconds: 42))!;
      expect(s.songIds, [1, 2, 3, 4, 5]);
      expect(s.index, 2);
      expect(s.positionMs, 42000);
      expect(s.currentId, 3);
    });

    test('restores the queue paused, at the saved song and position', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      final ok = await h.notifier.restoreSession(
        const PlaybackSnapshot(
          songIds: [1, 2, 3, 4, 5],
          index: 3,
          positionMs: 61000,
          shuffle: true,
          loopMode: 1,
        ),
        songs,
      );
      expect(ok, isTrue);
      expect(h.player.lastInitialIndex, 3);
      expect(h.player.lastInitialPosition, const Duration(seconds: 61));
      expect(h.player.playCalls, 0);
      expect(h.state.isPlaying, isFalse);
      expect(h.state.queue.map((s) => s.id), [1, 2, 3, 4, 5]);
      expect(h.state.currentSong?.id, 4);
      // loopMode 1 is LoopMode.one (the enum's own index).
      expect(h.player.loop, LoopMode.one);
      expect(h.player.shuffled, isTrue);
    });

    test(
      'songs that are gone are dropped and the index follows the song',
      () async {
        final h = _H(songs: songs);
        addTearDown(h.dispose);
        await h.notifier.restoreSession(
          const PlaybackSnapshot(
            songIds: [1, 99, 3, 98, 5],
            index: 4,
            positionMs: 5000,
          ),
          songs,
        );
        expect(h.state.queue.map((s) => s.id), [1, 3, 5]);
        expect(h.player.lastInitialIndex, 2);
        expect(h.player.lastInitialPosition, const Duration(seconds: 5));
      },
    );

    test(
      'if the playing song is gone, it starts at the top of what is left',
      () async {
        final h = _H(songs: songs);
        addTearDown(h.dispose);
        await h.notifier.restoreSession(
          const PlaybackSnapshot(
            songIds: [1, 99, 3],
            index: 1,
            positionMs: 9000,
          ),
          songs,
        );
        expect(h.player.lastInitialIndex, 0);
        expect(h.player.lastInitialPosition, Duration.zero);
      },
    );

    test('nothing left means nothing restored', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      final ok = await h.notifier.restoreSession(
        const PlaybackSnapshot(songIds: [90, 91], index: 0, positionMs: 0),
        songs,
      );
      expect(ok, isFalse);
      expect(h.state.queue, isEmpty);
    });
  });

  group('sleep timer', () {
    test('minutes: sets the mode and the time it ends', () {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.notifier.setSleepTimer(30);
      expect(h.state.sleepMode, SleepMode.minutes);
      expect(h.state.sleepTimerMinutes, 30);
      final left = h.state.sleepEndsAt!.difference(DateTime.now());
      expect(left.inMinutes, inInclusiveRange(29, 30));
      h.notifier.setSleepTimer(null);
      expect(h.state.sleepMode, SleepMode.off);
      expect(h.state.sleepEndsAt, isNull);
    });

    test('end of track: replaces a minutes timer', () {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.notifier.setSleepTimer(30);
      h.notifier.setSleepAtEnd(SleepMode.endOfTrack);
      expect(h.state.sleepMode, SleepMode.endOfTrack);
      expect(h.state.sleepTimerMinutes, isNull);
      expect(h.state.sleepEndsAt, isNull);
    });

    Future<_H> playing({bool shuffle = false, int index = 0}) async {
      final h = _H(songs: songs);
      await h.notifier.playSong(songs[index], contextList: songs);
      h.player.shuffled = shuffle;
      h.player.emit(index);
      return h;
    }

    test('end of track: fades out as the track runs out, once', () async {
      final h = await playing();
      addTearDown(h.dispose);
      h.notifier.setSleepAtEnd(SleepMode.endOfTrack);
      const duration = Duration(minutes: 3);
      h.notifier.onPosition(const Duration(minutes: 1), duration);
      expect(h.handler.fadeOuts, isEmpty); // far from the end
      h.notifier.onPosition(const Duration(minutes: 2, seconds: 57), duration);
      expect(h.handler.fadeOuts, hasLength(1));
      expect(h.state.sleepMode, SleepMode.off);
      // More ticks do not fire it again.
      h.notifier.onPosition(const Duration(minutes: 2, seconds: 58), duration);
      expect(h.handler.fadeOuts, hasLength(1));
    });

    test('the fade is as long as what is left, when that is short', () async {
      final h = await playing();
      addTearDown(h.dispose);
      h.notifier.setSleepAtEnd(SleepMode.endOfTrack);
      h.notifier.onPosition(
        const Duration(minutes: 2, seconds: 58),
        const Duration(minutes: 3),
      );
      expect(h.handler.fadeOuts.single, const Duration(seconds: 2));
    });

    test(
      'a lead (a crossfade about to start) makes it begin earlier',
      () async {
        final h = await playing();
        addTearDown(h.dispose);
        h.notifier.setSleepAtEnd(SleepMode.endOfTrack);
        const duration = Duration(minutes: 3);
        // 8 s left: too early on its own, in time with a 6 s lead.
        h.notifier.onPosition(
          const Duration(minutes: 2, seconds: 52),
          duration,
        );
        expect(h.handler.fadeOuts, isEmpty);
        h.notifier.onPosition(
          const Duration(minutes: 2, seconds: 52),
          duration,
          lead: const Duration(seconds: 6),
        );
        expect(h.handler.fadeOuts, hasLength(1));
      },
    );

    test('nothing happens while paused, or with no timer', () async {
      final h = await playing();
      addTearDown(h.dispose);
      const end = Duration(minutes: 2, seconds: 59);
      h.notifier.onPosition(end, const Duration(minutes: 3));
      expect(h.handler.fadeOuts, isEmpty);
      h.notifier.setSleepAtEnd(SleepMode.endOfTrack);
      h.player.setPlaying(false);
      h.notifier.onPosition(end, const Duration(minutes: 3));
      expect(h.handler.fadeOuts, isEmpty);
    });

    test('end of queue: waits for the last track', () async {
      final h = await playing(index: 1);
      addTearDown(h.dispose);
      h.notifier.setSleepAtEnd(SleepMode.endOfQueue);
      const near = Duration(minutes: 2, seconds: 59);
      h.notifier.onPosition(near, const Duration(minutes: 3));
      expect(h.handler.fadeOuts, isEmpty);

      await h.notifier.playSong(songs.last, contextList: songs);
      h.player.setPlaying(true);
      h.notifier.setSleepAtEnd(SleepMode.endOfQueue);
      h.notifier.onPosition(near, const Duration(minutes: 3));
      expect(h.handler.fadeOuts, hasLength(1));
    });

    test('end of queue with shuffle: the last in the shuffled order', () async {
      final h = await playing(index: 1, shuffle: true);
      addTearDown(h.dispose);
      // Played in the order 4, 0, 2, 3, 1.
      h.player.shuffleOrder = [4, 0, 2, 3, 1];
      h.player.emit(1);
      h.notifier.setSleepAtEnd(SleepMode.endOfQueue);
      h.notifier.onPosition(
        const Duration(minutes: 2, seconds: 59),
        const Duration(minutes: 3),
      );
      expect(h.handler.fadeOuts, hasLength(1));
    });
  });

  group('sleep timer extras', () {
    Future<_H> playing() async {
      final h = _H(songs: songs);
      await h.notifier.playSong(songs[0], contextList: songs);
      h.player.emit(0);
      return h;
    }

    const duration = Duration(minutes: 3);
    const nearEnd = Duration(minutes: 2, seconds: 57);

    test(
      'after N tracks: counts each track and stops at the end of the last',
      () async {
        final h = await playing();
        addTearDown(h.dispose);
        h.notifier.setSleepAfterTracks(2);
        expect(h.state.sleepMode, SleepMode.afterTracks);
        expect(h.state.sleepTracksLeft, 2);

        // The first of the two tracks runs out: no fade yet.
        h.notifier.onPosition(nearEnd, duration);
        expect(h.handler.fadeOuts, isEmpty);

        h.player.emit(1);
        expect(h.state.sleepTracksLeft, 1);
        h.notifier.onPosition(nearEnd, duration);
        expect(h.handler.fadeOuts, hasLength(1));
        expect(h.state.sleepMode, SleepMode.off);
      },
    );

    test('after 1 track behaves like the end of this track', () async {
      final h = await playing();
      addTearDown(h.dispose);
      h.notifier.setSleepAfterTracks(1);
      h.notifier.onPosition(nearEnd, duration);
      expect(h.handler.fadeOuts, hasLength(1));
    });

    test('skipping past the last track stops at once', () async {
      final h = await playing();
      addTearDown(h.dispose);
      h.notifier.setSleepAfterTracks(1);
      h.player.emit(1);
      expect(h.handler.fadeOuts, hasLength(1));
      expect(h.state.sleepMode, SleepMode.off);
    });

    test('a minutes timer can be extended', () async {
      final h = await playing();
      addTearDown(h.dispose);
      h.notifier.setSleepTimer(5);
      final before = h.state.sleepEndsAt!;
      expect(h.notifier.extendSleep(minutes: 10), isTrue);
      expect(h.state.sleepEndsAt!.difference(before).inMinutes, 10);
      expect(h.state.sleepMode, SleepMode.minutes);
    });

    test('a track timer gains a track; end of track becomes two', () async {
      final h = await playing();
      addTearDown(h.dispose);
      h.notifier.setSleepAtEnd(SleepMode.endOfTrack);
      expect(h.notifier.extendSleep(), isTrue);
      expect(h.state.sleepMode, SleepMode.afterTracks);
      expect(h.state.sleepTracksLeft, 2);
      expect(h.notifier.extendSleep(), isTrue);
      expect(h.state.sleepTracksLeft, 3);
    });

    test(
      'there is nothing to extend without a timer or at the queue end',
      () async {
        final h = await playing();
        addTearDown(h.dispose);
        expect(h.notifier.extendSleep(), isFalse);
        h.notifier.setSleepAtEnd(SleepMode.endOfQueue);
        expect(h.notifier.extendSleep(), isFalse);
      },
    );

    test('a shake counts as near the end only in the last minute', () async {
      final h = await playing();
      addTearDown(h.dispose);
      h.notifier.setSleepTimer(30);
      expect(h.notifier.sleepNearEnd, isFalse);
      h.notifier.setSleepTimer(1);
      expect(h.notifier.sleepNearEnd, isTrue);
    });

    test(
      'extending just after the timer stopped the music resumes it',
      () async {
        final h = await playing();
        addTearDown(h.dispose);
        h.notifier.setSleepAtEnd(SleepMode.endOfTrack);
        h.notifier.onPosition(nearEnd, duration); // fires the fade
        expect(h.notifier.sleepNearEnd, isTrue);
        expect(h.notifier.extendSleep(minutes: 15), isTrue);
        expect(h.handler.plays, 1);
        expect(h.state.sleepMode, SleepMode.minutes);
        expect(h.state.sleepTimerMinutes, 15);
      },
    );
  });

  group('bulk queue and delete', () {
    List<int> ids(Iterable<SongModel> s) => [for (final x in s) x.id];

    test('add several to the queue keeps queue and player aligned', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      await h.notifier.playSong(songs[0], contextList: songs.sublist(0, 2));
        expect(on.player.lastShuffleOrder, isA<SmartShuffleOrder>());

        final off = _H(
          songs: songs,
          settings: const SettingsState(smartShuffle: false),
        );
        addTearDown(off.dispose);
        await off.notifier.playSong(songs[0], contextList: songs);
        expect(off.player.lastShuffleOrder, isNot(isA<SmartShuffleOrder>()));
      },
    );

    test(
      'the order sees the queue: index, play count and a liked weight',
      () async {
        final h = _H(songs: songs);
        addTearDown(h.dispose);
        await h.notifier.playSong(songs[0], contextList: songs);
        final order = h.player.lastShuffleOrder! as SmartShuffleOrder;
        expect(order.describe(2).index, 2);
        expect(order.describe(99).weight, 1); // outside the queue
        await h.notifier.toggleShuffle(); // loads the play counts
        // Song 3 (index 2) was played 9 times: it weighs less than an unplayed one.
        expect(order.describe(2).weight, lessThan(order.describe(1).weight));
      },
    );

    test(
      'turning shuffle on remakes the order; turning it off does not',
      () async {
        final h = _H(songs: songs);
        addTearDown(h.dispose);
        await h.notifier.playSong(songs[1], contextList: songs);
        await h.notifier.toggleShuffle();
        expect(h.player.shuffled, isTrue);
        expect(h.player.reshuffles, 1);
        await h.notifier.toggleShuffle();
        expect(h.player.shuffled, isFalse);
        expect(h.player.reshuffles, 1);
      },
    );
  });

  // ================================================================= wiring
  group('last session', () {
    test('is reopened once the library is known, paused', () async {
      final h = _H();
      addTearDown(h.dispose);
      h.store.saved = const PlaybackSnapshot(
        songIds: [1, 2, 3],
        index: 1,
        positionMs: 30000,
      );
      h.wire();
      await h.pump();
      expect(h.state.queue, isEmpty); // the library is still empty

      h.library.load(songs);
      await h.pump(50);
      expect(h.state.queue.map((s) => s.id), [1, 2, 3]);
      expect(h.state.currentSong?.id, 2);
      expect(h.player.lastInitialPosition, const Duration(seconds: 30));
      expect(h.player.playCalls, 0);
    });

    test('is left alone when the setting is off', () async {
      final h = _H(
        songs: songs,
        settings: const SettingsState(resumeSession: false),
      );
      addTearDown(h.dispose);
      h.store.saved = const PlaybackSnapshot(
        songIds: [1, 2],
        index: 0,
        positionMs: 0,
      );
      h.wire();
      await h.pump(50);
      expect(h.state.queue, isEmpty);
    });

    test('does not replace something that is already playing', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      await h.notifier.playSong(songs[4], contextList: [songs[4]]);
      h.store.saved = const PlaybackSnapshot(
        songIds: [1, 2],
        index: 0,
        positionMs: 0,
      );
      h.wire();
      await h.pump(50);
      expect(h.state.queue.map((s) => s.id), [5]);
    });

    test('saves the queue and where playback is', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.wire();
      await h.pump();
      await h.notifier.playSong(songs[2], contextList: songs);
      await h.pump(800); // past the save delay
      expect(h.store.queue, [1, 2, 3, 4, 5]);
      expect(h.store.progress!['index'], 2);
    });

    test('forgets the session when the queue is emptied afterwards', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.store.saved = const PlaybackSnapshot(
        songIds: [1],
        index: 0,
        positionMs: 0,
      );
      h.wire();
      await h.pump(50); // restored
      expect(h.state.queue, hasLength(1));
      await h.notifier.removeFromQueue(0);
      await h.pump(800);
      expect(h.store.clears, 1);
    });

    test('a restore that fails keeps the stored session', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.player.failNextLoad = true;
      h.store.saved = const PlaybackSnapshot(
        songIds: [1, 2],
        index: 0,
        positionMs: 0,
      );
      h.wire();
      await h.pump(800); // past the save delay
      expect(h.state.queue, isEmpty);
      expect(h.store.clears, 0);
      expect(h.store.saved, isNotNull);
    });

    test('does not replace what the user starts while it loads', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.store.saved = const PlaybackSnapshot(
        songIds: [1, 2],
        index: 0,
        positionMs: 0,
      );
      h.wire(); // starts loading the stored session
      await h.notifier.playSong(songs[4], contextList: [songs[4]]);
      await h.pump(50);
      expect(h.state.queue.map((s) => s.id), [5]);
    });

    test('does not save when the setting is off', () async {
      final h = _H(
        songs: songs,
        settings: const SettingsState(resumeSession: false),
      );
      addTearDown(h.dispose);
      h.wire();
      await h.pump();
      await h.notifier.playSong(songs[0], contextList: songs);
      await h.pump(800);
      expect(h.store.queue, isNull);
    });
  });

  group('volume leveling (ReplayGain)', () {
    test('applies the track gain of the playing song', () async {
      final h = _H(
        songs: songs,
        settings: const SettingsState(replayGainMode: 1),
        tags: {1: const ReplayGainTags(trackGain: -7.5, albumGain: -3)},
      );
      addTearDown(h.dispose);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: songs);
      await h.pump();
      expect(h.handler.gains.last, -7.5);
    });

    test('album mode uses the album gain', () async {
      final h = _H(
        songs: songs,
        settings: const SettingsState(replayGainMode: 2),
        tags: {1: const ReplayGainTags(trackGain: -7.5, albumGain: -3)},
      );
      addTearDown(h.dispose);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: songs);
      await h.pump();
      expect(h.handler.gains.last, -3);
    });

    test('a song without tags, or with leveling off, gets no change', () async {
      final h = _H(
        songs: songs,
        settings: const SettingsState(replayGainMode: 1),
        tags: {1: const ReplayGainTags(trackGain: -7.5)},
      );
      addTearDown(h.dispose);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: songs);
      await h.pump();
      expect(h.handler.gains.last, -7.5);
      await h.notifier.playSong(songs[1], contextList: songs);
      await h.pump();
      expect(h.handler.gains.last, 0); // no tags on song 2

      await h.settings.setReplayGainMode(0);
      await h.pump();
      await h.notifier.playSong(songs[0], contextList: songs);
      await h.pump();
      expect(h.handler.gains.last, 0);
    });

    test('changing the setting re-levels the current song', () async {
      final h = _H(
        songs: songs,
        tags: {1: const ReplayGainTags(trackGain: -4)},
      );
      addTearDown(h.dispose);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: songs);
      await h.pump();
      expect(h.handler.gains.last, 0); // off by default
      await h.settings.setReplayGainMode(1);
      await h.pump();
      expect(h.handler.gains.last, -4);
    });
  });

  group('crossfade length', () {
    test('follows the setting, and turning it off cancels a fade', () async {
      final h = _H(settings: const SettingsState(crossfadeSeconds: 6));
      addTearDown(h.dispose);
      h.wire();
      expect(h.handler.crossfader.fade, const Duration(seconds: 6));
      await h.settings.setCrossfadeSeconds(10);
      await h.pump();
      expect(h.handler.crossfader.fade, const Duration(seconds: 10));
      expect(h.handler.crossfader.cancels, 0);
      await h.settings.setCrossfadeSeconds(0);
      await h.pump();
      expect(h.handler.crossfader.fade, Duration.zero);
      expect(h.handler.crossfader.cancels, 1);
    });
  });

  group('A-B loop', () {
    test('jumps back to A when playback passes B', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: songs);
      await h.pump();
      final loop = h.container.read(abLoopProvider.notifier);
      loop.press(const Duration(seconds: 10));
      loop.press(const Duration(seconds: 20));

      h.position.to(const Duration(seconds: 15));
      expect(h.player.seeks, isEmpty);
      h.position.to(const Duration(seconds: 20, milliseconds: 100));
      await h.pump();
      expect(h.player.seeks, [const Duration(seconds: 10)]);
    });

    test('belongs to one song: changing song clears it', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: songs);
      await h.pump();
      h.container
          .read(abLoopProvider.notifier)
          .press(const Duration(seconds: 5));
      await h.notifier.playSong(songs[1], contextList: songs);
      await h.pump();
      expect(h.container.read(abLoopProvider).isEmpty, isTrue);
    });
  });

  group('sleep at the end of a track, through the position', () {
    test('the position ticks reach the timer', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: songs);
      h.notifier.setSleepAtEnd(SleepMode.endOfTrack);
      h.position.to(const Duration(minutes: 2, seconds: 58));
      await h.pump();
      expect(h.handler.fadeOuts, hasLength(1));
    });
  });

  group('remembered speed', () {
    final other = [for (var i = 11; i <= 12; i++) testSong(i, albumId: 200)];

    test('a saved rate is applied when the album changes', () async {
      final h = _H(songs: [...songs, ...other]);
      addTearDown(h.dispose);
      h.rateStore.saved['a:200'] = const PlaybackRate(1.5, 0.9);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: [...songs, ...other]);
      await h.pump();
      expect(h.player.speedValue, 1);

      await h.notifier.playSong(other[0], contextList: [...songs, ...other]);
      await h.pump(50);
      expect(h.player.speedValue, 1.5);
      expect(h.player.pitchValue, 0.9);

      // Back to the first album: normal speed again.
      await h.notifier.playSong(songs[1], contextList: [...songs, ...other]);
      await h.pump(50);
      expect(h.player.speedValue, 1);
      expect(h.player.pitchValue, 1);
    });

    test('a change inside one album is kept across its tracks', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: songs);
      await h.pump();
      h.player.speedValue = 1.3; // the user changed it
      await h.notifier.playSong(songs[1], contextList: songs);
      await h.pump(50);
      expect(h.player.speedValue, 1.3);
    });

    test('does nothing when the setting is off', () async {
      final h = _H(
        songs: [...songs, ...other],
        settings: const SettingsState(rememberRates: false),
      );
      addTearDown(h.dispose);
      h.rateStore.saved['a:200'] = const PlaybackRate(1.5, 1);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: [...songs, ...other]);
      await h.notifier.playSong(other[0], contextList: [...songs, ...other]);
      await h.pump(50);
      expect(h.player.speedValue, 1);
    });
  });

  group('home-screen widget', () {
    test('sends the song with its artwork, then only the play state', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: songs);
      await h.pump(500);
      expect(h.widget.updates, isNotEmpty);
      final first = h.widget.updates.first;
      expect(first.title, 'Track 1');
      expect(first.artist, 'Artist');
      expect(first.art, isNotNull);
      expect(first.art, isNotEmpty);

      final before = h.widget.updates.length;
      h.player.setPlaying(false);
      await h.pump(500);
      expect(h.widget.updates.length, greaterThan(before));
      final last = h.widget.updates.last;
      expect(last.playing, isFalse);
      // Same song: the picture is not sent again.
      expect(last.art, isNull);
    });

    test('a new song brings a new picture', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: songs);
      await h.pump(500);
      await h.notifier.playSong(songs[1], contextList: songs);
      await h.pump(500);
      final last = h.widget.updates.last;
      expect(last.title, 'Track 2');
      expect(last.art, isNotNull);
    });

    test('with nothing playing it says so', () async {
      final h = _H(songs: songs);
      addTearDown(h.dispose);
      h.wire();
      await h.notifier.playSong(songs[0], contextList: [songs[0]]);
      await h.pump(500);
      await h.notifier.removeFromQueue(0);
      await h.pump(500);
      final last = h.widget.updates.last;
      expect(last.title, 'Wavvy');
      expect(last.artist, 'Tap to open');
      expect(last.art, isEmpty); // clears the old picture
    });
  });
}
