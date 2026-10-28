import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/share/now_playing_card_screen.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/now_playing_card.dart';
import 'package:wavvy/widgets/song_menu.dart';

const _longTitle =
    'An Extraordinarily Long Song Title That Goes On And On Across Several '
    'Lines And Never Seems To Come To Any Kind Of End At All (Remastered 2011)';
const _longArtist =
    'The Philharmonic Orchestra Of The Unreasonably Long Artist Names Feat. '
    'Somebody Else And Yet Another Collaborator';

// A 1x1 PNG, a stand-in for a cover.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

const _accent = Color(0xFF3B7DD8);

NowPlayingCardData _data({
  String title = _longTitle,
  String artist = _longArtist,
  Uint8List? cover,
  bool time = true,
}) => NowPlayingCardData(
  title: title,
  artist: artist,
  album: 'An Album With A Name That Is Also Quite Long Indeed',
  cover: cover,
  accent: _accent,
  seed: 7,
  position: time ? const Duration(seconds: 83) : null,
  duration: time ? const Duration(minutes: 4, seconds: 12) : null,
);

SongModel _song({int id = 1}) => SongModel({
  '_id': id,
  '_data': '/music/$id.mp3',
  '_uri': 'content://media/$id',
  'title': 'Blue Monday',
  'artist': 'New Order',
  'album': 'Power, Corruption & Lies',
  'duration': 450000,
});

class _FakePlayer extends PlayerNotifier {
  _FakePlayer(this.song);
  final SongModel? song;
  @override
  PlayerState build() => song == null
      ? const PlayerState()
      : PlayerState(queue: [song!], currentSong: song, currentIndex: 0);
}

class _Position extends PositionNotifier {
  @override
  Duration build() => const Duration(seconds: 42);
}

class _Duration extends DurationNotifier {
  @override
  Duration build() => const Duration(minutes: 3, seconds: 20);
}

/// A card alone, in the look of the app.
Widget _cardHost({
  required NowPlayingCardStyle style,
  required NowPlayingCardAspect aspect,
  required WvAppearance appearance,
  required bool dark,
  NowPlayingCardData? data,
  bool mark = true,
  double scale = 1,
}) => MaterialApp(
  theme: WavvyTheme.light(appearance),
  darkTheme: WavvyTheme.dark(appearance),
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: NowPlayingCard(
        data: data ?? _data(),
        style: style,
        aspect: aspect,
        showMark: mark,
      ),
    ),
  ),
);

class _Rig {
  final shared = <(Uint8List, String)>[];
  final captured = <NowPlayingCardSizing>[];
  Completer<void>? hold;
  Object? shareError;

  List<Override> overrides({SongModel? playing, Uint8List? cover}) => [
    playerProvider.overrideWith(() => _FakePlayer(playing)),
    positionProvider.overrideWith(_Position.new),
    durationProvider.overrideWith(_Duration.new),
    nowPlayingCoverProvider.overrideWith((ref, id) async => cover),
    nowPlayingCardCapturerProvider.overrideWithValue((
      context,
      card,
      sizing,
      cover,
    ) async {
      captured.add(sizing);
      await hold?.future;
      return Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1]);
    }),
    nowPlayingCardSharerProvider.overrideWithValue((png, text) async {
      if (shareError != null) throw shareError!;
      shared.add((png, text));
    }),
  ];
}

Widget _screenHost(_Rig rig, SongModel song, {SongModel? playing}) =>
    ProviderScope(
      overrides: rig.overrides(playing: playing),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        theme: WavvyTheme.light(WvAppearance.aqua),
        home: NowPlayingCardScreen(song: song),
      ),
    );

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

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('sizing', () {
    test('each aspect is 360 wide and exports about 1080 wide', () {
      final square = nowPlayingCardSizing(NowPlayingCardAspect.square);
      final portrait = nowPlayingCardSizing(NowPlayingCardAspect.portrait);
      final story = nowPlayingCardSizing(NowPlayingCardAspect.story);
      expect(square.logical, const Size(360, 360));
      expect(portrait.logical, const Size(360, 450));
      expect(story.logical, const Size(360, 640));
      expect(story.pixelRatio, 3);
      expect(square.pixels, const Size(1080, 1080));
      expect(portrait.pixels, const Size(1080, 1350));
      expect(story.pixels, const Size(1080, 1920));
    });

    test('the output width sets the pixel ratio', () {
      final s = nowPlayingCardSizing(
        NowPlayingCardAspect.story,
        outputWidth: 720,
      );
      expect(s.pixelRatio, 2);
      expect(s.pixels, const Size(720, 1280));
    });
  });

  group('fitFontSize', () {
    const style = TextStyle(fontFamily: 'Ahem');

    test('keeps the largest size when the text fits', () {
      expect(fitFontSize('Hi', style, 300, maxSize: 30, minSize: 12), 30);
    });

    test('shrinks a long title, never below the minimum', () {
      final size = fitFontSize(
        'A longer title here',
        style,
        200,
        maxSize: 30,
        minSize: 12,
      );
      expect(size, lessThan(30));
      expect(size, greaterThanOrEqualTo(12));
      expect(fitFontSize(_longTitle, style, 100, maxSize: 30, minSize: 12), 12);
    });

    test('more lines allow a larger size', () {
      final one = fitFontSize(
        'A longer title here',
        style,
        200,
        maxSize: 30,
        minSize: 8,
      );
      final two = fitFontSize(
        'A longer title here',
        style,
        200,
        maxLines: 2,
        maxSize: 30,
        minSize: 8,
      );
      expect(two, greaterThan(one));
    });
  });

  group('card widgets', () {
    final looks = <(String, WvAppearance, bool)>[
      ('Aqua light', WvAppearance.aqua, false),
      ('Aqua dark', WvAppearance.aqua, true),
      ('Pinstripe light', WvAppearance.pinstripe, false),
      ('Brushed Metal dark', WvAppearance.brushedMetal, true),
    ];
    for (final style in NowPlayingCardStyle.values) {
      for (final aspect in NowPlayingCardAspect.values) {
        for (final (name, appearance, dark) in looks) {
          testWidgets('${style.name} ${aspect.name} $name: long text, no art', (
            tester,
          ) async {
            tall(tester);
            await tester.pumpWidget(
              _cardHost(
                style: style,
                aspect: aspect,
                appearance: appearance,
                dark: dark,
              ),
            );
            expect(tester.takeException(), isNull);
            expect(
              tester.getSize(find.byType(NowPlayingCard)),
              nowPlayingCardSizing(aspect).logical,
            );
            expect(find.text('WAVVY'), findsOneWidget);
          });
        }

        testWidgets('${style.name} ${aspect.name}: art, no time, no mark, 2x '
            'text scale', (tester) async {
          tall(tester);
          await tester.pumpWidget(
            _cardHost(
              style: style,
              aspect: aspect,
              appearance: WvAppearance.aqua,
              dark: false,
              data: _data(cover: _png, time: false),
              mark: false,
              scale: 2,
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('WAVVY'), findsNothing);
        });

        testWidgets('${style.name} ${aspect.name}: short text, no art', (
          tester,
        ) async {
          tall(tester);
          await tester.pumpWidget(
            _cardHost(
              style: style,
              aspect: aspect,
              appearance: WvAppearance.graphite,
              dark: true,
              data: _data(title: 'Song', artist: 'Band'),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Song'), findsOneWidget);
          expect(find.text('1:23'), findsOneWidget);
          expect(find.text('4:12'), findsOneWidget);
        });
      }
    }
  });

  group('screen', () {
    testWidgets('style and aspect pickers update the preview and are kept', (
      tester,
    ) async {
      tall(tester);
      final rig = _Rig();
      await tester.pumpWidget(_screenHost(rig, _song()));
      await tester.pump();

      NowPlayingCard card() =>
          tester.widget<NowPlayingCard>(find.byType(NowPlayingCard));
      expect(card().style, NowPlayingCardStyle.aqua);
      expect(card().aspect, NowPlayingCardAspect.square);

      await tester.tap(find.text('Poster'));
      await tester.pump();
      await tester.tap(find.text('Story 9:16'));
      await tester.pump();
      expect(card().style, NowPlayingCardStyle.poster);
      expect(card().aspect, NowPlayingCardAspect.story);

      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString('share_card_style'), 'poster');
      expect(await prefs.getString('share_card_aspect'), 'story');

      // A new screen starts from the last choice.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_screenHost(_Rig(), _song()));
      await tester.pump();
      await tester.pump();
      expect(card().style, NowPlayingCardStyle.poster);
      expect(card().aspect, NowPlayingCardAspect.story);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the mark toggle; the time toggle only for the playing song', (
      tester,
    ) async {
      tall(tester);
      final song = _song();
      await tester.pumpWidget(_screenHost(_Rig(), song, playing: song));
      await tester.pump();

      NowPlayingCard card() =>
          tester.widget<NowPlayingCard>(find.byType(NowPlayingCard));
      expect(find.byType(AquaSwitch), findsNWidgets(2));
      expect(card().showMark, isTrue);
      expect(card().data.hasTime, isTrue);
      expect(card().data.position, const Duration(seconds: 42));
      expect(card().data.duration, const Duration(minutes: 3, seconds: 20));

      await tester.tap(find.byType(AquaSwitch).first);
      await tester.pump();
      expect(card().showMark, isFalse);
      await tester.tap(find.byType(AquaSwitch).last);
      await tester.pump();
      expect(card().data.hasTime, isFalse);

      // Another song is open: nothing to show the time of.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_screenHost(_Rig(), _song(id: 2), playing: song));
      await tester.pump();
      expect(find.byType(AquaSwitch), findsOneWidget);
      expect(card().data.hasTime, isFalse);
    });

    testWidgets('Share hands the image and "Title - Artist" over once', (
      tester,
    ) async {
      tall(tester);
      final rig = _Rig();
      await tester.pumpWidget(_screenHost(rig, _song()));
      await tester.pump();
      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pump();
      expect(rig.shared, hasLength(1));
      expect(rig.shared.single.$2, 'Blue Monday - New Order');
      expect(rig.shared.single.$1.take(4), [137, 80, 78, 71]);
      expect(
        rig.captured.single,
        nowPlayingCardSizing(NowPlayingCardAspect.square),
      );
    });

    testWidgets('a second tap while sharing does nothing', (tester) async {
      tall(tester);
      final rig = _Rig()..hold = Completer<void>();
      await tester.pumpWidget(_screenHost(rig, _song()));
      await tester.pump();
      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.tap(find.text('Share'), warnIfMissed: false);
      await tester.pump();
      rig.hold!.complete();
      await tester.pump();
      await tester.pump();
      expect(rig.captured, hasLength(1));
      expect(rig.shared, hasLength(1));

      // Free again afterwards.
      rig.hold = null;
      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pump();
      expect(rig.shared, hasLength(2));
    });

    testWidgets('an error shows a toast and frees the button', (tester) async {
      tall(tester);
      final rig = _Rig()..shareError = StateError('disk full');
      await tester.pumpWidget(_screenHost(rig, _song()));
      await tester.pump();
      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Error sharing'), findsOneWidget);
      expect(find.textContaining('disk full'), findsOneWidget);

      rig.shareError = null;
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pump();
      expect(rig.shared, hasLength(1));
    });

    testWidgets('a song opened from outside gets a plain card', (tester) async {
      tall(tester);
      final rig = _Rig();
      await tester.pumpWidget(_screenHost(rig, _song(id: -5)));
      await tester.pump();
      expect(
        tester.widget<NowPlayingCard>(find.byType(NowPlayingCard)).data.cover,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('song menu', () {
    Widget host(SongModel song) => ProviderScope(
      overrides: _Rig().overrides(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        theme: WavvyTheme.light(WvAppearance.aqua),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: TextButton(
                onPressed: () => SongMenuHelper.show(context, ref, song),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    for (final id in [1, -1]) {
      testWidgets('offers Share card and opens the screen (id $id)', (
        tester,
      ) async {
        tall(tester);
        await tester.pumpWidget(host(_song(id: id)));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Share card'),
          100,
          scrollable: find
              .descendant(
                of: find.byType(AquaSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('Share card'));
        await tester.pumpAndSettle();
        expect(find.byType(NowPlayingCardScreen), findsOneWidget);
        expect(
          tester
              .widget<NowPlayingCardScreen>(find.byType(NowPlayingCardScreen))
              .song
              .id,
          id,
        );
      });
    }
  });
}
