import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/playback/history.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/stats/stats.screen.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

class _Store implements HistoryStore {
  _Store(this.data);
  List<Map<String, Object?>> data;
  int clears = 0;

  @override
  Future<void> log(Map<String, Object?> row) async => data = [row, ...data];

  @override
  Future<List<Map<String, Object?>>> rows({int? sinceMs}) async => [
    for (final r in data)
      if (sinceMs == null || (r['played_at'] as int) >= sinceMs) r,
  ];

  @override
  Future<void> clear() async {
    clears++;
    data = [];
  }
}

class _Library extends LibraryNotifier {
  @override
  LibraryState build() => LibraryState(songs: [_song(1)]);
}

class _Player extends PlayerNotifier {
  static final played = <int>[];
  @override
  PlayerState build() => const PlayerState();
  @override
  Future<void> playSong(SongModel song, {List<SongModel>? contextList}) async =>
      played.add(song.id);
}

SongModel _song(int id) => SongModel({
  '_id': id,
  '_data': '/music/$id.mp3',
  '_uri': 'content://media/$id',
  'title': 'Song $id',
  'duration': 180000,
});

Map<String, Object?> _row(
  int song,
  Duration ago, {
  String artist = 'Artist',
  String album = 'Album',
}) => {
  'song_id': song,
  'played_at': DateTime.now().subtract(ago).millisecondsSinceEpoch,
  'title': 'Song $song',
  'artist': artist,
  'album': album,
  'duration': 180000,
};

Widget _app(_Store store, {double scale = 1, bool dark = false}) =>
    ProviderScope(
      overrides: [
        historyStoreProvider.overrideWithValue(store),
        libraryProvider.overrideWith(_Library.new),
        playerProvider.overrideWith(_Player.new),
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
        home: const StatsScreen(),
      ),
    );

void _size(WidgetTester tester) {
  // Tall, so the lazy list builds every section.
  tester.view.physicalSize = const Size(360, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<Map<String, Object?>> _populated() => [
  _row(1, const Duration(minutes: 5)),
  _row(1, const Duration(hours: 2)),
  _row(2, const Duration(days: 1, hours: 2), artist: 'Other', album: 'Disc'),
  _row(3, const Duration(days: 20), artist: 'Old', album: 'Vault'),
];

void main() {
  for (final scale in [1.0, 1.5]) {
    group('StatsScreen at ${scale}x', () {
      testWidgets('empty state mentions incognito', (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(_Store([]), scale: scale));
        await tester.pumpAndSettle();
        expect(find.textContaining('No plays yet'), findsOneWidget);
        expect(find.textContaining('Incognito'), findsOneWidget);
        expect(find.text('Clear history'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('populated state, light and dark', (tester) async {
        _size(tester);
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            _app(_Store(_populated()), scale: scale, dark: dark),
          );
          await tester.pumpAndSettle();
          expect(find.text('Top songs'), findsOneWidget);
          expect(find.text('Top artists'), findsOneWidget);
          expect(find.text('Top albums'), findsOneWidget);
          expect(find.text('2 plays'), findsWidgets);
          expect(find.text('PLAYS'), findsOneWidget);
          expect(find.text('EST. LISTENING TIME'), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp('plays in the last 14')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('period switch changes the totals', (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(_Store(_populated()), scale: scale));
        await tester.pumpAndSettle();
        expect(find.text('3'), findsWidgets); // 3 plays in 7 days
        // The chip row scrolls sideways when the text is large.
        await tester.ensureVisible(find.text('All time'));
        await tester.tap(find.text('All time'));
        await tester.pumpAndSettle();
        expect(find.text('4'), findsWidgets);
        expect(find.text('Vault'), findsOneWidget);
        await tester.ensureVisible(find.text('7 days'));
        await tester.tap(find.text('7 days'));
        await tester.pumpAndSettle();
        expect(find.text('Vault'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('clear history asks first, then empties', (tester) async {
        _size(tester);
        final store = _Store(_populated());
        await tester.pumpWidget(_app(store, scale: scale));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear history'));
        await tester.pumpAndSettle();
        expect(find.text('Clear listening history?'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(store.clears, 0);

        await tester.tap(find.text('Clear history'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(store.clears, 1);
        expect(find.textContaining('No plays yet'), findsOneWidget);
      });

      testWidgets('tapping a song in the library plays it', (tester) async {
        _size(tester);
        _Player.played.clear();
        await tester.pumpWidget(_app(_Store(_populated()), scale: scale));
        await tester.pumpAndSettle();
        // Song 1 is in the library; song 2 is not and does nothing.
        await tester.tap(find.text('Song 1').first);
        expect(_Player.played, [1]);
        await tester.tap(find.text('Song 2').first);
        expect(_Player.played, [1]);
      });
    });
  }
}
