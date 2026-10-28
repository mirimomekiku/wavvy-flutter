import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/selection_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/selection_bar.dart';
import 'package:wavvy/widgets/song_selection.dart';

SongModel _song(int id) => SongModel({
  '_id': id,
  '_data': '/music/$id.mp3',
  '_uri': 'content://media/$id',
  'title': 'Track $id',
  'artist': 'Artist $id',
  'duration': 180000,
});

class _FavStore implements FavoritesStore {
  final Map<int, int> rows = {};
  @override
  Future<Map<int, int>> load() async => {...rows};
  @override
  Future<void> add(int songId, int addedAt) async => rows[songId] = addedAt;
  @override
  Future<void> remove(int songId) async => rows.remove(songId);
}

/// Records what the selection bar asks the player to do.
class _Player extends PlayerNotifier {
  final calls = <String>[];
  List<int> ids(List<SongModel> s) => [for (final x in s) x.id];
  @override
  PlayerState build() => const PlayerState();
  @override
  Future<void> playSong(SongModel song, {List<SongModel>? contextList}) async =>
      calls.add('play ${ids(contextList ?? [song])}');
  @override
  Future<void> playNextAll(List<SongModel> songs) async =>
      calls.add('next ${ids(songs)}');
  @override
  Future<void> addAllToQueue(List<SongModel> songs) async =>
      calls.add('queue ${ids(songs)}');
  @override
  Future<void> deleteSongs(List<SongModel> songs) async =>
      calls.add('delete ${ids(songs)}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final songs = [for (var i = 1; i <= 4; i++) _song(i)];

  late _Player player;
  late _FavStore favorites;
  late ProviderContainer container;

  Widget app(Widget body) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      theme: WavvyTheme.light(WvAppearance.aqua),
      home: Scaffold(body: body, bottomNavigationBar: const SelectionBar()),
    ),
  );

  setUp(() {
    player = _Player();
    favorites = _FavStore();
    container = ProviderContainer(
      overrides: [
        playerProvider.overrideWith(() => player),
        favoritesStoreProvider.overrideWithValue(favorites),
      ],
    );
  });
  tearDown(() => container.dispose());

  SelectionNotifier selection() => container.read(selectionProvider.notifier);

  group('the song row', () {
    var taps = 0;
    Widget rows() => ListView(
      children: [
        for (var i = 0; i < songs.length; i++)
          SelectableSongRow(
            song: songs[i],
            index: i,
            isCurrent: false,
            isPlaying: false,
            secondary: 'Artist',
            scope: songs,
            onTap: () => taps++,
            onAction: () {},
          ),
      ],
    );

    setUp(() => taps = 0);

    testWidgets('a tap plays, as before', (tester) async {
      await tester.pumpWidget(app(rows()));
      await tester.tap(find.text('Track 2'));
      expect(taps, 1);
      expect(container.read(selectionProvider).active, isFalse);
    });

    testWidgets('a long press starts picking with that song', (tester) async {
      await tester.pumpWidget(app(rows()));
      await tester.longPress(find.text('Track 2'));
      await tester.pump();
      expect(container.read(selectionProvider).selected.map((s) => s.id), [2]);
      expect(taps, 0);
    });

    testWidgets('while picking, taps pick and drop instead of playing', (
      tester,
    ) async {
      await tester.pumpWidget(app(rows()));
      await tester.longPress(find.text('Track 2'));
      await tester.pump();
      await tester.tap(find.text('Track 4'));
      await tester.pump();
      expect(container.read(selectionProvider).selected.map((s) => s.id), [
        2,
        4,
      ]);
      await tester.tap(find.text('Track 2'));
      await tester.pump();
      expect(container.read(selectionProvider).selected.map((s) => s.id), [4]);
      expect(taps, 0);
    });

    testWidgets(
      'picked rows show a checked Aqua box, the others an empty one',
      (tester) async {
        await tester.pumpWidget(app(rows()));
        // Not picking: no boxes, the options button is there.
        expect(find.byType(AquaCheckbox), findsNothing);
        expect(find.byIcon(Icons.more_horiz_rounded), findsNWidgets(4));

        await tester.longPress(find.text('Track 1'));
        await tester.pump();
        final boxes = tester
            .widgetList<AquaCheckbox>(find.byType(AquaCheckbox))
            .toList();
        expect(boxes, hasLength(4));
        expect(boxes.where((b) => b.value), hasLength(1));
        // The options button is replaced while picking.
        expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      },
    );
  });

  group('the Aqua check box', () {
    Widget box({
      required bool value,
      ValueChanged<bool>? onChanged,
      bool disabled = false,
      bool dark = false,
      double size = 18,
    }) => MaterialApp(
      theme: dark
          ? WavvyTheme.dark(WvAppearance.aqua)
          : WavvyTheme.light(WvAppearance.aqua),
      home: Scaffold(
        body: Center(
          child: AquaCheckbox(
            value: value,
            onChanged: onChanged,
            disabled: disabled,
            size: size,
          ),
        ),
      ),
    );

    testWidgets('a tap asks for the opposite value', (tester) async {
      bool? asked;
      await tester.pumpWidget(box(value: false, onChanged: (v) => asked = v));
      await tester.tap(find.byType(AquaCheckbox));
      expect(asked, isTrue);
      await tester.pumpWidget(box(value: true, onChanged: (v) => asked = v));
      await tester.tap(find.byType(AquaCheckbox));
      expect(asked, isFalse);
    });

    testWidgets('without a callback, or when disabled, a tap does nothing', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(box(value: false));
      await tester.tap(find.byType(AquaCheckbox));
      await tester.pumpWidget(
        box(value: false, disabled: true, onChanged: (_) => taps++),
      );
      await tester.tap(find.byType(AquaCheckbox));
      expect(taps, 0);
    });

    testWidgets('tells screen readers whether it is checked', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(box(value: true, onChanged: (_) {}));
      expect(
        tester.getSemantics(find.byType(AquaCheckbox)),
        isSemantics(isChecked: true),
      );
      await tester.pumpWidget(box(value: false, onChanged: (_) {}));
      await tester.pump();
      expect(
        tester.getSemantics(find.byType(AquaCheckbox)),
        isSemantics(isChecked: false),
      );
      handle.dispose();
    });

    for (final dark in [false, true]) {
      testWidgets(
        'draws on and off, mid-change, at several sizes (dark: $dark)',
        (tester) async {
          for (final size in [14.0, 18.0, 22.0, 32.0]) {
            await tester.pumpWidget(box(value: false, dark: dark, size: size));
            await tester.pumpWidget(box(value: true, dark: dark, size: size));
            await tester.pump(const Duration(milliseconds: 60)); // mid-change
            await tester.pump(const Duration(milliseconds: 200));
            expect(
              tester.getSize(find.byType(AquaCheckbox)),
              Size.square(size),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('holds still for reduced motion', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WavvyTheme.light(WvAppearance.aqua),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: AquaCheckbox(value: false, onChanged: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: WavvyTheme.light(WvAppearance.aqua),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(child: AquaCheckbox(value: true, onChanged: (_) {})),
            ),
          ),
        ),
      );
      // Settled on the very next frame: nothing left animating.
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('the selection bar', () {
    testWidgets('shows nothing useful until songs are picked, then the count', (
      tester,
    ) async {
      selection().start(songs[0], scope: songs);
      selection().toggle(songs[2]);
      await tester.pumpWidget(app(const SizedBox.shrink()));
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('Play plays the picked songs in order and stops picking', (
      tester,
    ) async {
      selection().start(songs[2], scope: songs);
      selection().toggle(songs[0]);
      await tester.pumpWidget(app(const SizedBox.shrink()));
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      expect(player.calls, ['play [3, 1]']);
      expect(container.read(selectionProvider).active, isFalse);
    });

    testWidgets('Play next and Add to queue pass the picked songs', (
      tester,
    ) async {
      selection().start(songs[1], scope: songs);
      selection().toggle(songs[3]);
      await tester.pumpWidget(app(const SizedBox.shrink()));
      await tester.tap(find.byTooltip('Play next'));
      await tester.pump();
      expect(player.calls, ['next [2, 4]']);

      selection().start(songs[0], scope: songs);
      await tester.pump();
      await tester.tap(find.byTooltip('Add to queue'));
      await tester.pump();
      expect(player.calls.last, 'queue [1]');
    });

    testWidgets('close ends picking without doing anything', (tester) async {
      selection().start(songs[0], scope: songs);
      await tester.pumpWidget(app(const SizedBox.shrink()));
      await tester.tap(find.byTooltip('Cancel selection'));
      await tester.pump();
      expect(container.read(selectionProvider).active, isFalse);
      expect(player.calls, isEmpty);
    });

    testWidgets('More > Select all picks the rest of the list', (tester) async {
      selection().start(songs[1], scope: songs);
      await tester.pumpWidget(app(const SizedBox.shrink()));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(container.read(selectionProvider).count, 4);
      expect(find.text('4 selected'), findsOneWidget);
      // Nothing left to select, so the item is gone.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Select all'), findsNothing);
    });

    testWidgets('More > Add to favorites likes them all', (tester) async {
      selection().start(songs[0], scope: songs);
      selection().toggle(songs[1]);
      await tester.pumpWidget(app(const SizedBox.shrink()));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to favorites'));
      await tester.pumpAndSettle();
      expect(favorites.rows.keys.toSet(), {1, 2});
      expect(container.read(selectionProvider).active, isFalse);
    });

    testWidgets('More > Delete asks first, and only then deletes', (
      tester,
    ) async {
      selection().start(songs[0], scope: songs);
      selection().toggle(songs[1]);
      await tester.pumpWidget(app(const SizedBox.shrink()));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 songs?'), findsOneWidget);
      expect(player.calls, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(player.calls, isEmpty);
      expect(container.read(selectionProvider).active, isTrue);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(player.calls, ['delete [1, 2]']);
    });
  });
}
