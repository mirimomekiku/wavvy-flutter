import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:on_audio_query/on_audio_query.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_backdrop.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/player_sheets/layouts/poster_layout.dart';
import 'package:wavvy/providers/palette_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/settings/player_layout_setting.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

import 'helpers/fake_player.dart';

class _Player extends PlayerNotifier {
  _Player(this.songs);
  final List<SongModel> songs;
  final calls = <String>[];
  final seeks = <Duration>[];

  @override
  PlayerState build() => PlayerState(
    queue: songs,
    currentSong: songs[0],
    currentIndex: 0,
    isPlaying: false,
  );

  void go(int index) =>
      state = state.copyWith(currentSong: songs[index], currentIndex: index);

  @override
  void togglePlay() {
    calls.add('toggle');
    state = state.copyWith(isPlaying: !state.isPlaying);
  }

  @override
  void next() {
    calls.add('next');
    go(state.currentIndex + 1);
  }

  @override
  void previous() {
    calls.add('previous');
    go(state.currentIndex - 1);
  }

  @override
  Future<void> seek(Duration position, {bool relative = false}) async =>
      seeks.add(position);

  @override
  Future<void> toggleShuffle() async {
    calls.add('shuffle');
    state = state.copyWith(isShuffleModeEnabled: !state.isShuffleModeEnabled);
  }

  @override
  Future<void> cycleLoopMode() async {
    calls.add('repeat');
    state = state.copyWith(loopMode: LoopMode.all);
  }
}

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
}

class _Position extends PositionNotifier {
  @override
  Duration build() => const Duration(seconds: 50);
}

class _Duration extends DurationNotifier {
  @override
  Duration build() => const Duration(minutes: 3);
}

class _Palette extends PaletteNotifier {
  _Palette(this.color);
  final Color? color;
  @override
  PaletteState build() => PaletteState(playerColor: color);
}

class _FavStore implements FavoritesStore {
  @override
  Future<Map<int, int>> load() async => {};
  @override
  Future<void> add(int id, int at) async {}
  @override
  Future<void> remove(int id) async {}
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final songs = [for (var i = 1; i <= 3; i++) testSong(i, albumId: 100)];
  late List<String> opened;
  late _Player player;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
    opened = [];
  });

  /// Pumps the layout the way the sheet does: through the host, with Poster
  /// chosen in Settings (or the settings of [settings]).
  Future<ProviderContainer> open(
    WidgetTester tester, {
    bool dark = false,
    double scale = 1,
    bool still = false,
    bool lyrics = true,
    bool queue = true,
    bool artist = true,
    Color? tint,
    WvAppearance appearance = WvAppearance.aqua,
    Size size = const Size(411, 900),
    int layoutIndex = 4,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    player = _Player(songs);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(() => player),
          positionProvider.overrideWith(_Position.new),
          durationProvider.overrideWith(_Duration.new),
          favoritesStoreProvider.overrideWithValue(_FavStore()),
          paletteProvider.overrideWith(() => _Palette(tint)),
          settingsProvider.overrideWith(
            () => _Settings(
              SettingsState(
                playerLayout: layoutIndex,
                playerLayoutAdaptive: false,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: WavvyTheme.light(appearance),
          darkTheme: WavvyTheme.dark(appearance),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: still,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final song = ref.watch(
                  playerProvider.select((s) => s.currentSong),
                )!;
                return PlayerLayoutHost(
                  data: PlayerLayoutData(
                    song: song,
                    onLyrics: lyrics ? () => opened.add('lyrics') : null,
                    onArtist: artist ? () => opened.add('artist') : null,
                    onQueue: queue ? () => opened.add('queue') : null,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
  }

  group('PosterLayout', () {
    testWidgets('shows the song, the times and the controls', (tester) async {
      await open(tester);
      expect(find.byType(PosterLayout), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
      expect(find.text('0:50'), findsOneWidget);
      expect(find.text('3:00'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byTooltip('Previous'), findsOneWidget);
      expect(find.byTooltip('Next'), findsOneWidget);
      expect(find.byTooltip('Add to Favorites'), findsOneWidget);
      expect(find.byTooltip('View lyrics'), findsOneWidget);
      expect(find.byTooltip('Open queue'), findsOneWidget);
      expect(find.byTooltip('Shuffle'), findsOneWidget);
      expect(find.byTooltip('Repeat'), findsOneWidget);
      expect(find.byTooltip('Sound'), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);
      // The title is big and bold.
      final title = tester.widget<Text>(find.text('Track 1'));
      expect(title.style!.fontSize, 30);
      expect(title.style!.fontWeight, FontWeight.w700);
      expect(title.maxLines, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('play, pause, next and previous work', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(find.byTooltip('Play'), findsOneWidget);
      await tester.tap(find.byTooltip('Next'));
      await tester.pump();
      expect(find.text('Track 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous'));
      await tester.pump();
      expect(find.text('Track 1'), findsOneWidget);
      expect(player.calls, ['toggle', 'toggle', 'next', 'previous']);
    });

    testWidgets('the seek bar seeks', (tester) async {
      await open(tester);
      await tester.drag(find.byType(AquaSeekBar), const Offset(80, 0));
      await tester.pump();
      expect(player.seeks, isNotEmpty);
    });

    testWidgets('shuffle and repeat buttons call through', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Shuffle'));
      await tester.pump();
      expect(find.byTooltip('Shuffle on'), findsOneWidget);
      await tester.tap(find.byTooltip('Repeat'));
      await tester.pump();
      expect(find.byTooltip('Repeat all'), findsOneWidget);
      expect(player.calls, ['shuffle', 'repeat']);
    });

    testWidgets('queue, lyrics, artist and heart call through', (tester) async {
      final c = await open(tester);
      await tester.tap(find.byTooltip('Open queue'));
      await tester.tap(find.byTooltip('View lyrics'));
      await tester.tap(find.text('Artist'));
      await tester.tap(find.byTooltip('Add to Favorites'));
      await tester.pump();
      expect(opened, ['queue', 'lyrics', 'artist']);
      expect(c.read(favoritesProvider).containsKey(1), isTrue);
      expect(find.byTooltip('Remove from Favorites'), findsOneWidget);
    });

    testWidgets('turned-off pages have no button', (tester) async {
      await open(tester, lyrics: false, queue: false, artist: false);
      expect(find.byTooltip('View lyrics'), findsNothing);
      expect(find.byTooltip('Open queue'), findsNothing);
      await tester.tap(find.text('Queue'));
      await tester.fling(find.text('Queue'), const Offset(0, -200), 1500);
      await tester.pump();
      expect(opened, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap on the handle opens the queue', (tester) async {
      await open(tester);
      await tester.tap(find.text('Queue'));
      expect(opened, ['queue']);
    });

    testWidgets('swiping up on the handle opens the queue', (tester) async {
      await open(tester);
      await tester.fling(find.text('Queue'), const Offset(0, -200), 1500);
      await tester.pump();
      expect(opened, ['queue']);
      // A slow drag or a swipe down does not.
      await tester.fling(find.text('Queue'), const Offset(0, 200), 1500);
      await tester.pump();
      expect(opened, ['queue']);
    });

    testWidgets('swiping up on the page opens the queue when it fits', (
      tester,
    ) async {
      await open(tester);
      await tester.fling(
        find.byType(PlayerBackdrop),
        const Offset(0, -250),
        1500,
      );
      await tester.pump();
      expect(opened, ['queue']);
    });

    testWidgets('swiping up on the handle works when the page scrolls', (
      tester,
    ) async {
      await open(tester, size: const Size(320, 360));
      await tester.ensureVisible(find.text('Queue'));
      await tester.pump();
      await tester.fling(find.text('Queue'), const Offset(0, -150), 1500);
      await tester.pump();
      expect(opened, ['queue']);
    });

    testWidgets('the backdrop follows the song', (tester) async {
      await open(tester);
      Finder art(int id) => find.descendant(
        of: find.byType(PlayerBackdrop),
        matching: find.byKey(ValueKey(id)),
      );
      expect(art(1), findsOneWidget);
      player.go(1);
      await tester.pump();
      // Cross-fading: both covers for a moment.
      expect(art(1), findsOneWidget);
      expect(art(2), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(art(1), findsNothing);
      expect(art(2), findsOneWidget);
      expect(find.text('Track 2'), findsOneWidget);
    });

    testWidgets('reduced motion swaps the backdrop at once', (tester) async {
      await open(tester, still: true);
      player.go(1);
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(PlayerBackdrop),
          matching: find.byKey(const ValueKey(1)),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(PlayerBackdrop),
          matching: find.byKey(const ValueKey(2)),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the backdrop is tinted by the album color, only when set', (
      tester,
    ) async {
      await open(tester, tint: const Color(0xFFCC2222));
      final tinted = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(PlayerBackdrop),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        ((tinted.decoration! as BoxDecoration).color)!.a,
        closeTo(PlayerBackdrop.tintAlpha, 0.01),
      );
    });

    testWidgets('no tint without an album color', (tester) async {
      await open(tester);
      final plain = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(PlayerBackdrop),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((plain.decoration! as BoxDecoration).color, Colors.transparent);
    });

    testWidgets('a song without a cover gets a plain backdrop', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: WavvyTheme.light(WvAppearance.aqua),
            home: Scaffold(body: PlayerBackdrop(song: testSong(-5))),
          ),
        ),
      );
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(DecoratedBox), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('it is a repaint layer and the blur never animates', (
      tester,
    ) async {
      await open(tester);
      final filtered = tester.widget<ImageFiltered>(
        find.descendant(
          of: find.byType(PlayerBackdrop),
          matching: find.byType(ImageFiltered),
        ),
      );
      expect(filtered, isNotNull);
      expect(
        find.descendant(
          of: find.byType(PlayerBackdrop),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      // Time passing does not rebuild anything animated.
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('controls have semantics labels', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      for (final label in [
        'Play',
        'Next',
        'Previous',
        'Shuffle',
        'Repeat',
        'Sound',
        'Queue',
      ]) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
      expect(
        tester.getSemantics(find.bySemanticsLabel('Queue')),
        matchesSemantics(label: 'Queue', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('the cover is sharp and sized to the page', (tester) async {
      await open(tester);
      final box = tester.getSize(find.byType(PlayerCover));
      expect(box.width, box.height);
      expect(box.width, greaterThan(150));
      expect(box.width, lessThanOrEqualTo(411 - 40));
    });
  });

  group('no overflow', () {
    for (final size in [const Size(320, 568), const Size(360, 640)]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final dark in [false, true]) {
          testWidgets(
            '${size.width.toInt()}x${size.height.toInt()} at ${scale}x, '
            'dark $dark',
            (tester) async {
              await open(tester, size: size, scale: scale, dark: dark);
              expect(tester.takeException(), isNull);
              expect(find.text('Track 1'), findsOneWidget);
              // Everything can be reached by scrolling.
              await tester.ensureVisible(find.text('Queue'));
              await tester.pump();
              expect(tester.takeException(), isNull);
              await tester.ensureVisible(find.text('Track 1'));
              await tester.pump();
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
    for (final appearance in [
      WvAppearance.aqua,
      WvAppearance.graphite,
      WvAppearance.pinstripe,
      WvAppearance.brushedMetal,
    ]) {
      for (final dark in [false, true]) {
        testWidgets('$appearance, dark $dark, 320 wide at 1.5x', (
          tester,
        ) async {
          await open(
            tester,
            size: const Size(320, 568),
            scale: 1.5,
            dark: dark,
            appearance: appearance,
            tint: const Color(0xFF3366CC),
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Queue'));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a long title and artist stay in bounds', (tester) async {
      final long = SongModel({
        '_id': 9,
        '_data': '/music/9.mp3',
        '_uri': 'content://media/9',
        'title': 'An extremely long song title that goes on ' * 3,
        'artist': 'An equally long artist name ' * 4,
        'duration': 180000,
      });
      songs.add(long);
      addTearDown(songs.removeLast);
      await open(tester, size: const Size(320, 568), scale: 2);
      player.go(3);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wide screen keeps the content centered and narrow', (
      tester,
    ) async {
      await open(tester, size: const Size(1000, 700));
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.byType(PlayerTitleBlock));
      expect(title.width, lessThanOrEqualTo(440));
      expect(title.center.dx, closeTo(500, 1));
    });
  });

  group('readable text', () {
    // The color under the text, worst case: the cover averaged to a color,
    // washed with the page color, tinted, and under the scrim.
    final covers = {
      'white': const Color(0xFFFFFFFF),
      'black': const Color(0xFF000000),
      'yellow': const Color(0xFFFFEE00),
      'red': const Color(0xFFFF0000),
      'blue': const Color(0xFF0000FF),
      'grey': const Color(0xFF808080),
    };
    for (final appearance in [
      WvAppearance.aqua,
      WvAppearance.graphite,
      WvAppearance.pinstripe,
      WvAppearance.brushedMetal,
    ]) {
      for (final dark in [false, true]) {
        testWidgets('title and artist, $appearance, dark $dark', (
          tester,
        ) async {
          await open(tester, dark: dark, appearance: appearance);
          final a = Wv.of(tester.element(find.byType(PosterLayout)));
          final title = tester.widget<Text>(find.text('Track 1'));
          final artist = tester.widget<Text>(find.text('Artist'));
          // The title is in the theme's text colors, so test those.
          final titleColor = title.style!.color ?? a.text;
          final artistColor = artist.style!.color ?? a.textSecondary;
          expect(a.dark, dark);
          for (final cover in covers.values) {
            for (final tint in <Color?>[null, ...covers.values]) {
              final under = PlayerBackdrop.effective(
                cover: cover,
                page: a.background,
                dark: dark,
                tint: tint,
                scrim: kPosterScrimAlpha,
              );
              expect(
                _contrast(titleColor, under),
                greaterThanOrEqualTo(4.5),
                reason: 'title over $cover tinted $tint',
              );
              expect(
                _contrast(artistColor, under),
                greaterThanOrEqualTo(3.0),
                reason: 'artist over $cover tinted $tint',
              );
            }
          }
        });
      }
    }

    testWidgets('the scrim is part of the layout', (tester) async {
      await open(tester);
      final scrims = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((b) {
            final d = b.decoration;
            return d is BoxDecoration &&
                d.gradient is LinearGradient &&
                (d.gradient! as LinearGradient).colors.last.a > 0.4;
          });
      expect(scrims, isNotEmpty);
    });
  });

  group('picker and settings', () {
    testWidgets('the preview paints', (tester) async {
      tester.view.physicalSize = const Size(200, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: WavvyTheme.light(WvAppearance.aqua),
            darkTheme: WavvyTheme.dark(WvAppearance.aqua),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: const Scaffold(body: PosterLayoutPreview()),
          ),
        );
        expect(find.byType(PosterLayoutPreview), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(kPlayerLayoutPreviews[PlayerLayout.poster], isNotNull);
    });

    testWidgets('it appears in the picker and picking it saves it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              () => _Settings(const SettingsState()),
            ),
          ],
          child: MaterialApp(
            theme: WavvyTheme.light(WvAppearance.aqua),
            home: const Scaffold(body: PlayerLayoutPicker()),
          ),
        ),
      );
      expect(find.byType(PosterLayoutPreview), findsOneWidget);
      expect(find.text('Poster'), findsOneWidget);
      await tester.tap(find.text('Poster'));
      await tester.pump();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(PlayerLayoutPicker)),
      );
      expect(c.read(settingsProvider).playerLayout, PlayerLayout.poster.index);
    });

    testWidgets('choosing Poster in settings makes the host show it', (
      tester,
    ) async {
      final c = await open(tester, layoutIndex: 0);
      expect(find.byType(PosterLayout), findsNothing);
      await c
          .read(settingsProvider.notifier)
          .setPlayerLayout(PlayerLayout.poster.index);
      await tester.pump();
      expect(find.byType(PosterLayout), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
    });
  });
}
