import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/playlist_dialogs.dart';
import 'package:wavvy/widgets/song_menu.dart';

class _Playlists extends PlaylistsNotifier {
  _Playlists(this.initial);
  final List<Map<String, dynamic>> initial;
  @override
  PlaylistsState build() => PlaylistsState(playlists: initial);
}

final _song = SongModel({
  '_id': 1,
  '_data': '/music/1.mp3',
  '_uri': 'content://media/1',
  'title': 'A Very Long Song Title That Has To Wrap Across Lines',
  'artist': 'Some Artist',
});

Widget _host({
  required void Function(BuildContext, WidgetRef) onOpen,
  List<Map<String, dynamic>> playlists = const [],
  bool dark = false,
  double scale = 1,
}) {
  return ProviderScope(
    overrides: [playlistsProvider.overrideWith(() => _Playlists(playlists))],
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
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Center(
            child: TextButton(
              onPressed: () => onOpen(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
  });

  void small(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('song menu sheet', () {
    for (final dark in [false, true]) {
      testWidgets('lists grouped actions at 320 wide, 1.5x (dark: $dark)', (
        tester,
      ) async {
        small(tester);
        await tester.pumpWidget(
          _host(
            dark: dark,
            scale: 1.5,
            onOpen: (context, ref) => SongMenuHelper.show(
              context,
              ref,
              _song,
              options: const SongMenuOptions(
                showDelete: true,
                showSongInfo: true,
                showPlaybackSpeed: true,
                showCustomEqualizer: true,
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(AquaSheet), findsOneWidget);
        expect(find.byType(AquaMenuGroup), findsWidgets);
        expect(find.text('Play Next'), findsOneWidget);
        expect(find.text('Add to Playlist'), findsOneWidget);
        // The menu is taller than the screen, so the rest scrolls into view.
        await tester.scrollUntilVisible(
          find.text('Delete'),
          100,
          scrollable: find.descendant(
            of: find.byType(AquaSheet),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('Speed & pitch'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the close light dismisses the sheet', (tester) async {
      await tester.pumpWidget(
        _host(onOpen: (c, r) => SongMenuHelper.show(c, r, _song)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AquaSheet), findsNothing);
    });

    testWidgets('options that are switched off are not shown', (tester) async {
      await tester.pumpWidget(
        _host(
          onOpen: (c, r) => SongMenuHelper.show(
            c,
            r,
            _song,
            options: const SongMenuOptions(
              showPlayNext: false,
              showFavorite: false,
              showAddToQueue: false,
              showAddToPlaylist: false,
              showGoToArtist: false,
              showGoToAlbum: false,
              showSleepTimer: false,
              showEditTags: false,
              showShare: false,
              showShareCard: false,
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(AquaMenuGroup), findsNothing);
      expect(find.byType(AquaMenuRow), findsNothing);
    });
  });

  group('add to playlist sheet', () {
    testWidgets('lists playlists and offers a new one', (tester) async {
      small(tester);
      await tester.pumpWidget(
        _host(
          playlists: [
            {'id': 1, 'name': 'Road trip'},
            {'id': 2, 'name': 'Focus'},
          ],
          scale: 1.5,
          onOpen: (c, r) => showAddToPlaylistSheet(c, r, _song),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Add to Playlist'), findsOneWidget);
      expect(find.text('Road trip'), findsOneWidget);
      expect(find.text('Focus'), findsOneWidget);
      expect(find.text('New Playlist…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty library of playlists explains itself', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(onOpen: (c, r) => showAddToPlaylistSheet(c, r, _song)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('No playlists yet'), findsOneWidget);
      expect(find.text('New Playlist…'), findsOneWidget);
    });
  });

  group('menu row', () {
    testWidgets('runs its action when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: WavvyTheme.light(WvAppearance.aqua),
          home: Scaffold(
            body: AquaMenuGroup(
              rows: [
                AquaMenuRow(
                  icon: Icons.add_rounded,
                  label: 'Do it',
                  onTap: () => taps++,
                ),
                AquaMenuRow(
                  icon: Icons.delete_rounded,
                  label: 'Remove',
                  destructive: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Do it'));
      expect(taps, 1);
    });
  });

  group('window', () {
    testWidgets('title bar holds the title and the action', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: WavvyTheme.light(WvAppearance.aqua),
          home: Scaffold(
            body: AquaWindow(
              title: 'Things',
              subtitle: 'Some of them',
              action: 'More',
              onAction: () => pressed = true,
              child: const SizedBox(height: 40),
            ),
          ),
        ),
      );
      await tester.tap(find.text('More'));
      expect(pressed, isTrue);
      expect(find.text('Things'), findsOneWidget);
      expect(find.text('Some of them'), findsOneWidget);
    });
  });
}
