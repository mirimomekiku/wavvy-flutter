import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/player_sheets/artist_page.dart';
import 'package:wavvy/providers/artist_info_provider.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/screens/downloader/downloads_sheet.dart';
import 'package:wavvy/screens/library/library_tab.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

import 'helpers/fake_engine.dart';

SongModel _song(int id, {String artist = 'New Order'}) => SongModel({
  '_id': id,
  '_data': '/music/$id.mp3',
  '_uri': 'content://media/$id',
  'title': 'Song $id',
  'artist': artist,
  'artist_id': 1,
  'album': 'Power',
  'duration': 240000,
  'is_music': true,
});

class _Library extends LibraryNotifier {
  _Library(this.songs);
  final List<SongModel> songs;
  @override
  LibraryState build() => LibraryState(songs: songs, filteredSongs: songs);
}

class _Playlists extends PlaylistsNotifier {
  @override
  PlaylistsState build() => const PlaylistsState();
}

class _Player extends PlayerNotifier {
  _Player(this.song);
  final SongModel? song;
  @override
  PlayerState build() => PlayerState(currentSong: song);
}

class _Artist extends ArtistInfoNotifier {
  _Artist(this.value);
  final ArtistInfoState value;
  @override
  ArtistInfoState build() => value;
}

Widget _host(
  Widget child, {
  required List<Override> overrides,
  double topInset = 0,
  double scale = 1,
  bool dark = false,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: WavvyTheme.light(WvAppearance.aqua),
    darkTheme: WavvyTheme.dark(WvAppearance.aqua),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        padding: EdgeInsets.only(top: topInset),
      ),
      child: c!,
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
  });

  testWidgets('pinned library chips stay below the status bar', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final songs = [for (var i = 1; i <= 80; i++) _song(i)];
    await tester.pumpWidget(
      _host(
        const LibraryTab(),
        topInset: 40,
        overrides: [
          libraryProvider.overrideWith(() => _Library(songs)),
          playlistsProvider.overrideWith(_Playlists.new),
          playerProvider.overrideWith(() => _Player(null)),
        ],
      ),
    );
    await tester.pump();
    final chips = find.text('Songs');
    expect(chips, findsOneWidget);

    // Not scrolled yet: the chips follow the search field directly. The status
    // bar inset must not open a gap between them.
    final search = find.byType(AquaSearchFrame);
    final gap = tester.getTopLeft(chips).dy - tester.getBottomLeft(search).dy;
    expect(gap, lessThan(30));
    expect(tester.getTopLeft(chips).dy, greaterThanOrEqualTo(40));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pump();
    // Pinned now: the chip text must sit under the 40px status bar, not in it.
    expect(tester.getTopLeft(chips).dy, greaterThanOrEqualTo(40));
    expect(tester.takeException(), isNull);
  });

  group('artist tab', () {
    List<Override> overrides(ArtistInfoState info, {SongModel? song}) => [
      libraryProvider.overrideWith(
        () => _Library([for (var i = 1; i <= 3; i++) _song(i)]),
      ),
      playerProvider.overrideWith(() => _Player(song ?? _song(1))),
      artistInfoProvider.overrideWith(() => _Artist(info)),
    ];

    testWidgets('shows the artist, readout, biography and songs', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          const ArtistInfoPage(),
          overrides: overrides(const ArtistInfoState(bio: 'A short bio.')),
        ),
      );
      await tester.pump();
      expect(find.text('Artist'), findsOneWidget);
      expect(find.text('New Order'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      expect(find.text('A short bio.'), findsOneWidget);
      expect(find.text('TRACKS'), findsOneWidget);
      expect(find.text('12 m'), findsOneWidget); // 3 x 4 min
      expect(find.text('In your library'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long biography collapses and expands', (tester) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          const ArtistInfoPage(),
          overrides: overrides(ArtistInfoState(bio: 'Word ' * 200)),
        ),
      );
      await tester.pump();
      expect(find.text('Show more'), findsOneWidget);
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('loading and failure are explained, failure can retry', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          const ArtistInfoPage(),
          overrides: overrides(const ArtistInfoState(isLoading: true)),
        ),
      );
      await tester.pump();
      expect(find.text('Loading artist information…'), findsOneWidget);

      // A fresh scope, so the new overrides apply.
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(
        _host(
          const ArtistInfoPage(),
          overrides: overrides(
            const ArtistInfoState(
              bio: 'Could not load this artist. Check your connection.',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('an unknown artist has no biography to fetch', (tester) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          const ArtistInfoPage(),
          overrides: overrides(
            const ArtistInfoState(),
            song: _song(9, artist: '<unknown>'),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('There is no artist information for this song.'),
        findsOneWidget,
      );
    });

    for (final dark in [false, true]) {
      testWidgets('fits 320 wide at 1.5x text (dark: $dark)', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _host(
            const ArtistInfoPage(),
            dark: dark,
            scale: 1.5,
            overrides: overrides(ArtistInfoState(bio: 'Word ' * 200)),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('the downloads sheet covers the whole screen', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showDownloadsSheet(context),
            child: const Text('open'),
          ),
        ),
        overrides: [
          ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
          downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
        ],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AquaSheet)), const Size(360, 740));
    expect(find.text('Downloads'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AquaSheet), findsNothing);
  });
}
