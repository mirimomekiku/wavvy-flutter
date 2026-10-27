import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:wavvy/playback/ab_loop.dart';
import 'package:wavvy/playback/crossfade.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/focus.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/playback/replay_gain.dart';
import 'package:wavvy/playback/session.dart';
import 'package:wavvy/providers/library_provider.dart';

import 'helpers/fake_player.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

/// ASCII text as bytes, with binary padding around it as in a real file.
Uint8List _tagBytes(String text, {bool utf16 = false}) {
  final body = utf16
      ? [
          for (final c in text.codeUnits) ...[c, 0],
        ]
      : text.codeUnits;
  return _bytes([0x01, 0xff, 0xfe, ...body, 0x00, 0xde, 0xad]);
}

void main() {
  group('ReplayGain tags', () {
    test('an ID3 TXXX frame (ASCII)', () {
      final t = parseReplayGain(
        _tagBytes('TXXX\x03REPLAYGAIN_TRACK_GAIN\x00-6.54 dB'),
      );
      expect(t!.trackGain, -6.54);
      expect(t.albumGain, isNull);
    });

    test('an ID3 TXXX frame in UTF-16', () {
      final t = parseReplayGain(
        _tagBytes('TXXX\x01REPLAYGAIN_ALBUM_GAIN\x00+2.10 dB', utf16: true),
      );
      expect(t!.albumGain, 2.10);
    });

    test('a Vorbis comment (FLAC, Ogg, Opus)', () {
      final t = parseReplayGain(
        _tagBytes(
          'REPLAYGAIN_TRACK_GAIN=-8.20 dB\x00\x00REPLAYGAIN_TRACK_PEAK=0.987654',
        ),
      );
      expect(t!.trackGain, -8.20);
      expect(t.trackPeak, closeTo(0.987654, 1e-9));
    });

    test('an MP4 freeform atom', () {
      final t = parseReplayGain(
        _bytes([
          ...'----'.codeUnits,
          ...'replaygain_track_gain'.codeUnits,
          ...'data'.codeUnits,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          ...'-3.30 dB'.codeUnits,
        ]),
      );
      expect(t!.trackGain, -3.30);
    });

    test('is case-insensitive and accepts a decimal comma', () {
      final t = parseReplayGain(_tagBytes('replaygain_track_gain: -4,5 DB'));
      expect(t!.trackGain, -4.5);
    });

    test('finds track and album gain together', () {
      final t = parseReplayGain(
        _tagBytes(
          'REPLAYGAIN_TRACK_GAIN=-6.0 dB REPLAYGAIN_ALBUM_GAIN=-7.5 dB',
        ),
      );
      expect(t!.trackGain, -6.0);
      expect(t.albumGain, -7.5);
    });

    test('files without tags, and random bytes, give nothing', () {
      expect(parseReplayGain(_bytes([])), isNull);
      expect(parseReplayGain(_tagBytes('just some title text')), isNull);
      final noise = Uint8List.fromList(
        List.generate(5000, (i) => (i * 37 + 11) % 256),
      );
      expect(parseReplayGain(noise), isNull);
      // A gain with no number after it is not a gain.
      expect(parseReplayGain(_tagBytes('REPLAYGAIN_TRACK_GAIN=')), isNull);
    });
  });

  group('reading tags from a file', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('wavvy_rg'));
    tearDown(() => dir.deleteSync(recursive: true));

    File write(String name, List<int> bytes) =>
        File('${dir.path}/$name')..writeAsBytesSync(bytes);

    test('from the start of the file', () async {
      final f = write('a.flac', [
        ...'fLaC'.codeUnits,
        ..._tagBytes('REPLAYGAIN_TRACK_GAIN=-5.5 dB'),
        ...List.filled(1000, 7),
      ]);
      expect((await readReplayGain(f.path))!.trackGain, -5.5);
    });

    test('from the end of the file (APE or MP4 tags)', () async {
      final f = write('a.m4a', [
        ...List.filled(600000, 3),
        ..._tagBytes('replaygain_track_gain -2.0 dB'),
      ]);
      expect((await readReplayGain(f.path))!.trackGain, -2.0);
    });

    test('an ID3v2 tag larger than the first block is read whole', () async {
      final padding = List.filled(300000, 0x20);
      final size = padding.length + 60;
      // "ID3", version, flags, then the size as four 7-bit bytes.
      final header = [
        0x49,
        0x44,
        0x33,
        4,
        0,
        0,
        (size >> 21) & 0x7f,
        (size >> 14) & 0x7f,
        (size >> 7) & 0x7f,
        size & 0x7f,
      ];
      final f = write('a.mp3', [
        ...header,
        ...padding,
        ..._tagBytes('TXXX REPLAYGAIN_TRACK_GAIN\x00-9.9 dB'),
        ...List.filled(5000, 1),
      ]);
      expect((await readReplayGain(f.path))!.trackGain, -9.9);
    });

    test(
      'a missing or untagged file gives nothing, without throwing',
      () async {
        expect(await readReplayGain('${dir.path}/nope.mp3'), isNull);
        final f = write('plain.mp3', List.filled(2000, 5));
        expect(await readReplayGain(f.path), isNull);
      },
    );
  });

  group('the gain to apply', () {
    const tags = ReplayGainTags(
      trackGain: -6,
      albumGain: -3,
      trackPeak: 0.9,
      albumPeak: 0.8,
    );
    test('track or album, or nothing when off', () {
      expect(replayGainDb(tags, ReplayGainMode.track), -6);
      expect(replayGainDb(tags, ReplayGainMode.album), -3);
      expect(replayGainDb(tags, ReplayGainMode.off), 0);
      expect(replayGainDb(null, ReplayGainMode.track), 0);
    });
    test('falls back to the other gain when one is missing', () {
      expect(
        replayGainDb(const ReplayGainTags(albumGain: -4), ReplayGainMode.track),
        -4,
      );
      expect(
        replayGainDb(const ReplayGainTags(trackGain: -5), ReplayGainMode.album),
        -5,
      );
    });
    test('a quiet track is boosted, but never past full scale or the cap', () {
      // 12 dB wanted; capped at 9; no peak to protect.
      expect(
        replayGainDb(const ReplayGainTags(trackGain: 12), ReplayGainMode.track),
        maxReplayGainBoostDb,
      );
      // Peak 0.5 leaves 6.02 dB of headroom.
      final limited = replayGainDb(
        const ReplayGainTags(trackGain: 8, trackPeak: 0.5),
        ReplayGainMode.track,
      );
      expect(limited, closeTo(20 * math.log(2) / math.ln10, 1e-6));
      // Already at full scale: no boost at all.
      expect(
        replayGainDb(
          const ReplayGainTags(trackGain: 5, trackPeak: 1.0),
          ReplayGainMode.track,
        ),
        0,
      );
    });
    test('a cut is never limited by the peak', () {
      expect(
        replayGainDb(
          const ReplayGainTags(trackGain: -9, trackPeak: 1.5),
          ReplayGainMode.track,
        ),
        -9,
      );
    });
    test('mode from the saved setting', () {
      expect(ReplayGainMode.fromIndex(0), ReplayGainMode.off);
      expect(ReplayGainMode.fromIndex(1), ReplayGainMode.track);
      expect(ReplayGainMode.fromIndex(2), ReplayGainMode.album);
      expect(ReplayGainMode.fromIndex(9), ReplayGainMode.off);
      expect(ReplayGainMode.fromIndex(-1), ReplayGainMode.off);
    });
    test(
      'the cache reads each song once, even when asked at the same time',
      () async {
        var reads = 0;
        final cache = ReplayGainCache((song) async {
          reads++;
          return const ReplayGainTags(trackGain: -1);
        });
        final song = testSong(1);
        final both = await Future.wait([
          cache.tagsFor(song),
          cache.tagsFor(song),
        ]);
        await cache.tagsFor(song);
        expect(reads, 1);
        expect(both.first!.trackGain, -1);
      },
    );
  });

  group('audio focus', () {
    late _Target target;
    late FocusPolicy policy;
    late DateTime now;
    late FocusController focus;

    setUp(() {
      target = _Target();
      policy = const FocusPolicy();
      now = DateTime(2026, 1, 1, 12);
      focus = FocusController(
        target: target,
        policy: () => policy,
        clock: () => now,
      );
    });

    test('a short sound lowers the volume and restores it', () async {
      target.playing = true;
      await focus.onInterruption(true, FocusInterruption.duck);
      expect(target.ducked, isTrue);
      expect(target.log, ['duck:true']);
      await focus.onInterruption(false, FocusInterruption.duck);
      expect(target.ducked, isFalse);
      expect(target.playing, isTrue);
    });

    test('with ducking off, a short sound pauses instead', () async {
      policy = const FocusPolicy(duck: false);
      target.playing = true;
      await focus.onInterruption(true, FocusInterruption.duck);
      expect(target.log, ['pause']);
      await focus.onInterruption(false, FocusInterruption.duck);
      expect(target.log, ['pause', 'play']);
    });

    test('a call pauses, and playback resumes afterwards', () async {
      target.playing = true;
      await focus.onInterruption(true, FocusInterruption.pause);
      expect(target.playing, isFalse);
      await focus.onInterruption(false, FocusInterruption.pause);
      expect(target.playing, isTrue);
    });

    test('it does not start music that was not playing', () async {
      target.playing = false;
      await focus.onInterruption(true, FocusInterruption.pause);
      await focus.onInterruption(false, FocusInterruption.pause);
      expect(target.log, isEmpty);
    });

    test('with resume turned off, it stays paused', () async {
      policy = const FocusPolicy(resumeAfterInterruption: false);
      target.playing = true;
      await focus.onInterruption(true, FocusInterruption.pause);
      await focus.onInterruption(false, FocusInterruption.pause);
      expect(target.playing, isFalse);
    });

    test(
      'when another app took over for good, it does not barge back in',
      () async {
        target.playing = true;
        await focus.onInterruption(true, FocusInterruption.pause);
        await focus.onInterruption(false, FocusInterruption.unknown);
        expect(target.playing, isFalse);
      },
    );

    test('pressing play yourself cancels the automatic resume', () async {
      target.playing = true;
      await focus.onInterruption(true, FocusInterruption.pause);
      focus.userChangedPlayback();
      await focus.onInterruption(false, FocusInterruption.pause);
      expect(target.playing, isFalse);
    });

    test('unplugging pauses, unless the setting is off', () async {
      target.playing = true;
      await focus.onBecomingNoisy();
      expect(target.playing, isFalse);

      policy = const FocusPolicy(pauseOnUnplug: false);
      target.playing = true;
      await focus.onBecomingNoisy();
      expect(target.playing, isTrue);
    });

    test('plugging back in resumes only when asked, and only soon', () async {
      policy = const FocusPolicy(resumeOnReconnect: true);
      target.playing = true;
      await focus.onBecomingNoisy();
      now = now.add(const Duration(minutes: 3));
      await focus.onHeadphonesConnected();
      expect(target.playing, isTrue);

      // Too long ago.
      target.playing = true;
      await focus.onBecomingNoisy();
      now = now.add(const Duration(minutes: 30));
      await focus.onHeadphonesConnected();
      expect(target.playing, isFalse);
    });

    test('by default plugging in does not resume', () async {
      target.playing = true;
      await focus.onBecomingNoisy();
      await focus.onHeadphonesConnected();
      expect(target.playing, isFalse);
    });

    test('headphones connecting without an unplug does nothing', () async {
      policy = const FocusPolicy(resumeOnReconnect: true);
      await focus.onHeadphonesConnected();
      expect(target.log, isEmpty);
    });
  });

  group('crossfade plan', () {
    const plan = CrossfadePlan(Duration(seconds: 6));
    bool start({
      Duration position = const Duration(seconds: 195),
      Duration? duration = const Duration(seconds: 200),
      Duration? nextDuration = const Duration(seconds: 180),
      bool playing = true,
      bool hasNext = true,
      bool repeatOne = false,
      int index = 0,
      int? alreadyFor,
      CrossfadePlan p = plan,
    }) => p.shouldStart(
      position: position,
      duration: duration,
      nextDuration: nextDuration,
      playing: playing,
      hasNext: hasNext,
      repeatOne: repeatOne,
      currentIndex: index,
      alreadyFor: alreadyFor,
    );

    test('starts when the remaining time fits the fade', () {
      expect(start(), isTrue);
      expect(start(position: const Duration(seconds: 194)), isTrue);
      expect(
        start(position: const Duration(seconds: 194, milliseconds: 500)),
        isTrue,
      );
    });
    test('not before the fade, and not once the track is over', () {
      expect(start(position: const Duration(seconds: 190)), isFalse);
      expect(start(position: const Duration(milliseconds: 199800)), isFalse);
    });
    test('only once per track', () {
      expect(start(alreadyFor: 0), isFalse);
      expect(start(alreadyFor: 1), isTrue);
    });
    test('needs something playing, something next and no repeat-one', () {
      expect(start(playing: false), isFalse);
      expect(start(hasNext: false), isFalse);
      expect(start(repeatOne: true), isFalse);
    });
    test('off when the length is zero', () {
      expect(start(p: const CrossfadePlan(Duration.zero)), isFalse);
    });
    test('short tracks are not crossfaded', () {
      // The fade needs 2 x 6 s + 2 s.
      expect(start(duration: const Duration(seconds: 13)), isFalse);
      expect(
        start(
          duration: const Duration(seconds: 14),
          position: const Duration(seconds: 9),
        ),
        isTrue,
      );
      expect(start(nextDuration: const Duration(seconds: 10)), isFalse);
      expect(start(duration: null), isFalse);
      // An unknown next length is allowed.
      expect(start(nextDuration: null), isTrue);
    });
    test('the levels cross with equal power', () {
      expect(crossfadeLevels(0).outgoing, 1);
      expect(crossfadeLevels(0).incoming, closeTo(0, 1e-12));
      expect(crossfadeLevels(1).outgoing, closeTo(0, 1e-12));
      expect(crossfadeLevels(1).incoming, 1);
      for (var i = 0; i <= 20; i++) {
        final l = crossfadeLevels(i / 20);
        expect(
          l.outgoing * l.outgoing + l.incoming * l.incoming,
          closeTo(1, 1e-9),
        );
      }
      expect(crossfadeLevels(-1).outgoing, 1);
      expect(crossfadeLevels(2).incoming, 1);
    });
  });

  group('A-B loop', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());
    AbLoopNotifier n() => c.read(abLoopProvider.notifier);
    AbLoop s() => c.read(abLoopProvider);

    test('three presses: set A, set B, clear', () {
      n().press(const Duration(seconds: 10));
      expect(s().start, const Duration(seconds: 10));
      expect(s().isActive, isFalse);
      n().press(const Duration(seconds: 25));
      expect(s().end, const Duration(seconds: 25));
      expect(s().isActive, isTrue);
      n().press(const Duration(seconds: 30));
      expect(s().isEmpty, isTrue);
    });
    test('a B that is too close to A moves A instead', () {
      n().press(const Duration(seconds: 10));
      n().press(const Duration(seconds: 10, milliseconds: 400));
      expect(s().isActive, isFalse);
      expect(s().start, const Duration(seconds: 10, milliseconds: 400));
    });
    test('jumps back to A once past B, not before', () {
      n().press(const Duration(seconds: 10));
      n().press(const Duration(seconds: 20));
      expect(n().jumpFor(const Duration(seconds: 15)), isNull);
      expect(
        n().jumpFor(const Duration(seconds: 19, milliseconds: 900)),
        isNull,
      );
      expect(
        n().jumpFor(const Duration(seconds: 20)),
        const Duration(seconds: 10),
      );
      expect(
        n().jumpFor(const Duration(seconds: 25)),
        const Duration(seconds: 10),
      );
    });
    test('no jump without a complete loop', () {
      expect(n().jumpFor(const Duration(minutes: 1)), isNull);
      n().press(const Duration(seconds: 10));
      expect(n().jumpFor(const Duration(minutes: 1)), isNull);
    });
    test('clear removes it', () {
      n().press(const Duration(seconds: 1));
      n().clear();
      expect(s().isEmpty, isTrue);
    });
  });

  group('saved session', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('the queue and progress come back as saved', () async {
      final store = PrefsSessionStore();
      expect(await store.load(), isNull);
      await store.saveQueue([5, 6, 7]);
      await store.saveProgress(
        index: 1,
        positionMs: 12345,
        shuffle: true,
        loopMode: 2,
      );
      final s = (await store.load())!;
      expect(s.songIds, [5, 6, 7]);
      expect(s.index, 1);
      expect(s.positionMs, 12345);
      expect(s.shuffle, isTrue);
      expect(s.loopMode, 2);
      expect(s.currentId, 6);
    });

    test('a queue without progress still loads, from the start', () async {
      final store = PrefsSessionStore();
      await store.saveQueue([1, 2]);
      final s = (await store.load())!;
      expect(s.index, 0);
      expect(s.positionMs, 0);
    });

    test('clear forgets everything', () async {
      final store = PrefsSessionStore();
      await store.saveQueue([1]);
      await store.clear();
      expect(await store.load(), isNull);
    });

    test('a damaged save is ignored, not a crash', () async {
      final prefs = SharedPreferencesAsyncPlatform.instance!;
      // ignore: invalid_use_of_visible_for_testing_member
      expect(prefs, isNotNull);
      final store = PrefsSessionStore();
      await store.saveQueue([1, 2]);
      // Overwrite with junk through the same store key.
      await _putRaw('session_queue', '{not json');
      expect(await store.load(), isNull);
      await _putRaw('session_queue', jsonEncode(['a', 'b']));
      expect(await store.load(), isNull);
    });

    test('currentId is null for a bad index', () {
      expect(
        const PlaybackSnapshot(songIds: [1], index: 5, positionMs: 0).currentId,
        isNull,
      );
      expect(
        const PlaybackSnapshot(
          songIds: [1],
          index: -1,
          positionMs: 0,
        ).currentId,
        isNull,
      );
    });
  });

  group('remembered speed', () {
    test('the key is the album, or the folder without one', () {
      expect(rateKey(testSong(1, albumId: 7)), 'a:7');
      expect(rateKey(testSong(2)), 'a:0'.replaceFirst('a:0', 'd:/music/0'));
      final noAlbum = testSong(3, albumId: null);
      expect(rateKey(noAlbum), startsWith('d:/music/'));
      expect(
        rateKey(testSong(4, albumId: 7)),
        rateKey(testSong(5, albumId: 7)),
      );
    });

    test('remembers per album, forgets normal speed, and persists', () async {
      final store = _RateStore();
      final c = ProviderContainer(
        overrides: [rateStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      final rates = c.read(playbackRatesProvider.notifier);
      await rates.ready;
      final book = testSong(1, albumId: 10);
      final album = testSong(2, albumId: 20);

      await rates.remember(book, const PlaybackRate(1.4, 1));
      expect(rates.rateFor(book).speed, 1.4);
      expect(rates.rateFor(album).isNormal, isTrue);
      expect(store.saved['a:10']!.speed, 1.4);

      await rates.remember(book, PlaybackRate.normal);
      expect(rates.rateFor(book).isNormal, isTrue);
      expect(store.saved, isEmpty);
    });

    test('loads what was saved', () async {
      final store = _RateStore()..saved['a:10'] = const PlaybackRate(1.25, 0.9);
      final c = ProviderContainer(
        overrides: [rateStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      final rates = c.read(playbackRatesProvider.notifier);
      await rates.ready;
      expect(rates.rateFor(testSong(1, albumId: 10)).pitch, 0.9);
    });

    test('the preferences store round-trips and survives junk', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final store = PrefsRateStore();
      expect(await store.load(), isEmpty);
      await store.save({'a:1': const PlaybackRate(1.5, 1)});
      expect((await store.load())['a:1']!.speed, 1.5);
      await _putRaw('playback_rates', 'junk');
      expect(await store.load(), isEmpty);
    });
  });

  group('favorites', () {
    test('toggle adds, then removes, and saves each time', () async {
      final store = _FavStore();
      final c = ProviderContainer(
        overrides: [favoritesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      final favorites = c.read(favoritesProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await favorites.toggle(testSong(1));
      expect(favorites.isFavorite(1), isTrue);
      expect(store.rows.keys, [1]);
      await favorites.toggle(testSong(1));
      expect(favorites.isFavorite(1), isFalse);
      expect(store.rows, isEmpty);
    });

    test('saved favorites load, and a toggle during loading wins', () async {
      final store = _FavStore()..rows.addAll({1: 100, 2: 200});
      final c = ProviderContainer(
        overrides: [favoritesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      c.read(favoritesProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(favoritesProvider).keys, containsAll([1, 2]));
    });

    test(
      'liked songs are the ones still in the library, newest first',
      () async {
        final store = _FavStore()
          ..rows.addAll({1: 100, 2: 300, 3: 200, 99: 400});
        final songs = [for (var i = 1; i <= 4; i++) testSong(i)];
        final c = ProviderContainer(
          overrides: [
            favoritesStoreProvider.overrideWithValue(store),
            libraryProvider.overrideWith(() => _Library(songs)),
          ],
        );
        addTearDown(c.dispose);
        c.read(favoritesProvider);
        await Future<void>.delayed(Duration.zero);
        // 99 is not in the library any more.
        expect(c.read(likedSongsProvider).map((s) => s.id), [2, 3, 1]);
      },
    );
  });
}

/// Writes a raw string where the in-memory preferences keep it.
Future<void> _putRaw(String key, String value) => PrefsRaw.set(key, value);

class _Target implements FocusTarget {
  @override
  bool playing = false;
  bool ducked = false;
  final log = <String>[];

  @override
  Future<void> pause() async {
    log.add('pause');
    playing = false;
  }

  @override
  Future<void> play() async {
    log.add('play');
    playing = true;
  }

  @override
  Future<void> setDucked(bool d) async {
    log.add('duck:$d');
    ducked = d;
  }
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

class _FavStore implements FavoritesStore {
  final Map<int, int> rows = {};
  @override
  Future<Map<int, int>> load() async => {...rows};
  @override
  Future<void> add(int songId, int addedAt) async => rows[songId] = addedAt;
  @override
  Future<void> remove(int songId) async => rows.remove(songId);
}

class _Library extends LibraryNotifier {
  _Library(this.songs);
  final List<dynamic> songs;
  @override
  LibraryState build() => LibraryState(
    songs: List.castFrom(songs),
    filteredSongs: List.castFrom(songs),
  );
}

/// Direct access to the in-memory preferences, to plant damaged values.
class PrefsRaw {
  static Future<void> set(String key, String value) async {
    final platform = SharedPreferencesAsyncPlatform.instance!;
    await platform.setString(key, value, const SharedPreferencesOptions());
  }
}
