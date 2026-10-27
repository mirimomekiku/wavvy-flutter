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
import 'package:wavvy/providers/player_sheet_provider.dart';
import 'package:wavvy/screens/home/home.screen.dart';
import 'package:wavvy/screens/library/library_tab.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
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
  PlaylistsState build() => PlaylistsState(
    playlists: [
      {'id': 1, 'name': 'Road trip'},
      {'id': 2, 'name': 'Focus'},
    ],
    mostPlayed: [for (var i = 1; i <= 6; i++) _song(i)],
    recent: [for (var i = 3; i <= 8; i++) _song(i)],
  );
}

Widget _app(Widget screen, {bool dark = false, double scale = 1.0}) {
  return ProviderScope(
    overrides: [
      libraryProvider.overrideWith(_FakeLibrary.new),
      playerProvider.overrideWith(_FakePlayer.new),
      playlistsProvider.overrideWith(_FakePlaylists.new),
      positionProvider.overrideWith(_FakePosition.new),
      durationProvider.overrideWith(_FakeDuration.new),
      settingsProvider.overrideWith(_FakeSettings.new),
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
      home: screen,
    ),
  );
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

  // The three tabs of the shell. Only the selected tab is built, so each case
  // taps its bottom-nav item first.
  final tabs = <String, String?>{
    'Home tab': null,
    'Library tab': 'Library',
    'Search tab': 'Search',
  };

  for (final entry in tabs.entries) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('${entry.key} renders (dark=$dark, text x$scale)', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(360 * 3, 740 * 3);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _app(const HomeScreen(), dark: dark, scale: scale),
          );
          await tester.pump(const Duration(milliseconds: 400));

          final navLabel = entry.value;
          if (navLabel != null) {
            await tester.tap(
              find.descendant(
                of: find.byType(BottomMiniPlayer),
                matching: find.byKey(ValueKey('nav_${navLabel.toLowerCase()}')),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
            await tester.pump(const Duration(milliseconds: 600));
          }

          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} threw while rendering',
          );
        });
      }
    }
  }

  testWidgets('opening the player sheet does not modify a provider mid-build, '
      'and resets the sheet to the player tab', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // Pretend the sheet was last left on the Lyrics tab.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    container.read(sheetPageIndexProvider.notifier).set(2);

    // Tap the mini-player card in the bottom area.
    await tester.tap(find.byKey(const Key('mini_player')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      tester.takeException(),
      isNull,
      reason: 'opening the player sheet threw',
    );
    expect(find.byType(FullPlayerSheet), findsOneWidget);
    expect(container.read(sheetPageIndexProvider), 0);
  });
  testWidgets(
    'floating trays follow reference order and open the correct tabs',
    (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 740 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const HomeScreen()));
      await tester.pump(const Duration(milliseconds: 400));
      final nowPlaying = tester.getRect(
        find.byKey(const Key('floating_now_playing')),
      );
      final navigation = tester.getRect(
        find.byKey(const Key('floating_navigation')),
      );
      expect(nowPlaying.left, greaterThan(0));
      expect(nowPlaying.right, lessThan(360));
      expect(nowPlaying.bottom, lessThan(navigation.top));
      expect(
        find.descendant(
          of: find.byKey(const Key('floating_navigation')),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      expect(
        tester.getCenter(find.byKey(const Key('nav_home'))).dx,
        lessThan(tester.getCenter(find.byKey(const Key('nav_search'))).dx),
      );
      expect(
        tester.getCenter(find.byKey(const Key('nav_search'))).dx,
        lessThan(tester.getCenter(find.byKey(const Key('nav_library'))).dx),
      );
      await tester.tap(find.byKey(const Key('nav_search')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        DefaultTabController.of(tester.element(find.byType(TabBarView))).index,
        2,
      );
      await tester.tap(find.byKey(const Key('nav_library')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        DefaultTabController.of(tester.element(find.byType(TabBarView))).index,
        1,
      );
      await tester.scrollUntilVisible(
        find.text('Song 25'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(LibraryTab),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      expect(
        tester.getRect(find.text('Song 25')).bottom,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('floating_now_playing'))).dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
