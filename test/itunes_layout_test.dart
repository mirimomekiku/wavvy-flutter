import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/player_sheets/layouts/itunes_layout.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/providers/artist_info_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/settings/player_layout_setting.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

SongModel _song(int id) => SongModel({
  '_id': id,
  '_data': '/music/s$id.mp3',
  '_uri': 'content://media/$id',
  '_display_name': 's$id.mp3',
  '_display_name_wo_ext': 's$id',
  '_size': 1024,
  'title': 'Song $id with a rather long title to test ellipsis',
  'artist': 'Artist $id',
  'album': 'Album $id',
  'album_id': id,
  'artist_id': id,
  'duration': 200000,
  'is_music': true,
});

class _Library extends LibraryNotifier {
  @override
  LibraryState build() => LibraryState(songs: [_song(1)]);
}

class _Player extends PlayerNotifier {
  static int toggles = 0;
  static int nexts = 0;
  static final seeks = <Duration>[];
  @override
  PlayerState build() => PlayerState(
    queue: [for (var i = 1; i <= 3; i++) _song(i)],
    currentSong: _song(2),
    currentIndex: 1,
    isPlaying: true,
  );
  @override
  Future<void> togglePlay() async => toggles++;
  @override
  Future<void> next() async => nexts++;
  @override
  Future<void> seek(Duration position, {bool relative = false}) async =>
      seeks.add(position);
}

class _Position extends PositionNotifier {
  @override
  Duration build() => const Duration(seconds: 42);
}

class _Duration extends DurationNotifier {
  @override
  Duration build() => const Duration(minutes: 3, seconds: 20);
}

class _Settings extends SettingsNotifier {
  _Settings(this.layout);
  final PlayerLayout layout;
  @override
  SettingsState build() =>
      SettingsState(playerLayout: layout.index, playerLayoutAdaptive: false);
}

class _Playlists extends PlaylistsNotifier {
  @override
  PlaylistsState build() => const PlaylistsState();
}

class _Lyrics extends LyricsNotifier {
  @override
  LyricsState build() => const LyricsState();
}

class _Artist extends ArtistInfoNotifier {
  @override
  ArtistInfoState build() => const ArtistInfoState();
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(
  Widget screen, {
  bool dark = false,
  double scale = 1.0,
  bool reduceMotion = false,
  WvAppearance appearance = WvAppearance.aqua,
  PlayerLayout layout = PlayerLayout.itunes,
}) {
  return ProviderScope(
    overrides: [
      libraryProvider.overrideWith(_Library.new),
      playerProvider.overrideWith(_Player.new),
      playlistsProvider.overrideWith(_Playlists.new),
      positionProvider.overrideWith(_Position.new),
      durationProvider.overrideWith(_Duration.new),
      settingsProvider.overrideWith(() => _Settings(layout)),
      lyricsProvider.overrideWith(_Lyrics.new),
      artistInfoProvider.overrideWith(_Artist.new),
    ],
    child: MaterialApp(
      theme: WavvyTheme.light(appearance),
      darkTheme: WavvyTheme.dark(appearance),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: screen,
    ),
  );
}

Widget _host({VoidCallback? onArtist, VoidCallback? onLyrics}) => Scaffold(
  body: PlayerLayoutHost(
    data: PlayerLayoutData(
      song: _song(2),
      onArtist: onArtist,
      onLyrics: onLyrics,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    _Player.toggles = 0;
    _Player.nexts = 0;
    _Player.seeks.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
  });

  testWidgets('shows the song in the LCD and the shared controls work', (
    tester,
  ) async {
    var artist = 0;
    _size(tester, const Size(360, 700));
    await tester.pumpWidget(_app(_host(onArtist: () => artist++)));
    await tester.pump();

    expect(find.byType(ItunesLayout), findsOneWidget);
    expect(find.textContaining('Song 2 with'), findsOneWidget);
    expect(find.text('Artist 2 - Album 2'), findsOneWidget);
    expect(find.text('0:42'), findsOneWidget);
    expect(find.text('-2:38'), findsOneWidget);
    expect(find.byType(PlayerTransport), findsOneWidget);
    expect(find.byType(PlayerModeDock), findsOneWidget);
    expect(find.byType(PlayerExtras), findsOneWidget);
    expect(find.byTooltip('Add to Favorites'), findsOneWidget);

    await tester.tap(find.text('Artist 2 - Album 2'));
    expect(artist, 1);
    await tester.tap(find.byTooltip('Pause'));
    await tester.tap(find.byTooltip('Next'));
    expect(_Player.toggles, 1);
    expect(_Player.nexts, 1);
    expect(find.byTooltip('View lyrics'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the lyrics button shows when lyrics are on', (tester) async {
    var lyrics = 0;
    _size(tester, const Size(360, 700));
    await tester.pumpWidget(_app(_host(onLyrics: () => lyrics++)));
    await tester.pump();
    await tester.tap(find.byTooltip('View lyrics'));
    expect(lyrics, 1);
  });

  testWidgets('scrubbing seeks once, on release', (tester) async {
    _size(tester, const Size(360, 700));
    await tester.pumpWidget(_app(_host()));
    await tester.pump();
    final bar = find.byType(AquaSeekBar);
    final center = tester.getCenter(bar);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(_Player.seeks, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(_Player.seeks, hasLength(1));
  });

  group('no overflow', () {
    final sizes = {
      '320x568': const Size(320, 568),
      '360x640': const Size(360, 640),
      '360x700': const Size(360, 700),
    };
    final looks = {
      'light': (false, WvAppearance.aqua),
      'dark': (true, WvAppearance.aqua),
      'pinstripe': (false, WvAppearance.pinstripe),
      'brushed': (true, WvAppearance.brushedMetal),
      'graphite': (false, WvAppearance.graphite),
    };
    for (final size in sizes.entries) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final look in looks.entries) {
          testWidgets('${size.key} x$scale ${look.key}', (tester) async {
            _size(tester, size.value);
            await tester.pumpWidget(
              _app(
                _host(onLyrics: () {}),
                dark: look.value.$1,
                appearance: look.value.$2,
                scale: scale,
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            // Short screens scroll instead of clipping.
            expect(find.byType(SingleChildScrollView), findsOneWidget);
          });
        }
      }
    }
  });

  testWidgets('fits a typical phone without scrolling', (tester) async {
    _size(tester, const Size(360, 700));
    await tester.pumpWidget(_app(_host()));
    await tester.pump();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, 0);
    expect(find.byKey(const Key('itunes_cover')), findsOneWidget);
  });

  testWidgets('a very short screen scrolls to the dock', (tester) async {
    _size(tester, const Size(320, 480));
    await tester.pumpWidget(_app(_host(), scale: 2.0));
    await tester.pump();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byType(Scrollable), const Offset(0, -2000));
    await tester.pump();
    expect(find.byType(PlayerModeDock), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion swaps the cover without a fade', (tester) async {
    _size(tester, const Size(360, 700));
    await tester.pumpWidget(_app(_host(), reduceMotion: true));
    await tester.pump();
    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('semantics: the cover is labelled and the seek bar adjustable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    _size(tester, const Size(360, 700));
    await tester.pumpWidget(_app(_host()));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('^Cover of Song 2')), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Previous'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byType(AquaSeekBar))
          .getSemanticsData()
          .hasAction(SemanticsAction.increase),
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('the preview paints and appears in the picker', (tester) async {
    _size(tester, const Size(400, 800));
    await tester.pumpWidget(
      _app(
        const Scaffold(body: PlayerLayoutPicker()),
        layout: PlayerLayout.vinyl,
      ),
    );
    await tester.pump();
    expect(find.byType(ItunesLayoutPreview), findsOneWidget);
    expect(find.text('iTunes LCD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing the layout in the picker changes the sheet', (
    tester,
  ) async {
    _size(tester, const Size(400, 800));
    final key = GlobalKey();
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            const SizedBox(
              height: 300,
              child: Material(child: PlayerLayoutPicker()),
            ),
            Expanded(
              child: Scaffold(
                key: key,
                body: PlayerLayoutHost(data: PlayerLayoutData(song: _song(2))),
              ),
            ),
          ],
        ),
        layout: PlayerLayout.vinyl,
      ),
    );
    await tester.pump();
    expect(find.byType(ItunesLayout), findsNothing);
    await tester.tap(
      find.byType(PlayerLayoutTile).at(PlayerLayout.itunes.index),
    );
    await tester.pump();
    expect(find.byType(ItunesLayout), findsOneWidget);
  });

  testWidgets('the sheet hosts the layout', (tester) async {
    _size(tester, const Size(360, 700));
    await tester.pumpWidget(_app(const Scaffold(body: FullPlayerSheet())));
    await tester.pump();
    expect(find.byType(ItunesLayout), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
