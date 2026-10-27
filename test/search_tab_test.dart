import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/search/search_tab.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

SongModel _song(int id, String title, String artist, String album) =>
    SongModel({
      '_id': id,
      '_data': '/music/$title.mp3',
      '_uri': 'content://media/$id',
      '_display_name': '$title.mp3',
      '_display_name_wo_ext': title,
      '_size': 1024,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': 180000,
      'is_music': true,
    });

final _songs = [
  _song(1, 'Blue Monday', 'New Order', 'Power'),
  _song(2, 'Sunrise', 'Norah Jones', 'Come Away'),
  _song(3, 'Other', 'Zed', 'Misc'),
];
final _albums = [
  AlbumModel({
    '_id': 1,
    'album': 'Power Corruption',
    'artist': 'New Order',
    'numsongs': 5,
  }),
  AlbumModel({'_id': 2, 'album': 'Misc', 'artist': 'Zed', 'numsongs': 2}),
];
final _artists = [
  ArtistModel({
    '_id': 1,
    'artist': 'New Order',
    'number_of_albums': 1,
    'number_of_tracks': 3,
  }),
  ArtistModel({
    '_id': 2,
    'artist': 'Zed',
    'number_of_albums': 1,
    'number_of_tracks': 1,
  }),
];

class _FakeLibrary extends LibraryNotifier {
  @override
  LibraryState build() => LibraryState(
    songs: _songs,
    filteredSongs: _songs,
    albums: _albums,
    artists: _artists,
  );
}

class _FakePlayer extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}

class _FakeSettings extends SettingsNotifier {
  final bool downloader;
  _FakeSettings(this.downloader);

  @override
  SettingsState build() => SettingsState(enableDownloader: downloader);
}

class _FakeYt extends YtdlpNotifier {
  final List<String> queries = [];

  @override
  YtdlpState build() => const YtdlpState(
    taskTitles: {'y1': 'YT song'},
    progressMap: {'y1': 40},
    statusMap: {'y1': DownloadTaskStatus.running},
  );

  @override
  Future<void> search(String query) async => queries.add(query);
}

class _FakeTt extends TikTokNotifier {
  final List<String> fetched = [];

  @override
  TikTokState build() => const TikTokState(
    taskTitles: {'t1': 'tiktok_clip'},
    progressMap: {'t1': 100},
    statusMap: {'t1': DownloadTaskStatus.complete},
  );

  @override
  Future<void> fetchVideoInfo(String url) async => fetched.add(url);
}

Widget _app({
  bool downloader = true,
  bool dark = false,
  double scale = 1.0,
  _FakeYt? yt,
  _FakeTt? tt,
}) {
  return ProviderScope(
    overrides: [
      libraryProvider.overrideWith(_FakeLibrary.new),
      playerProvider.overrideWith(_FakePlayer.new),
      settingsProvider.overrideWith(() => _FakeSettings(downloader)),
      ytdlpProvider.overrideWith(() => yt ?? _FakeYt()),
      tiktokProvider.overrideWith(() => tt ?? _FakeTt()),
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
      home: const Scaffold(body: SafeArea(child: SearchTab())),
    ),
  );
}

void _size(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _tapChip(WidgetTester tester, String label) async {
  // The chip row scrolls horizontally on narrow phones.
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
}

void main() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
  });

  testWidgets('typing filters into Songs/Albums/Artists, no provider writes', (
    tester,
  ) async {
    _size(tester, 411, 732);
    await tester.pumpWidget(_app());
    expect(find.text('Search your library'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'new order');
    await tester.pump();

    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Blue Monday'), findsOneWidget);
    expect(find.text('Sunrise'), findsNothing);
    expect(find.text('Power Corruption'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchTab)),
    );
    expect(container.read(libraryProvider).filteredSongs.length, 3);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chips switch the body and hint; submit calls the providers', (
    tester,
  ) async {
    _size(tester, 411, 732);
    final yt = _FakeYt();
    final tt = _FakeTt();
    await tester.pumpWidget(_app(yt: yt, tt: tt));

    expect(find.text('Songs, albums, artists'), findsOneWidget);

    await tester.tap(find.text('YOUTUBE'));
    await tester.pump();
    expect(find.text('Search YouTube'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(yt.queries, ['lofi']);

    await tester.tap(find.text('TIKTOK'));
    await tester.pump();
    expect(find.text('Paste a TikTok link'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'https://vm.tiktok.com/x');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(tt.fetched, ['https://vm.tiktok.com/x']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear button and switching source empty the field', (
    tester,
  ) async {
    _size(tester, 411, 732);
    await tester.pumpWidget(_app());
    await tester.enterText(find.byType(TextField), 'new order');
    await tester.pump();
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(find.text('Search your library'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.tap(find.text('YOUTUBE'));
    await tester.pump();
    expect(find.byTooltip('Clear'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('downloader disabled: only Library, no chips', (tester) async {
    _size(tester, 411, 732);
    await tester.pumpWidget(_app(downloader: false));
    expect(find.byType(WvChips), findsNothing);
    expect(find.text('YOUTUBE'), findsNothing);
    expect(find.text('Songs, albums, artists'), findsOneWidget);
  });

  testWidgets('Downloads shows tasks of both providers', (tester) async {
    _size(tester, 411, 732);
    await tester.pumpWidget(_app());
    await _tapChip(tester, 'DOWNLOADS');
    expect(find.text('YT song'), findsOneWidget);
    expect(find.text('tiktok_clip'), findsOneWidget);
    expect(find.text('40% · Downloading'), findsOneWidget);
    expect(find.text('100% · Done'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('Downloads filters titles and explains no matches', (
    tester,
  ) async {
    _size(tester, 360, 740);
    await tester.pumpWidget(_app());
    await _tapChip(tester, 'DOWNLOADS');
    await tester.enterText(find.byType(TextField), 'YT');
    await tester.pump();
    expect(find.text('YT song'), findsOneWidget);
    expect(find.text('tiktok_clip'), findsNothing);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('No matching downloads'), findsOneWidget);
  });

  testWidgets('source switches restore each search draft', (tester) async {
    _size(tester, 360, 740);
    await tester.pumpWidget(_app());
    await tester.enterText(find.byType(TextField), 'new order');
    await _tapChip(tester, 'YOUTUBE');
    await tester.enterText(find.byType(TextField), 'instrumentals');
    await _tapChip(tester, 'LIBRARY');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'new order',
    );
    await _tapChip(tester, 'YOUTUBE');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'instrumentals',
    );
  });
  testWidgets('download status views separate active and completed files', (
    tester,
  ) async {
    _size(tester, 360, 740);
    await tester.pumpWidget(_app());
    await _tapChip(tester, 'DOWNLOADS');
    await tester.tap(find.text('Active'));
    await tester.pump();
    expect(find.text('YT song'), findsOneWidget);
    expect(find.text('tiktok_clip'), findsNothing);
    await tester.tap(find.text('Completed'));
    await tester.pump();
    expect(find.text('YT song'), findsNothing);
    expect(find.text('tiktok_clip'), findsOneWidget);
  });

  for (final size in const [Size(411, 732), Size(360, 740)]) {
    for (final scale in const [1.0, 1.5]) {
      for (final dark in const [false, true]) {
        testWidgets(
          'renders every source at ${size.width.toInt()}x${size.height.toInt()} '
          'x$scale ${dark ? 'dark' : 'light'}',
          (tester) async {
            _size(tester, size.width, size.height);
            await tester.pumpWidget(_app(dark: dark, scale: scale));
            await tester.enterText(find.byType(TextField), 'e');
            await tester.pump();
            expect(tester.takeException(), isNull);

            for (final chip in ['YOUTUBE', 'TIKTOK', 'DOWNLOADS', 'LIBRARY']) {
              await _tapChip(tester, chip);
              expect(tester.takeException(), isNull, reason: chip);
            }
          },
        );
      }
    }
  }
}
