import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/player_sheets/player_dialogs.dart';
import 'package:wavvy/playback/ab_loop.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/library/liked/liked.screen.dart';
import 'package:wavvy/screens/settings/settings.screen.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/audio_dialogs.dart';
import 'package:wavvy/widgets/song_menu.dart';

import 'helpers/fake_engine.dart';
import 'helpers/fake_player.dart';

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

class _Position extends PositionNotifier {
  @override
  Duration build() => const Duration(seconds: 50);
  void to(Duration d) => state = d;
}

class _Duration extends DurationNotifier {
  @override
  Duration build() => const Duration(minutes: 3);
}

class _FavStore implements FavoritesStore {
  final Map<int, int> rows;
  _FavStore([Map<int, int>? initial]) : rows = {...?initial};
  @override
  Future<Map<int, int>> load() async => {...rows};
  @override
  Future<void> add(int id, int at) async => rows[id] = at;
  @override
  Future<void> remove(int id) async => rows.remove(id);
}

class _Rates implements RateStore {
  final saved = <String, PlaybackRate>{};
  @override
  Future<Map<String, PlaybackRate>> load() async => {...saved};
  @override
  Future<void> save(Map<String, PlaybackRate> r) async {
    saved
      ..clear()
      ..addAll(r);
  }
}

final _songs = [for (var i = 1; i <= 4; i++) testSong(i, albumId: 100)];

class _Rig {
  _Rig({Map<int, int>? favorites, SettingsState? settings})
    : player = MemoryPlayer(),
      favorites = _FavStore(favorites),
      rates = _Rates(),
      initialSettings = settings ?? const SettingsState();

  final MemoryPlayer player;
  final _FavStore favorites;
  final _Rates rates;
  final SettingsState initialSettings;

  List<Override> get overrides => [
    audioPlayerProvider.overrideWithValue(player),
    libraryProvider.overrideWith(() => _Library(_songs)),
    playlistsProvider.overrideWith(_Playlists.new),
    positionProvider.overrideWith(_Position.new),
    durationProvider.overrideWith(_Duration.new),
    favoritesStoreProvider.overrideWithValue(favorites),
    rateStoreProvider.overrideWithValue(rates),
    settingsProvider.overrideWith(() => _SettingsFake(initialSettings)),
    ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
    downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
  ];

  Widget app(Widget home, {double scale = 1, bool dark = false}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: WavvyTheme.light(WvAppearance.aqua),
          darkTheme: WavvyTheme.dark(WvAppearance.aqua),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: c!,
          ),
          home: home,
        ),
      );
}

class _SettingsFake extends SettingsNotifier {
  _SettingsFake(this.initial);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
  });

  void phone(WidgetTester tester, {double w = 411, double h = 900}) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  ProviderContainer containerOf(WidgetTester tester, Type type) =>
      ProviderScope.containerOf(tester.element(find.byType(type).first));

  group('Now Playing extras', () {
    Future<ProviderContainer> open(
      WidgetTester tester,
      _Rig rig, {
      double scale = 1,
    }) async {
      phone(tester);
      await tester.pumpWidget(rig.app(const FullPlayerSheet(), scale: scale));
      final c = containerOf(tester, FullPlayerSheet);
      await c
          .read(playerProvider.notifier)
          .playSong(_songs[1], contextList: _songs);
      await tester.pump();
      await tester.pump();
      return c;
    }

    testWidgets('the heart adds and removes a favorite', (tester) async {
      final rig = _Rig();
      final c = await open(tester, rig);
      expect(find.byTooltip('Add to Favorites'), findsOneWidget);
      await tester.tap(find.byTooltip('Add to Favorites'));
      await tester.pump();
      expect(c.read(favoritesProvider).containsKey(2), isTrue);
      expect(rig.favorites.rows.keys, [2]);
      expect(find.byTooltip('Remove from Favorites'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove from Favorites'));
      await tester.pump();
      expect(c.read(favoritesProvider).containsKey(2), isFalse);
    });

    testWidgets('back and forward 15 seconds seek relative to now', (
      tester,
    ) async {
      final rig = _Rig();
      await open(tester, rig);
      await tester.tap(find.byTooltip('Forward 15 seconds'));
      await tester.pump();
      await tester.tap(find.byTooltip('Back 15 seconds'));
      await tester.pump();
      // The position is 50 s: 65 s forward, 35 s back.
      expect(rig.player.seeks, [
        const Duration(seconds: 65),
        const Duration(seconds: 35),
      ]);
    });

    testWidgets('the A-B button marks A, then B, then clears', (tester) async {
      final rig = _Rig();
      final c = await open(tester, rig);
      expect(find.text('A–B'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ab_loop')));
      await tester.pump();
      expect(c.read(abLoopProvider).start, const Duration(seconds: 50));
      expect(find.text('Set B'), findsOneWidget);

      // Move on 20 s, mark B.
      (c.read(positionProvider.notifier) as _Position).to(
        const Duration(seconds: 70),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('ab_loop')));
      await tester.pump();
      expect(c.read(abLoopProvider).isActive, isTrue);
      expect(find.text('A–B on'), findsOneWidget);
      expect(find.byTooltip('Clear the repeated section'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ab_loop')));
      await tester.pump();
      expect(c.read(abLoopProvider).isEmpty, isTrue);
    });

    for (final scale in [1.0, 1.5]) {
      testWidgets('fits a small phone at $scale x text', (tester) async {
        final rig = _Rig();
        phone(tester, w: 320, h: 640);
        await tester.pumpWidget(rig.app(const FullPlayerSheet(), scale: scale));
        final c = containerOf(tester, FullPlayerSheet);
        await c
            .read(playerProvider.notifier)
            .playSong(_songs[0], contextList: _songs);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('sleep timer dialog', () {
    testWidgets('offers end of track and end of queue', (tester) async {
      final rig = _Rig();
      phone(tester);
      await tester.pumpWidget(
        rig.app(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => openSleepTimerDialog(ref),
              child: const Text('open'),
            ),
          ),
        ),
      );
      final c = containerOf(tester, TextButton);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Music plays until you stop it'), findsOneWidget);
      expect(find.text('End of this track'), findsOneWidget);
      expect(find.text('End of the queue'), findsOneWidget);

      await tester.tap(find.text('End of this track'));
      await tester.pumpAndSettle();
      expect(c.read(playerProvider).sleepMode, SleepMode.endOfTrack);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Music stops after this track'), findsOneWidget);
      await tester.tap(find.text('End of the queue'));
      await tester.pumpAndSettle();
      expect(c.read(playerProvider).sleepMode, SleepMode.endOfQueue);
    });

    testWidgets('a minutes timer shows when it ends', (tester) async {
      final rig = _Rig();
      phone(tester);
      await tester.pumpWidget(
        rig.app(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => openSleepTimerDialog(ref),
              child: const Text('open'),
            ),
          ),
        ),
      );
      final c = containerOf(tester, TextButton);
      c.read(playerProvider.notifier).setSleepTimer(45);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Music stops at'), findsOneWidget);
      // Cancel it so no timer outlives the test.
      c.read(playerProvider.notifier).setSleepTimer(null);
      await tester.pump();
    });
  });

  group('speed dialog remembers for the album', () {
    testWidgets('a speed change is saved for the playing song\'s album', (
      tester,
    ) async {
      final rig = _Rig();
      phone(tester);
      await tester.pumpWidget(
        rig.app(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showSpeedDialog(ref),
              child: const Text('open'),
            ),
          ),
        ),
      );
      final c = containerOf(tester, TextButton);
      await c
          .read(playerProvider.notifier)
          .playSong(_songs[0], contextList: _songs);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Tap the far end of the speed slider: 2x.
      final slider = find.byType(AquaSlider).first;
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.right - 4, rect.center.dy));
      await tester.pumpAndSettle();
      expect(rig.player.speedValue, 2.0);
      expect(rig.rates.saved['a:100']!.speed, 2.0);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(rig.player.speedValue, 1.0);
      expect(rig.rates.saved, isEmpty); // normal speed is not stored
    });

    testWidgets('with the setting off, nothing is stored', (tester) async {
      final rig = _Rig(settings: const SettingsState(rememberRates: false));
      phone(tester);
      await tester.pumpWidget(
        rig.app(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showSpeedDialog(ref),
              child: const Text('open'),
            ),
          ),
        ),
      );
      final c = containerOf(tester, TextButton);
      await c
          .read(playerProvider.notifier)
          .playSong(_songs[0], contextList: _songs);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(AquaSlider).first);
      await tester.tapAt(Offset(rect.right - 4, rect.center.dy));
      await tester.pumpAndSettle();
      expect(rig.player.speedValue, 2.0);
      expect(rig.rates.saved, isEmpty);
    });
  });

  group('favorites in the app', () {
    testWidgets('Liked songs lists them newest first and can remove one', (
      tester,
    ) async {
      final rig = _Rig(favorites: {1: 100, 3: 300, 2: 200});
      phone(tester);
      await tester.pumpWidget(rig.app(const LikedSongsScreen()));
      await tester.pump();
      await tester.pump();
      expect(find.text('Liked songs'), findsWidgets);
      expect(find.text('3 Songs'), findsOneWidget);
      final order = [
        for (final t in ['Track 3', 'Track 2', 'Track 1'])
          tester.getTopLeft(find.text(t)).dy,
      ];
      expect(order, orderedEquals([...order]..sort()));

      await tester.tap(find.byTooltip('Remove from Favorites').first);
      await tester.pump();
      expect(find.text('Track 3'), findsNothing);
      expect(rig.favorites.rows.keys, isNot(contains(3)));
    });

    testWidgets('with none, it explains how to add one', (tester) async {
      final rig = _Rig();
      phone(tester);
      await tester.pumpWidget(rig.app(const LikedSongsScreen()));
      await tester.pump();
      expect(
        find.text('Tap the heart on a song to keep it here'),
        findsOneWidget,
      );
    });

    testWidgets('the song menu has an Add / Remove favorites row', (
      tester,
    ) async {
      final rig = _Rig(favorites: {2: 5});
      phone(tester);
      await tester.pumpWidget(
        rig.app(
          Consumer(
            builder: (context, ref, _) => Column(
              children: [
                TextButton(
                  onPressed: () => SongMenuHelper.show(context, ref, _songs[0]),
                  child: const Text('first'),
                ),
                TextButton(
                  onPressed: () => SongMenuHelper.show(context, ref, _songs[1]),
                  child: const Text('second'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('first'));
      await tester.pumpAndSettle();
      expect(find.text('Add to Favorites'), findsOneWidget);
      await tester.tap(find.text('Add to Favorites'));
      await tester.pumpAndSettle();
      final c = containerOf(tester, Column);
      expect(c.read(favoritesProvider).containsKey(1), isTrue);

      await tester.tap(find.text('second'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from Favorites'), findsOneWidget);
    });
  });

  group('Settings', () {
    Future<void> openSettings(WidgetTester tester, _Rig rig) async {
      // Tall enough that the whole list is built.
      phone(tester, w: 411, h: 4200);
      await tester.pumpWidget(rig.app(const SettingsScreen()));
      await tester.pump();
    }

    testWidgets('has the new playback options', (tester) async {
      final rig = _Rig();
      await openSettings(tester, rig);
      for (final label in [
        'Resume last session',
        'Remember speed',
        'Volume leveling',
        'Crossfade',
        'Pause when unplugged',
        'Lower volume for notifications',
        'Resume after interruptions',
        'Resume when plugged back in',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('choosing crossfade and leveling changes the settings', (
      tester,
    ) async {
      final rig = _Rig();
      await openSettings(tester, rig);
      final c = containerOf(tester, SettingsScreen);
      expect(c.read(settingsProvider).crossfadeSeconds, 0);

      await tester.tap(find.byTooltip('Crossfade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6 s'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).crossfadeSeconds, 6);

      await tester.tap(find.byTooltip('Volume leveling'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).replayGainMode, 2);
    });

    testWidgets('the toggles flip their settings', (tester) async {
      final rig = _Rig();
      await openSettings(tester, rig);
      final c = containerOf(tester, SettingsScreen);
      expect(c.read(settingsProvider).resumeOnReconnect, isFalse);
      await tester.tap(find.text('Resume when plugged back in'));
      await tester.pump();
      expect(c.read(settingsProvider).resumeOnReconnect, isTrue);
      expect(c.read(settingsProvider).pauseOnUnplug, isTrue);
      await tester.tap(find.text('Pause when unplugged'));
      await tester.pump();
      expect(c.read(settingsProvider).pauseOnUnplug, isFalse);
    });
  });

  testWidgets('the seek bar draws an A-B loop without trouble', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WavvyTheme.light(WvAppearance.aqua),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: AquaSeekBar(
                value: 500,
                max: 1000,
                loopStart: 200,
                loopEnd: 700,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // A start with no end, and a loop beyond the range, also draw.
    for (final (s, e) in [(200.0, null), (900.0, 5000.0), (null, null)]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: WavvyTheme.dark(WvAppearance.teal),
          home: Scaffold(
            body: AquaSeekBar(
              value: 10,
              max: 1000,
              loopStart: s,
              loopEnd: e,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
