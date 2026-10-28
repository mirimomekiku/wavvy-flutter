import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/core/disc_numbers.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/library/albums/view/album.screen.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/disc_header.dart';

SongModel _song(int id, String title, int? track, {int album = 1}) =>
    SongModel({
      '_id': id,
      '_data': '/music/$id.mp3',
      '_uri': 'content://media/$id',
      'title': title,
      'artist': 'Artist',
      'album': 'Album',
      'album_id': album,
      'duration': 180000,
      'track': track,
      'is_music': true,
    });

List<int> _ids(Iterable<SongModel> s) => [for (final x in s) x.id];

void main() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  group('discOf and trackNumberOf', () {
    // track value -> disc, number
    final table = <(int?, int, int?)>[
      (null, 1, null),
      (0, 1, null),
      (-4, 1, null),
      (1, 1, 1),
      (7, 1, 7),
      (999, 1, 999),
      (1001, 1, 1),
      (1012, 1, 12),
      (2003, 2, 3),
      (10002, 10, 2),
      (2000, 2, null),
      (3150, 3, 150),
    ];
    for (final (track, disc, number) in table) {
      test('$track -> disc $disc, track $number', () {
        expect(discOf(track), disc);
        expect(trackNumberOf(track), number);
      });
    }
  });

  group('trackLabelOf', () {
    test('names the disc only when the value has one', () {
      expect(trackLabelOf(null), isNull);
      expect(trackLabelOf(0), isNull);
      expect(trackLabelOf(5), 'Track 5');
      expect(trackLabelOf(2003), 'Disc 2 - Track 3');
      expect(trackLabelOf(1001), 'Disc 1 - Track 1');
      expect(trackLabelOf(2000), 'Disc 2');
      expect(trackLabelOf(5, forceDisc: true), 'Disc 1 - Track 5');
    });
  });

  group('groupByDisc', () {
    test('orders discs, then track number, then title', () {
      final songs = [
        _song(1, 'D', 2002),
        _song(2, 'B', 1002),
        _song(3, 'A', 1001),
        _song(4, 'C', 2001),
        _song(5, 'E', 1003),
      ];
      final groups = groupByDisc(songs);
      expect(groups.map((g) => g.disc), [1, 2]);
      expect(_ids(groups[0].songs), [3, 2, 5]);
      expect(_ids(groups[1].songs), [4, 1]);
    });

    test('plain track numbers are one disc', () {
      final groups = groupByDisc([
        _song(1, 'x', 3),
        _song(2, 'y', 1),
        _song(3, 'z', 2),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.disc, 1);
      expect(_ids(groups.single.songs), [2, 3, 1]);
    });

    test('songs without a track follow the numbered ones, by title', () {
      final groups = groupByDisc([
        _song(1, 'zeta', null),
        _song(2, 'one', 1),
        _song(3, 'Alpha', 0),
        _song(4, 'two', 2),
      ]);
      expect(_ids(groups.single.songs), [2, 4, 3, 1]);
    });

    test('equal titles and tracks keep their incoming order', () {
      final a = _song(1, 'same', null);
      final b = _song(2, 'same', null);
      final c = _song(3, 'same', null);
      expect(_ids(sortByDisc([c, a, b])), [3, 1, 2]);
      expect(_ids(sortByDisc([a, b, c])), [1, 2, 3]);
    });

    test('same track number twice falls back to the title', () {
      expect(_ids(sortByDisc([_song(1, 'b', 4), _song(2, 'a', 4)])), [2, 1]);
    });

    test('an untagged song joins disc 1 beside plain numbers', () {
      final groups = groupByDisc([
        _song(1, 'untagged', null),
        _song(2, 'two', 2002),
        _song(3, 'one', 1),
      ]);
      expect(groups.map((g) => g.disc), [1, 2]);
      expect(_ids(groups[0].songs), [3, 1]);
    });

    test('empty input and a lone song', () {
      expect(groupByDisc(const []), isEmpty);
      expect(groupByDisc([_song(1, 'a', null)]), hasLength(1));
    });

    test('does not change the list it is given', () {
      final input = [_song(1, 'b', 2), _song(2, 'a', 1)];
      sortByDisc(input);
      expect(_ids(input), [1, 2]);
    });
  });

  group('album screen', () {
    late _Player player;

    Future<void> open(
      WidgetTester tester,
      List<SongModel> songs, {
      double scale = 1,
      bool dark = false,
    }) async {
      tester.view.physicalSize = const Size(640, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      player = _Player();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryProvider.overrideWith(() => _Library(songs)),
            playerProvider.overrideWith(() => player),
            settingsProvider.overrideWith(_Settings.new),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: WavvyTheme.light(WvAppearance.aqua),
            darkTheme: WavvyTheme.dark(WvAppearance.aqua),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: AlbumDetailScreen(
              album: AlbumModel({
                '_id': 1,
                'album': 'Album',
                'artist': 'Artist',
              }),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    final twoDiscs = [
      _song(1, 'Disc2 Second', 2002),
      _song(2, 'Disc1 Second', 1002),
      _song(3, 'Disc2 First', 2001),
      _song(4, 'Disc1 First', 1001),
      _song(9, 'Other album', 1, album: 2),
    ];

    for (final scale in [1.0, 1.5]) {
      for (final dark in [false, true]) {
        testWidgets('two discs: headers and order x$scale dark=$dark', (
          tester,
        ) async {
          await open(tester, twoDiscs, scale: scale, dark: dark);
          expect(find.byType(DiscHeaderRow), findsNWidgets(2));
          expect(find.text('Disc 1'), findsOneWidget);
          expect(find.text('Disc 2'), findsOneWidget);
          double y(String t) => tester.getTopLeft(find.text(t)).dy;
          expect(y('Disc 1'), lessThan(y('Disc1 First')));
          expect(y('Disc1 First'), lessThan(y('Disc1 Second')));
          expect(y('Disc1 Second'), lessThan(y('Disc 2')));
          expect(y('Disc 2'), lessThan(y('Disc2 First')));
          expect(y('Disc2 First'), lessThan(y('Disc2 Second')));
          expect(find.text('Other album'), findsNothing);
          expect(find.text('4 Songs'), findsOneWidget);
          // Track numbers lead the artist on a multi-disc album.
          expect(find.text('1 · Artist'), findsNWidgets(2));
          expect(find.text('2 · Artist'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a single-disc album has no headers or numbers', (
      tester,
    ) async {
      await open(tester, [
        _song(1, 'Second', 2),
        _song(2, 'First', 1),
        _song(3, 'Untagged', null),
      ]);
      expect(find.byType(DiscHeaderRow), findsNothing);
      // The header's subtitle plus one line per song, with no numbers.
      expect(find.text('Artist'), findsNWidgets(4));
      expect(find.textContaining('·'), findsNothing);
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('First'), lessThan(y('Second')));
      expect(y('Second'), lessThan(y('Untagged')));
    });

    testWidgets('Play, Shuffle and taps use disc and track order', (
      tester,
    ) async {
      await open(tester, twoDiscs);
      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(player.calls.last, 'play 4 in [4, 2, 3, 1]');
      await tester.tap(find.text('Disc2 First'));
      await tester.pump();
      expect(player.calls.last, 'play 3 in [4, 2, 3, 1]');
      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      expect(player.calls.last, startsWith('play '));
      expect(player.shuffledIds.toSet(), {1, 2, 3, 4});
    });

    testWidgets('long press still starts picking songs', (tester) async {
      await open(tester, twoDiscs);
      await tester.longPress(find.text('Disc1 Second'));
      await tester.pump();
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Settings extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState();
}

class _Library extends LibraryNotifier {
  _Library(this.songs);
  final List<SongModel> songs;
  @override
  LibraryState build() => LibraryState(songs: songs, filteredSongs: songs);
}

class _Player extends PlayerNotifier {
  final calls = <String>[];
  List<int> shuffledIds = const [];
  @override
  PlayerState build() => const PlayerState();
  @override
  Future<void> playSong(SongModel song, {List<SongModel>? contextList}) async {
    final ids = _ids(contextList ?? [song]);
    shuffledIds = ids;
    calls.add('play ${song.id} in $ids');
  }
}
