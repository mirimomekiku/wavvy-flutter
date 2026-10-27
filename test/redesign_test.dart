import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/artist_info_provider.dart';
import 'package:wavvy/providers/player_sheet_provider.dart';
import 'package:wavvy/providers/library_section_provider.dart';
import 'package:wavvy/providers/search_source_provider.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/downloader/models.dart';
import 'package:wavvy/downloader/search_provider.dart';
import 'package:wavvy/screens/library/library_tab.dart';
import 'package:wavvy/screens/search/search_tab.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:wavvy/screens/settings/settings.screen.dart';
import 'package:wavvy/screens/library/albums/view/album.screen.dart';
import 'package:wavvy/screens/library/artists/view/artist.screen.dart';
import 'package:wavvy/screens/library/playlists/view/playlist.screen.dart';
import 'package:just_audio/just_audio.dart' show AndroidEqualizerBand;
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/screens/audio_effects/effects.screen.dart';
import 'package:wavvy/widgets/lyric_card.dart';
import 'package:wavvy/models/lyric.dart';
import 'package:wavvy/widgets/vinyl_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/home/home.screen.dart';

import 'helpers/fake_engine.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';

SongModel _song(int id) => SongModel({
  '_id': id,
  '_data': '/music/s$id.mp3',
  '_uri': 'content://media/$id',
  '_display_name': 's$id.mp3',
  '_display_name_wo_ext': 's$id',
  '_size': 1024,
  'title': 'Song $id',
  'artist': 'Artist $id',
  'album': 'Album ${id % 3}',
  'album_id': id % 3,
  'artist_id': id,
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

class _FakeLibrary extends LibraryNotifier {
  @override
  LibraryState build() {
    final songs = [for (var i = 1; i <= 25; i++) _song(i)];
    return LibraryState(
      songs: songs,
      filteredSongs: songs,
      albums: [for (var i = 1; i <= 6; i++) _album(i)],
      artists: [for (var i = 1; i <= 6; i++) _artist(i)],
    );
  }
}

class _FakePlayer extends PlayerNotifier {
  @override
  PlayerState build() => PlayerState(
    queue: [for (var i = 1; i <= 5; i++) _song(i)],
    currentSong: _song(2),
    currentIndex: 1,
    isPlaying: true,
  );
}

class _FakePosition extends PositionNotifier {
  @override
  Duration build() => const Duration(seconds: 42);
}

class _FakeDuration extends DurationNotifier {
  @override
  Duration build() => const Duration(minutes: 3, seconds: 20);
}

class _FakeSettings extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState();
}

class _FakePlaylists extends PlaylistsNotifier {
  @override
  Future<List<SongModel>> getSongsInPlaylist(int playlistId) async => [
    for (int i = 1; i <= 6; i++) _song(i),
  ];
  @override
  PlaylistsState build() => PlaylistsState(
    playlists: [
      {'id': 1, 'name': 'Road trip'},
      {'id': 2, 'name': 'Focus'},
    ],
    mostPlayed: [for (var i = 1; i <= 6; i++) _song(i)],
    recent: [for (var i = 3; i <= 8; i++) _song(i)],
  );
}

class _PreviewLyrics extends LyricsNotifier {
  _PreviewLyrics(this.populated);
  final bool populated;
  @override
  LyricsState build() => populated
      ? LyricsState(
          currentIndex: 1,
          lyrics: [
            Lyric(Duration.zero, 'A little room to breathe.'),
            Lyric(const Duration(seconds: 40), 'Your music, wherever you go.'),
            Lyric(const Duration(seconds: 60), 'Another day in motion.'),
          ],
        )
      : const LyricsState();
}

class _PreviewArtist extends ArtistInfoNotifier {
  @override
  ArtistInfoState build() => const ArtistInfoState(
    bio:
        'An independent artist from your music collection. Artist information and artwork appear here when available online.',
  );
}

class _PreviewPage extends SheetPageIndexNotifier {
  _PreviewPage(this.page);
  final int page;
  @override
  int build() => page;
}

class _PreviewBand extends Fake implements AndroidEqualizerBand {
  _PreviewBand(this.centerFrequency, this.gain);
  @override
  final double centerFrequency;
  @override
  final double gain;
  @override
  Stream<double> get gainStream => Stream.value(gain);
}

class _PreviewEq extends EqualizerNotifier {
  @override
  EqualizerState build() => EqualizerState(
    isEnabled: true,
    currentPreset: 'Rock',
    bands: [
      _PreviewBand(60, 5),
      _PreviewBand(230, 3),
      _PreviewBand(910, -1),
      _PreviewBand(3600, 3),
      _PreviewBand(14000, 5),
    ],
  );
}

class _PreviewSource extends SearchSourceNotifier {
  _PreviewSource(this.source);
  final SearchSource source;
  @override
  SearchSource build() => source;
}

class _PreviewSection extends LibrarySectionNotifier {
  _PreviewSection(this.section);
  final LibrarySection section;
  @override
  LibrarySection build() => section;
}

class _PreviewOnline extends OnlineSearchNotifier {
  @override
  OnlineSearchState build() => OnlineSearchState(
    query: 'evening drive',
    hasSearched: true,
    results: [
      fakeMedia(
        'a',
        title: 'Evening drive',
        artist: 'Night Radio',
        seconds: 245,
      ),
      fakeMedia('b', title: 'City lights', artist: 'Night Radio', seconds: 198),
      fakeMedia(
        'c',
        title: 'Slow afternoons',
        artist: 'Quiet Hours',
        seconds: 312,
      ),
    ],
  );
}

Widget _app(
  Widget screen, {
  bool dark = false,
  double scale = 1.0,
  int page = 0,
  LibrarySection section = LibrarySection.songs,
  SearchSource source = SearchSource.library,
}) {
  return ProviderScope(
    overrides: [
      libraryProvider.overrideWith(_FakeLibrary.new),
      playerProvider.overrideWith(_FakePlayer.new),
      playlistsProvider.overrideWith(_FakePlaylists.new),
      positionProvider.overrideWith(_FakePosition.new),
      durationProvider.overrideWith(_FakeDuration.new),
      settingsProvider.overrideWith(_FakeSettings.new),
      lyricsProvider.overrideWith(() => _PreviewLyrics(page == 2)),
      artistInfoProvider.overrideWith(_PreviewArtist.new),
      sheetPageIndexProvider.overrideWith(() => _PreviewPage(page)),
      librarySectionProvider.overrideWith(() => _PreviewSection(section)),
      searchSourceProvider.overrideWith(() => _PreviewSource(source)),
      equalizerProvider.overrideWith(_PreviewEq.new),
      ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
      downloadStoreProvider.overrideWithValue(
        FakeDownloadStore([
          fakeTask(
            '1',
            title: 'Evening drive',
            status: DownloadStatus.running,
            progress: 42,
          ),
          fakeTask('2', title: 'City lights', status: DownloadStatus.complete),
        ]),
      ),
      onlineSearchProvider.overrideWith(_PreviewOnline.new),
    ],
    child: MaterialApp(
      theme: WavvyTheme.light(WvAppearance.aqua),
      darkTheme: WavvyTheme.dark(WvAppearance.aqua),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: screen,
    ),
  );
}

void main() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
      for (final entry in {
        'WorkSans': 'assets/fonts/WorkSans.ttf',
        'serif':
            '${const String.fromEnvironment('PREVIEW_FONT_DIR')}/georgia.ttf',
        'sans-serif':
            '${const String.fromEnvironment('PREVIEW_FONT_DIR')}/segoeui.ttf',
        'monospace':
            '${const String.fromEnvironment('PREVIEW_FONT_DIR')}/consola.ttf',
        'MaterialIcons': const String.fromEnvironment('PREVIEW_ICON_FONT'),
      }.entries) {
        final font = File(entry.value);
        if (await font.exists()) {
          final loader = FontLoader(entry.key)
            ..addFont(
              font.readAsBytes().then((data) => ByteData.sublistView(data)),
            );
          await loader.load();
        }
      }
    }
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
  });
  final screens = <String, Widget>{
    'home': const HomeScreen(),
    'library': const Scaffold(body: LibraryTab()),
    'search': const Scaffold(body: SearchTab()),
    'player': const Scaffold(body: FullPlayerSheet()),
    'queue': const Scaffold(body: FullPlayerSheet(initialPage: 1)),
    'lyrics': const Scaffold(body: FullPlayerSheet(initialPage: 2)),
    'artist-info': const Scaffold(body: FullPlayerSheet(initialPage: 3)),
    'library-albums': const Scaffold(body: LibraryTab()),
    'library-artists': const Scaffold(body: LibraryTab()),
    'library-playlists': const Scaffold(body: LibraryTab()),
    'online': const Scaffold(body: SearchTab()),
    'feedback': const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AquaToast(
              title: 'Downloaded',
              subtitle: 'ICED COFFEE O MANGO SHAKE',
              kind: ToastKind.success,
            ),
            SizedBox(height: 14),
            AquaToast(
              title: 'Could not play',
              subtitle: 'Could not play Song 3.',
              kind: ToastKind.error,
            ),
            SizedBox(height: 14),
            AquaToast(
              title: 'Sleep Timer',
              subtitle: 'Music will stop in 30 minutes',
            ),
            SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AquaCheckMark(size: 26),
                SizedBox(width: 24),
                AquaCheckMark(size: 40),
                SizedBox(width: 24),
                AquaSpinner(size: 24),
                SizedBox(width: 24),
                AquaSpinner(size: 40),
                SizedBox(width: 24),
                AquaProgressRing(
                  value: 0.6,
                  child: Icon(Icons.close_rounded, size: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    'settings': const SettingsScreen(),
    'album': AlbumDetailScreen(album: _album(1)),
    'artist': ArtistDetailScreen(artist: _artist(1)),
    'playlist': const PlaylistDetailScreen(
      playlistId: 1,
      playlistName: 'Slow afternoons',
    ),
    'audio': const AudioEffectsScreen(),
    'share': LyricCardGenerator(
      song: _song(1),
      lyrics: [Lyric(Duration.zero, 'A little music for your day')],
      themeColor: const Color(0xFF7960A8),
    ),
  };
  testWidgets('short landscape keeps playback and page content reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(740 * 2, 360 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(const Scaffold(body: FullPlayerSheet()), scale: 1.5),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    for (final label in ['Queue', 'Lyrics', 'About', 'Player']) {
      await tester.tap(find.byTooltip(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: label);
      expect(
        find.byTooltip('Pause'),
        label == 'Player' ? findsOneWidget : findsNothing,
      );
    }
  });
  for (final dark in [false, true]) {
    testWidgets('compact player and tabs at large text dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(const Scaffold(body: FullPlayerSheet()), dark: dark, scale: 1.5),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      for (final label in ['Queue', 'Lyrics', 'About', 'Player']) {
        await tester.ensureVisible(find.byTooltip(label));
        await tester.tap(find.byTooltip(label));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull, reason: label);
        expect(
          find.byTooltip('Pause'),
          label == 'Player' ? findsOneWidget : findsNothing,
        );
      }
    });
  }
  for (final dark in [false, true]) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} Kaisu layout dark=$dark', (tester) async {
        tester.view.physicalSize = const Size(390 * 2, 844 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          _app(
            RepaintBoundary(key: captureKey, child: entry.value),
            dark: dark,
            page:
                const {'queue': 1, 'lyrics': 2, 'artist-info': 3}[entry.key] ??
                0,
            section:
                const {
                  'library-albums': LibrarySection.albums,
                  'library-artists': LibrarySection.artists,
                  'library-playlists': LibrarySection.playlists,
                }[entry.key] ??
                LibrarySection.songs,
            source:
                const {'online': SearchSource.online}[entry.key] ??
                SearchSource.library,
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        if (entry.key == 'share') {
          await tester.tap(find.text('A little music for your day').last);
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        if (entry.key == 'player') {
          expect(find.byType(VinylDeck), findsOneWidget);
        }
        if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
          final boundary =
              captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final output = File(
              'build/kaisu-previews/${entry.key}-${dark ? 'dark' : 'light'}.png',
            );
            await output.parent.create(recursive: true);
            await output.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }
}
