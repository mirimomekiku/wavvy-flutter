import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/downloader/models.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/search/search_tab.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

import 'helpers/fake_engine.dart';

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

Widget _app({
  bool downloader = true,
  bool dark = false,
  double scale = 1.0,
  FakeYtDlpEngine? engine,
  FakeDownloadStore? store,
}) {
  return ProviderScope(
    overrides: [
      libraryProvider.overrideWith(_FakeLibrary.new),
      playerProvider.overrideWith(_FakePlayer.new),
      settingsProvider.overrideWith(() => _FakeSettings(downloader)),
      ytDlpEngineProvider.overrideWithValue(engine ?? FakeYtDlpEngine()),
      downloadStoreProvider.overrideWithValue(store ?? FakeDownloadStore()),
      downloadDirectoryProvider.overrideWithValue(() async => '/tmp/dl'),
      tagWriterProvider.overrideWithValue((path, task) async {}),
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
      home: const Scaffold(body: SafeArea(child: SearchTab())),
    ),
  );
}

void _size(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Source chips show icons only; each is found by its tooltip.
Future<void> _tapChip(WidgetTester tester, String label) async {
  final chip = find.byTooltip(label);
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await tester.pump();
}

/// Opens the Downloads sheet from the heading icon.
Future<void> _openDownloads(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Downloads'));
  await tester.pumpAndSettle();
}

/// The search field inside the Downloads sheet.
Finder get _sheetField => find.descendant(
  of: find.byType(AquaSheet),
  matching: find.byType(TextField),
);

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

  testWidgets('the Online chip switches the hint and searches on submit', (
    tester,
  ) async {
    _size(tester, 411, 732);
    final engine = FakeYtDlpEngine()
      ..searchResults = [fakeMedia('a', title: 'Alright')];
    await tester.pumpWidget(_app(engine: engine));
    await tester.pump();

    expect(find.text('Songs, albums, artists'), findsOneWidget);
    await _tapChip(tester, 'Online');
    await tester.pumpAndSettle();
    expect(find.text('Search online or paste a link'), findsOneWidget);
    expect(find.text('Search for music, or paste a link'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'kendrick');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(engine.searches, ['kendrick']);
    expect(find.text('Alright'), findsOneWidget);

    // Library search never goes online.
    await _tapChip(tester, 'Library');
    await tester.enterText(find.byType(TextField), 'sunrise');
    await tester.pump();
    expect(engine.searches, ['kendrick']);
  });

  testWidgets('a pasted link is resolved, not searched', (tester) async {
    _size(tester, 411, 732);
    final engine = FakeYtDlpEngine()
      ..resolved = fakeMedia('xyz', title: 'From a link');
    await tester.pumpWidget(_app(engine: engine));
    await tester.pump();
    await _tapChip(tester, 'Online');
    await tester.enterText(
      find.byType(TextField),
      'https://www.youtube.com/watch?v=xyz',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(engine.resolves, ['https://www.youtube.com/watch?v=xyz']);
    expect(engine.searches, isEmpty);
    expect(find.text('From a link'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
  });

  testWidgets('a failed lookup explains itself and can be retried', (
    tester,
  ) async {
    _size(tester, 411, 732);
    final engine = FakeYtDlpEngine()
      ..lookupError = const DownloaderException('Could not reach the server.');
    await tester.pumpWidget(_app(engine: engine));
    await tester.pump();
    await _tapChip(tester, 'Online');
    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Could not reach the server.'), findsOneWidget);

    engine
      ..lookupError = null
      ..searchResults = [fakeMedia('a', title: 'Back online')];
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Back online'), findsOneWidget);
  });

  testWidgets('until the engine is set up, Online offers to set it up', (
    tester,
  ) async {
    _size(tester, 411, 732);
    final engine = FakeYtDlpEngine()
      ..current = const EngineStatus(EngineState.missing);
    await tester.pumpWidget(_app(engine: engine));
    await tester.pump();
    await _tapChip(tester, 'Online');
    await tester.pumpAndSettle();
    expect(find.text('Set up the downloader'), findsOneWidget);
    expect(find.text('Search for music, or paste a link'), findsNothing);

    await tester.tap(find.byKey(const Key('engine_setup')));
    await tester.pumpAndSettle();
    expect(engine.installs, hasLength(1));
    expect(find.text('Search for music, or paste a link'), findsOneWidget);
    expect(find.text('Set up the downloader'), findsNothing);
  });

  testWidgets('a failed setup shows why and can be retried', (tester) async {
    _size(tester, 411, 732);
    final engine = FakeYtDlpEngine()
      ..current = const EngineStatus(EngineState.missing)
      ..installError = const DownloaderException('No connection.');
    await tester.pumpWidget(_app(engine: engine));
    await tester.pump();
    await _tapChip(tester, 'Online');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('engine_setup')));
    await tester.pumpAndSettle();
    expect(find.text('The downloader could not be set up'), findsOneWidget);
    expect(find.text('No connection.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a result\'s download button queues it', (tester) async {
    _size(tester, 411, 732);
    final engine = FakeYtDlpEngine()
      ..searchResults = [fakeMedia('a', title: 'Alright')];
    final store = FakeDownloadStore();
    await tester.pumpWidget(_app(engine: engine, store: store));
    await tester.pump();
    await _tapChip(tester, 'Online');
    await tester.enterText(find.byType(TextField), 'alright');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Download'));
    // The progress ring spins forever, so settle by pumping a few frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.started, hasLength(1));
    expect(engine.started.single.videoId, 'a');
    expect(engine.started.single.dir, '/tmp/dl');
    expect(store.tasks.values.single.title, 'Alright');
    // The button now shows progress and can cancel.
    expect(find.byTooltip('Downloading, tap to cancel'), findsOneWidget);
  });

  testWidgets('downloader disabled: only Library, no chips, no downloads', (
    tester,
  ) async {
    _size(tester, 411, 732);
    await tester.pumpWidget(_app(downloader: false));
    expect(find.byType(WvChips), findsNothing);
    expect(find.byTooltip('Online'), findsNothing);
    expect(find.byTooltip('Downloads'), findsNothing);
    expect(find.text('Songs, albums, artists'), findsOneWidget);
  });

  testWidgets('the Downloads sheet lists tasks with the right actions', (
    tester,
  ) async {
    _size(tester, 411, 732);
    final store = FakeDownloadStore([
      fakeTask(
        '1',
        title: 'Running one',
        status: DownloadStatus.running,
        progress: 40,
      ),
      fakeTask(
        '2',
        title: 'Done one',
        status: DownloadStatus.complete,
        mediaUri: 'content://media/external_primary/audio/media/7',
      ),
      fakeTask(
        '3',
        title: 'Broken one',
        status: DownloadStatus.failed,
        error: 'Could not reach the server.',
      ),
    ]);
    await tester.pumpWidget(
      _app(
        store: store,
        engine: FakeYtDlpEngine()
          ..pendingWork = const PendingWork(activeIds: {'1'}),
      ),
    );
    await tester.pump();
    await _openDownloads(tester);

    expect(find.text('Running one'), findsOneWidget);
    expect(find.text('40% \u00b7 Downloading'), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsOneWidget);
    expect(find.text('In your library'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.byTooltip('Try again'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('Downloads filters by search and by status', (tester) async {
    _size(tester, 360, 740);
    final store = FakeDownloadStore([
      fakeTask(
        '1',
        title: 'Running one',
        status: DownloadStatus.running,
        progress: 10,
      ),
      fakeTask('2', title: 'Done one', status: DownloadStatus.complete),
      fakeTask('3', title: 'Broken one', status: DownloadStatus.failed),
    ]);
    await tester.pumpWidget(
      _app(
        store: store,
        engine: FakeYtDlpEngine()
          ..pendingWork = const PendingWork(activeIds: {'1'}),
      ),
    );
    await tester.pump();
    await _openDownloads(tester);

    await tester.enterText(_sheetField, 'Done');
    await tester.pump();
    expect(find.text('Done one'), findsOneWidget);
    expect(find.text('Running one'), findsNothing);
    await tester.enterText(_sheetField, 'missing');
    await tester.pump();
    expect(find.text('No matching downloads'), findsOneWidget);
    await tester.enterText(_sheetField, '');
    await tester.pump();

    await tester.ensureVisible(find.text('Active'));
    await tester.pump();
    await tester.tap(find.text('Active'));
    await tester.pump();
    expect(find.text('Running one'), findsOneWidget);
    expect(find.text('Done one'), findsNothing);
    await tester.ensureVisible(find.text('Completed'));
    await tester.pump();
    await tester.tap(find.text('Completed'));
    await tester.pump();
    expect(find.text('Done one'), findsOneWidget);
    await tester.ensureVisible(find.text('Failed'));
    await tester.pump();
    await tester.tap(find.text('Failed'));
    await tester.pump();
    expect(find.text('Broken one'), findsOneWidget);
    expect(find.text('Done one'), findsNothing);
  });

  testWidgets('source switches restore each search draft', (tester) async {
    _size(tester, 360, 740);
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new order');
    await _tapChip(tester, 'Online');
    await tester.enterText(find.byType(TextField), 'instrumentals');
    await _tapChip(tester, 'Library');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'new order',
    );
    await _tapChip(tester, 'Online');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'instrumentals',
    );
  });

  for (final size in const [Size(411, 732), Size(360, 740)]) {
    for (final scale in const [1.0, 1.5]) {
      for (final dark in const [false, true]) {
        testWidgets(
          'renders both sources at ${size.width.toInt()}x${size.height.toInt()} '
          'x$scale ${dark ? 'dark' : 'light'}',
          (tester) async {
            _size(tester, size.width, size.height);
            final engine = FakeYtDlpEngine()
              ..searchResults = [
                fakeMedia(
                  'a',
                  title:
                      'A very long title that has to wrap across several lines on a narrow phone',
                ),
              ];
            await tester.pumpWidget(
              _app(dark: dark, scale: scale, engine: engine),
            );
            await tester.pump();
            await tester.enterText(find.byType(TextField), 'e');
            await tester.pump();
            expect(tester.takeException(), isNull);

            await _tapChip(tester, 'Online');
            await tester.enterText(find.byType(TextField), 'e');
            await tester.testTextInput.receiveAction(TextInputAction.search);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'online');

            await _tapChip(tester, 'Library');
            await _openDownloads(tester);
            expect(tester.takeException(), isNull, reason: 'downloads');
          },
        );
      }
    }
  }
}
