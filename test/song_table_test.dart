import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/library_section_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/screens/library/library_tab.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

class _FakeLibrary extends LibraryNotifier {
  @override
  LibraryState build() {
    final songs = [for (var i = 1; i <= 30; i++) _song(i, 'Song $i')];
    return LibraryState(
      songs: songs,
      filteredSongs: songs,
      albums: [for (var i = 1; i <= 5; i++) _album(i)],
      artists: [for (var i = 1; i <= 5; i++) _artist(i)],
    );
  }
}

class _FakePlayer extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}

class _FakePlaylists extends PlaylistsNotifier {
  @override
  PlaylistsState build() => const PlaylistsState(
    playlists: [
      {'id': 1, 'name': 'Road trip'},
      {'id': 2, 'name': 'Focus'},
    ],
  );
}

SongModel _song(int id, String title) => SongModel({
  '_id': id,
  '_data': '/music/$title.mp3',
  '_uri': 'content://media/$id',
  '_display_name': '$title.mp3',
  '_display_name_wo_ext': title,
  '_size': 1024,
  'title': title,
  'artist': 'Artist $id',
  'album': 'Album',
  'duration': 180000 + id * 1000,
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

Widget _app({bool dark = false, double scale = 1.0}) {
  return ProviderScope(
    overrides: [
      libraryProvider.overrideWith(_FakeLibrary.new),
      playerProvider.overrideWith(_FakePlayer.new),
      playlistsProvider.overrideWith(_FakePlaylists.new),
    ],
    child: MaterialApp(
      theme: WavvyTheme.light(WvAppearance.green),
      darkTheme: WavvyTheme.dark(WvAppearance.red),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const Scaffold(body: SafeArea(child: LibraryTab())),
    ),
  );
}

void _mockArtworkChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.lucasjosino.on_audio_query'),
        (call) async => null,
      );
}

void main() {
  setUp(_mockArtworkChannel);

  void phone(WidgetTester tester, {double w = 411, double h = 732}) {
    tester.view.physicalSize = Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LibraryTab)));

  testWidgets('library tab lays out: title, pinned chips, sort chips, rows', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.byTooltip('Sort tracks'), findsOneWidget);
    expect(find.text('Play all'), findsOneWidget);
    expect(find.text('Song 1'), findsOneWidget);
  });

  testWidgets('30 rows scroll to the end without exceptions', (tester) async {
    phone(tester);
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -5000),
      3000,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Song 30'), findsOneWidget);
  });

  testWidgets('section chips stay pinned while the list scrolls', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Song 1'), findsNothing);
    expect(find.text('Library'), findsNothing); // header scrolled away
  });

  testWidgets('choosing a sort menu item changes the library sort', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(_app());
    await tester.pump();

    final container = containerOf(tester);
    expect(container.read(libraryProvider).sort, SortOption.titleAZ);

    await tester.tap(find.byTooltip('Sort tracks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Artist'));
    await tester.pump();
    expect(container.read(libraryProvider).sort, SortOption.artistAZ);

    await tester.tap(find.byTooltip('Sort tracks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently added'));
    await tester.pump();
    expect(container.read(libraryProvider).sort, SortOption.dateNewest);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping each chip shows its section', (tester) async {
    phone(tester);
    await tester.pumpWidget(_app());
    await tester.pump();
    final container = containerOf(tester);
    expect(container.read(librarySectionProvider), LibrarySection.songs);

    await tester.tap(find.text('Albums'));
    await tester.pump();
    expect(container.read(librarySectionProvider), LibrarySection.albums);
    expect(find.text('Album 1'), findsOneWidget);
    expect(find.text('Song 1'), findsNothing);
    expect(find.text('Title'), findsNothing);

    await tester.tap(find.text('Artists'));
    await tester.pump();
    expect(container.read(librarySectionProvider), LibrarySection.artists);
    expect(find.text('Artist 1'), findsOneWidget);
    expect(find.text('Album 1'), findsNothing);

    // The four pills are wider than the screen: the chip row scrolls.
    await tester.ensureVisible(find.text('Playlists'));
    await tester.pump();
    await tester.tap(find.text('Playlists'));
    await tester.pump();
    expect(container.read(librarySectionProvider), LibrarySection.playlists);
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('Focus'), findsOneWidget);
    expect(find.byTooltip('New Playlist'), findsOneWidget);

    await tester.ensureVisible(find.text('Songs'));
    await tester.pump();
    await tester.tap(find.text('Songs'));
    await tester.pump();
    expect(container.read(librarySectionProvider), LibrarySection.songs);
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.byTooltip('New Playlist'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'connected sections expose the active selection to accessibility',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(_app());
      bool selected(String label) => tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(Semantics),
            ),
          )
          .any((widget) => widget.properties.selected == true);
      expect(selected('Songs'), isTrue);
      expect(selected('Albums'), isFalse);
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      expect(selected('Songs'), isFalse);
      expect(selected('Albums'), isTrue);
    },
  );

  testWidgets(
    'library filter narrows rows and clears without changing the collection',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(_app());
      await tester.enterText(find.byType(TextField), 'Song 2');
      // The filter waits for a pause in typing, not every key.
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Song 1'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Song 1'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Song 2',
        ),
        findsOneWidget,
      );
      expect(containerOf(tester).read(libraryProvider).songs.length, 30);
      await tester.tap(find.byTooltip('Clear filter'));
      await tester.pump();
      expect(find.text('Song 1'), findsOneWidget);
    },
  );

  group('renders without exceptions', () {
    const sizes = [Size(411, 732), Size(360, 740)];
    for (final size in sizes) {
      for (final scale in [1.0, 1.5]) {
        for (final dark in [false, true]) {
          for (final section in LibrarySection.values) {
            testWidgets(
              '${section.name} ${size.width.toInt()}x${size.height.toInt()} '
              'x$scale ${dark ? 'dark' : 'light'}',
              (tester) async {
                phone(tester, w: size.width, h: size.height);
                await tester.pumpWidget(_app(dark: dark, scale: scale));
                await tester.pump();
                containerOf(
                  tester,
                ).read(librarySectionProvider.notifier).set(section);
                await tester.pump();
                await tester.pump();

                expect(tester.takeException(), isNull);
                await tester.drag(
                  find.byType(CustomScrollView),
                  const Offset(0, -400),
                );
                await tester.pump();
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    }
  });
}
