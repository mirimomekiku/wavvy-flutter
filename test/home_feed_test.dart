import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/home_feed_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/library_section_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/screens/home/view/home_view.dart';
import 'package:wavvy/screens/settings/settings.screen.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

SongModel _song(
  int id, {
  int? albumId,
  int? artistId,
  String? artist,
  int dateAdded = 0,
}) => SongModel({
  '_id': id,
  '_data': '/music/s$id.mp3',
  '_uri': 'content://media/$id',
  '_display_name': 's$id.mp3',
  '_display_name_wo_ext': 's$id',
  '_size': 1024,
  'title': 'Song $id',
  'artist': artist ?? 'Artist ${artistId ?? id}',
  'artist_id': artistId ?? id,
  'album_id': albumId ?? id,
  'album': 'Album ${albumId ?? id}',
  'date_added': dateAdded,
  'duration': 200000,
  'is_music': true,
});

AlbumModel _album(int id) => AlbumModel({
  '_id': id,
  'album': 'Album $id',
  'artist': 'Artist $id',
  'numsongs': 5,
});

ArtistModel _artist(int id) => ArtistModel({
  '_id': id,
  'artist': 'Artist $id',
  'number_of_albums': 2,
  'number_of_tracks': 7,
});

HomeFeed _feed({
  List<SongModel> songs = const [],
  List<AlbumModel> albums = const [],
  List<ArtistModel> artists = const [],
  List<SongModel> recent = const [],
  List<SongModel> mostPlayed = const [],
  List<Map<String, dynamic>> playlists = const [],
  DateTime? now,
}) => buildHomeFeed(
  songs: songs,
  albums: albums,
  artists: artists,
  recent: recent,
  mostPlayed: mostPlayed,
  playlists: playlists,
  now: now ?? DateTime(2026, 1, 2),
);

List<int> _ids(List<SongModel> l) => [for (final s in l) s.id];

void main() {
  group('buildHomeFeed', () {
    test('recently added songs are newest first and capped at 20', () {
      final songs = [for (var i = 1; i <= 30; i++) _song(i, dateAdded: i)];
      final feed = _feed(songs: songs);
      expect(feed.recentlyAdded.length, 20);
      expect(feed.recentlyAdded.first.id, 30);
      expect(feed.recentlyAdded.last.id, 11);
    });

    test('recent albums ordered by newest song, capped at 12', () {
      final albums = [for (var i = 1; i <= 15; i++) _album(i)];
      final songs = [for (var i = 1; i <= 15; i++) _song(i, dateAdded: i)];
      // Album 2 gets the newest song of all.
      songs.add(_song(99, albumId: 2, dateAdded: 1000));
      final feed = _feed(songs: songs, albums: albums);
      expect(feed.recentAlbums.length, 12);
      expect(feed.recentAlbums.first.id, 2);
      expect(feed.recentAlbums[1].id, 15);
    });

    test('top artists are ranked by history, score > 0 only', () {
      final artists = [for (var i = 1; i <= 5; i++) _artist(i)];
      final songs = [
        for (var i = 1; i <= 10; i++) _song(i, artistId: i % 5 + 1),
      ];
      final recent = [_song(1, artistId: 3), _song(2, artistId: 3)];
      final most = [_song(3, artistId: 3), _song(4, artistId: 2)];
      final feed = _feed(
        songs: songs,
        artists: artists,
        recent: recent,
        mostPlayed: most,
      );
      expect([for (final a in feed.topArtists) a.id], [3, 2]);
      expect(feed.moreFromArtist?.id, 3);
    });

    test('top artists fall back to name match', () {
      final feed = _feed(
        songs: [_song(1, artistId: 777, artist: 'Artist 1')],
        artists: [_artist(1)],
        recent: [_song(1, artistId: 777, artist: 'Artist 1')],
      );
      expect(feed.topArtists.single.id, 1);
    });

    test('moreFrom excludes recent songs and is capped at 15', () {
      final songs = [for (var i = 1; i <= 30; i++) _song(i, artistId: 1)];
      final recent = [songs[0], songs[1]];
      final feed = _feed(songs: songs, artists: [_artist(1)], recent: recent);
      expect(feed.moreFrom.length, 15);
      expect(_ids(feed.moreFrom).contains(1), isFalse);
      expect(_ids(feed.moreFrom).contains(2), isFalse);
    });

    test('daily mix is stable within a day and differs across days', () {
      final songs = [for (var i = 1; i <= 60; i++) _song(i)];
      final a = _feed(songs: songs, now: DateTime(2026, 3, 4, 8));
      final b = _feed(
        songs: songs.reversed.toList(),
        now: DateTime(2026, 3, 4, 22),
      );
      final c = _feed(songs: songs, now: DateTime(2026, 3, 5));
      expect(a.dailyMix.length, 25);
      expect(_ids(a.dailyMix), _ids(b.dailyMix));
      expect(_ids(a.dailyMix), isNot(_ids(c.dailyMix)));
    });

    test('discover excludes played songs and is capped at 15', () {
      final songs = [for (var i = 1; i <= 60; i++) _song(i)];
      final recent = songs.take(10).toList();
      final most = songs.skip(10).take(10).toList();
      final feed = _feed(songs: songs, recent: recent, mostPlayed: most);
      expect(feed.discover.length, 15);
      expect(_ids(feed.discover).every((id) => id > 20), isTrue);
    });

    test('empty history still yields browsing sections', () {
      final songs = [for (var i = 1; i <= 8; i++) _song(i, dateAdded: i)];
      final feed = _feed(
        songs: songs,
        albums: [for (var i = 1; i <= 8; i++) _album(i)],
        artists: [_artist(1)],
      );
      expect(feed.recentSongs, isEmpty);
      expect(feed.mostPlayed, isEmpty);
      expect(feed.topArtists, isEmpty);
      expect(feed.moreFrom, isEmpty);
      expect(feed.moreFromArtist, isNull);
      expect(feed.recentAlbums, isNotEmpty);
      expect(feed.recentlyAdded.length, 8);
      expect(feed.dailyMix.length, 8);
      expect(feed.discover.length, 8);
      expect(feed.quickAccess, isNotEmpty);
    });

    test('quick access: playlists first, max 6, no duplicate albums', () {
      final albums = [for (var i = 1; i <= 10; i++) _album(i)];
      final songs = [for (var i = 1; i <= 10; i++) _song(i, dateAdded: i)];
      final feed = _feed(
        songs: songs,
        albums: albums,
        recent: [songs[0]],
        playlists: [
          {'id': 1, 'name': 'A'},
          {'id': 2, 'name': 'B'},
          {'id': 3, 'name': 'C'},
        ],
      );
      final q = feed.quickAccess;
      expect(q.length, 6);
      expect(q[0].kind, QuickAccessKind.playlist);
      expect(q[1].kind, QuickAccessKind.playlist);
      expect(q.where((e) => e.kind == QuickAccessKind.playlist).length, 2);
      final albumIds = [
        for (final e in q)
          if (e.kind == QuickAccessKind.album) e.id,
      ];
      expect(albumIds.toSet().length, albumIds.length);
    });

    test('no songs gives an empty feed', () {
      final feed = _feed();
      expect(feed.dailyMix, isEmpty);
      expect(feed.quickAccess, isEmpty);
    });
  });

  group('HomeView', () {
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
      required Size size,
      required double scale,
      required bool dark,
      bool empty = false,
    }) {
      final songs = empty
          ? <SongModel>[]
          : [for (var i = 1; i <= 30; i++) _song(i, dateAdded: i)];
      return ProviderScope(
        overrides: [
          libraryProvider.overrideWith(
            () => _FakeLibrary(
              LibraryState(
                songs: songs,
                filteredSongs: songs,
                albums: empty ? [] : [for (var i = 1; i <= 14; i++) _album(i)],
                artists: empty ? [] : [for (var i = 1; i <= 6; i++) _artist(i)],
              ),
            ),
          ),
          playlistsProvider.overrideWith(
            () => _FakePlaylists(
              PlaylistsState(
                playlists: empty
                    ? []
                    : [
                        {'id': 1, 'name': 'Road trip'},
                        {'id': 2, 'name': 'Focus'},
                      ],
                recent: empty ? [] : songs.take(8).toList(),
                mostPlayed: empty ? [] : songs.skip(5).take(8).toList(),
              ),
            ),
          ),
          playerProvider.overrideWith(_FakePlayer.new),
          positionProvider.overrideWith(_FakePosition.new),
          durationProvider.overrideWith(_FakeDuration.new),
        ],
        child: MaterialApp(
          theme: dark
              ? WavvyTheme.dark(WvAppearance.green)
              : WavvyTheme.light(WvAppearance.green),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: DefaultTabController(
            length: 3,
            child: const Scaffold(body: SafeArea(child: HomeView())),
          ),
        ),
      );
    }

    void view(WidgetTester tester, Size size) {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    for (final size in const [Size(411, 732), Size(360, 740)]) {
      for (final scale in const [1.0, 1.5]) {
        for (final dark in const [false, true]) {
          for (final empty in const [false, true]) {
            testWidgets('renders ${size.width.toInt()}x${size.height.toInt()} '
                'x$scale ${dark ? 'dark' : 'light'}${empty ? ' empty' : ''}', (
              tester,
            ) async {
              view(tester, size);
              await tester.pumpWidget(
                app(size: size, scale: scale, dark: dark, empty: empty),
              );
              await tester.pump();
              expect(tester.takeException(), isNull);
              if (empty) {
                expect(find.text('No Songs'), findsOneWidget);
              } else {
                expect(find.text('Jump back in'), findsOneWidget);
                await tester.fling(
                  find.byType(CustomScrollView),
                  const Offset(0, -3000),
                  3000,
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
              }
            });
          }
        }
      }
    }

    testWidgets('Show all under recent albums sets the library section', (
      tester,
    ) async {
      view(tester, const Size(411, 732));
      await tester.pumpWidget(
        app(size: const Size(411, 732), scale: 1, dark: true),
      );
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeView)),
      );
      expect(container.read(librarySectionProvider), LibrarySection.songs);

      await tester.scrollUntilVisible(
        find.text('Recently added albums'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final header = find.ancestor(
        of: find.text('Recently added albums'),
        matching: find.byType(Row),
      );
      final showAll = find.descendant(
        of: header.first,
        matching: find.text('Show all'),
      );
      await tester.ensureVisible(showAll);
      await tester.pumpAndSettle();
      await tester.tap(showAll);
      await tester.pump();
      expect(container.read(librarySectionProvider), LibrarySection.albums);
      expect(tester.takeException(), isNull);
    });
  });

  group('Expressive shell widgets', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    for (final scale in const [1.0, 1.5]) {
      testWidgets('settings + nav render at text x$scale', (tester) async {
        tester.view.physicalSize = const Size(360, 740) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerProvider.overrideWith(_FakePlayer.new),
              positionProvider.overrideWith(_FakePosition.new),
              durationProvider.overrideWith(_FakeDuration.new),
            ],
            child: MaterialApp(
              theme: WavvyTheme.dark(WvAppearance.green),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: DefaultTabController(
                length: 3,
                child: const Scaffold(
                  body: SettingsScreen(),
                  bottomNavigationBar: BottomMiniPlayer(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Aqua'), findsOneWidget);
        expect(find.byKey(const Key('nav_library')), findsOneWidget);
        await tester.tap(find.text('Graphite'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _FakeLibrary extends LibraryNotifier {
  final LibraryState initial;
  _FakeLibrary(this.initial);

  @override
  LibraryState build() => initial;
}

class _FakePlaylists extends PlaylistsNotifier {
  final PlaylistsState initial;
  _FakePlaylists(this.initial);

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
