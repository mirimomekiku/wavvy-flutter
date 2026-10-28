import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/playback/history.dart';
import 'package:wavvy/providers/home_shelves_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/screens/home/view/home_view.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

SongModel _song(int id, {int? albumId, String? album, String? artist}) =>
    SongModel({
      '_id': id,
      '_data': '/music/s$id.mp3',
      '_uri': 'content://media/$id',
      '_display_name': 's$id.mp3',
      '_display_name_wo_ext': 's$id',
      '_size': 1024,
      'title': 'Song $id',
      'artist': artist ?? 'Artist $id',
      'artist_id': id,
      'album_id': albumId ?? id,
      'album': album ?? 'Album ${albumId ?? id}',
      'date_added': id,
      'duration': 200000,
      'is_music': true,
    });

AlbumModel _album(int id, {String? name, String? artist}) => AlbumModel({
  '_id': id,
  'album': name ?? 'Album $id',
  'artist': artist ?? 'Artist $id',
  'numsongs': 5,
});

Map<String, Object?> _row(
  int songId,
  DateTime at, {
  String? album,
  String? artist,
}) => {
  'song_id': songId,
  'played_at': at.millisecondsSinceEpoch,
  'title': 'Song $songId',
  'artist': artist,
  'album': album,
  'duration': 1000,
};

List<int> _ids(List<SongModel> l) => [for (final s in l) s.id];

final _now = DateTime(2026, 6, 15, 12);

void main() {
  group('buildContinueListening', () {
    final songs = [for (var i = 1; i <= 5; i++) _song(i, albumId: i)];
    final albums = [for (var i = 1; i <= 5; i++) _album(i)];

    test('newest first, one tile per album', () {
      final rows = [
        _row(1, _now.subtract(const Duration(days: 3))),
        _row(2, _now.subtract(const Duration(hours: 1))),
        _row(1, _now.subtract(const Duration(days: 1))),
        _row(3, _now.subtract(const Duration(days: 2))),
      ];
      final out = buildContinueListening(
        rows: rows,
        songs: songs,
        albums: albums,
      );
      expect([for (final a in out) a.id], [2, 1, 3]);
    });

    test('songs of one album collapse into it', () {
      final shared = [_song(1, albumId: 9), _song(2, albumId: 9)];
      final out = buildContinueListening(
        rows: [_row(1, _now), _row(2, _now.subtract(const Duration(days: 1)))],
        songs: shared,
        albums: [_album(9)],
      );
      expect(out.length, 1);
    });

    test('falls back to album name and artist when the song is gone', () {
      final out = buildContinueListening(
        rows: [_row(99, _now, album: 'album 4', artist: 'ARTIST 4')],
        songs: songs,
        albums: albums,
      );
      expect(out.single.id, 4);
    });

    test('skips albums no longer in the library', () {
      final out = buildContinueListening(
        rows: [
          _row(99, _now, album: 'Gone', artist: 'Nobody'),
          _row(100, _now, album: null),
          _row(2, _now.subtract(const Duration(days: 1))),
        ],
        songs: songs,
        albums: albums,
      );
      expect([for (final a in out) a.id], [2]);
    });

    test('is capped at 10 and empty without history', () {
      final many = [for (var i = 1; i <= 15; i++) _song(i, albumId: i)];
      final all = [for (var i = 1; i <= 15; i++) _album(i)];
      final rows = [
        for (var i = 1; i <= 15; i++)
          _row(i, _now.subtract(Duration(minutes: i))),
      ];
      final out = buildContinueListening(rows: rows, songs: many, albums: all);
      expect(out.length, 10);
      expect(out.first.id, 1);
      expect(
        buildContinueListening(rows: const [], songs: many, albums: all),
        isEmpty,
      );
    });
  });

  group('buildRediscover', () {
    final songs = [for (var i = 1; i <= 60; i++) _song(i)];
    final day = _now.millisecondsSinceEpoch;
    int ago(int days) =>
        _now.subtract(Duration(days: days)).millisecondsSinceEpoch;

    List<SongModel> pick(Map<int, SongStat> stats, {int seed = 1}) =>
        buildRediscover(songs: songs, stats: stats, now: _now, seed: seed);

    test('never played songs qualify, capped at 20', () {
      final out = pick({});
      expect(out.length, 20);
      expect(out.toSet().length, 20);
    });

    test('a 90 day cutoff splits old from recent plays', () {
      final stats = {
        for (var i = 1; i <= 30; i++)
          i: SongStat(playCount: 3, lastPlayedMs: ago(89)),
        for (var i = 31; i <= 40; i++)
          i: SongStat(playCount: 3, lastPlayedMs: ago(91)),
        41: SongStat(playCount: 0, lastPlayedMs: null),
      };
      final out = pick(stats, seed: 5);
      expect(_ids(out).every((id) => id > 30), isTrue);
      final all = buildRediscover(
        songs: songs,
        stats: stats,
        now: _now,
        seed: 5,
        limit: 100,
      );
      expect(all.length, 30);
      expect(day, greaterThan(0));
    });

    test('the same seed gives the same pick, in any library order', () {
      final a = pick({}, seed: shelfSeed(_now));
      final b = buildRediscover(
        songs: songs.reversed.toList(),
        stats: const {},
        now: _now,
        seed: shelfSeed(_now),
      );
      expect(_ids(a), _ids(b));
    });

    test('a re-roll or another day changes the pick', () {
      final a = pick({}, seed: shelfSeed(_now));
      final b = pick({}, seed: shelfSeed(_now, 1));
      final c = pick({}, seed: shelfSeed(_now.add(const Duration(days: 1))));
      expect(_ids(a), isNot(_ids(b)));
      expect(_ids(a), isNot(_ids(c)));
      expect(shelfSeed(_now.add(const Duration(hours: 5))), shelfSeed(_now));
    });

    test('hidden under 8 candidates, shown at exactly 8', () {
      Map<int, SongStat> played(int unplayed) => {
        for (var i = unplayed + 1; i <= 60; i++)
          i: SongStat(playCount: 1, lastPlayedMs: ago(1)),
      };
      expect(pick(played(7)), isEmpty);
      expect(pick(played(8)).length, 8);
    });
  });

  group('Home shelves', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.lucasjosino.on_audio_query'),
            (call) async => null,
          );
    });

    Widget app({
      List<Map<String, Object?>> history = const [],
      Map<int, SongStat> stats = const {},
      int count = 30,
    }) {
      final songs = [for (var i = 1; i <= count; i++) _song(i)];
      return ProviderScope(
        overrides: [
          historyStoreProvider.overrideWithValue(_FakeHistory(history)),
          songStatsStoreProvider.overrideWithValue(_FakeStats(stats)),
          libraryProvider.overrideWith(
            () => _FakeLibrary(
              LibraryState(
                songs: songs,
                filteredSongs: songs,
                albums: [for (var i = 1; i <= count; i++) _album(i)],
              ),
            ),
          ),
          playlistsProvider.overrideWith(
            () => _FakePlaylists(const PlaylistsState()),
          ),
          playerProvider.overrideWith(_FakePlayer.new),
          positionProvider.overrideWith(_FakePosition.new),
          durationProvider.overrideWith(_FakeDuration.new),
        ],
        child: MaterialApp(
          theme: WavvyTheme.light(WvAppearance.green),
          home: DefaultTabController(
            length: 3,
            child: const Scaffold(body: SafeArea(child: HomeView())),
          ),
        ),
      );
    }

    Future<void> pumpHome(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(411, 732) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(w);
      await tester.pump();
      await tester.pump();
    }

    Future<void> reveal(WidgetTester tester, String title) =>
        tester.scrollUntilVisible(
          find.text(title),
          200,
          scrollable: find.byType(Scrollable).first,
        );

    testWidgets('both shelves render when there is something to show', (
      tester,
    ) async {
      await pumpHome(
        tester,
        app(
          history: [
            _row(3, DateTime.now().subtract(const Duration(hours: 2))),
            _row(1, DateTime.now().subtract(const Duration(days: 1))),
          ],
        ),
      );
      await reveal(tester, 'Continue listening');
      expect(find.text('Continue listening'), findsOneWidget);
      expect(find.text('Album 3'), findsOneWidget);
      await reveal(tester, 'Rediscover');
      expect(find.text('Rediscover'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shuffle re-rolls the Rediscover pick', (tester) async {
      await pumpHome(tester, app(count: 60));
      await reveal(tester, 'Rediscover');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeView)),
      );
      final before = _ids(container.read(rediscoverProvider));
      expect(before, isNotEmpty);
      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      expect(container.read(rediscoverRerollProvider), 1);
      expect(_ids(container.read(rediscoverProvider)), isNot(before));
    });

    testWidgets('both are hidden with no history and few candidates', (
      tester,
    ) async {
      // 6 songs: under the 8 needed, and no plays recorded.
      await pumpHome(tester, app(count: 6));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('Continue listening'), findsNothing);
      expect(find.text('Rediscover'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeHistory implements HistoryStore {
  _FakeHistory(this.rows_);
  final List<Map<String, Object?>> rows_;

  @override
  Future<void> clear() async {}
  @override
  Future<void> log(Map<String, Object?> row) async {}
  @override
  Future<List<Map<String, Object?>>> rows({int? sinceMs}) async => rows_;
}

class _FakeStats implements SongStatsStore {
  _FakeStats(this.stats);
  final Map<int, SongStat> stats;
  @override
  Future<Map<int, SongStat>> load() async => stats;
}

class _FakeLibrary extends LibraryNotifier {
  _FakeLibrary(this.initial);
  final LibraryState initial;
  @override
  LibraryState build() => initial;
}

class _FakePlaylists extends PlaylistsNotifier {
  _FakePlaylists(this.initial);
  final PlaylistsState initial;
  @override
  PlaylistsState build() => initial;
}

class _FakePlayer extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}

class _FakePosition extends PositionNotifier {
  @override
  Duration build() => Duration.zero;
}

class _FakeDuration extends DurationNotifier {
  @override
  Duration build() => Duration.zero;
}
