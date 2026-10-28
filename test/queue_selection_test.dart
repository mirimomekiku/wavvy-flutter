import 'dart:math' as math;

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
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/queue_selection_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

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
}

class _Duration extends DurationNotifier {
  @override
  Duration build() => const Duration(minutes: 3);
}

class _FavStore implements FavoritesStore {
  @override
  Future<Map<int, int>> load() async => {};
  @override
  Future<void> add(int id, int at) async {}
  @override
  Future<void> remove(int id) async {}
}

class _Rates implements RateStore {
  @override
  Future<Map<String, PlaybackRate>> load() async => {};
  @override
  Future<void> save(Map<String, PlaybackRate> r) async {}
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

  group('queue edits on several rows', () {
    late MemoryPlayer player;
    late ProviderContainer container;
    late PlayerNotifier notifier;

    /// Loads [ids] (repeats allowed) with row [current] playing.
    Future<List<SongModel>> load(List<int> ids, int current) async {
      final songs = [for (final id in ids) testSong(id)];
      await notifier.playSong(songs[current], contextList: songs);
      player.emit(current);
      return songs;
    }

    PlayerState state() => container.read(playerProvider);

    setUp(() {
      player = MemoryPlayer();
      container = ProviderContainer(
        overrides: [audioPlayerProvider.overrideWithValue(player)],
      );
      notifier = container.read(playerProvider.notifier);
    });
    tearDown(() async {
      container.dispose();
      await player.close();
    });

    /// The queue, the player's sources and the playing row all agree.
    void expectConsistent(List<SongModel> expected, SongModel playing) {
      expect(state().queue.length, expected.length, reason: 'queue length');
      for (var i = 0; i < expected.length; i++) {
        expect(identical(state().queue[i], expected[i]), isTrue, reason: 'q$i');
        expect(
          identical((player.sources[i] as dynamic).tag, expected[i]),
          isTrue,
          reason: 'source $i',
        );
      }
      expect(player.sources.length, expected.length);
      expect(identical(state().queue[state().currentIndex], playing), isTrue);
    }

    test(
      'removing picked rows removes them from both, duplicates too',
      () async {
        final songs = await load([1, 2, 1, 3, 2, 1], 3);
        expect(await notifier.removeQueueIndices({0, 2, 5}), isTrue);
        expectConsistent([songs[1], songs[3], songs[4]], songs[3]);
        expect(state().currentIndex, 1);
      },
    );

    test('removing the playing row leaves the rest for the player', () async {
      final songs = await load([1, 2, 3, 4], 1);
      await notifier.removeQueueIndices({1, 2});
      expect(player.nativeOrder, [1, 4]);
      expect(state().queue.map((s) => s.id), [1, 4]);
      // The real player moves on and reports the new index; the playing row
      // is no longer in the queue, so none is claimed meanwhile.
      player.emit(1);
      expect(state().currentSong?.id, 4);
      expect(state().currentIndex, 1);
      expect(identical(state().queue[1], songs[3]), isTrue);
    });

    test('removing every row stops and empties the queue', () async {
      await load([1, 2, 3], 0);
      await notifier.removeQueueIndices({0, 1, 2});
      expect(state().queue, isEmpty);
      expect(player.sources, isEmpty);
      expect(state().currentIndex, -1);
      expect(state().currentSong, isNull);
    });

    test('an empty or invalid pick changes nothing', () async {
      final songs = await load([1, 2, 3], 1);
      expect(await notifier.removeQueueIndices({}), isFalse);
      expect(await notifier.removeQueueIndices({-1, 3, 99}), isFalse);
      expect(await notifier.moveQueueIndicesToNext({}), isFalse);
      expect(await notifier.moveQueueIndicesToEnd({}), isFalse);
      expect(await notifier.moveQueueIndicesToEnd({7}), isFalse);
      expectConsistent(songs, songs[1]);
    });

    test('moving rows next keeps their order and the playing song', () async {
      final songs = await load([1, 2, 3, 4, 5, 6], 2);
      expect(await notifier.moveQueueIndicesToNext({0, 4, 5}), isTrue);
      expectConsistent([
        songs[1],
        songs[2],
        songs[0],
        songs[4],
        songs[5],
        songs[3],
      ], songs[2]);
      expect(state().currentIndex, 1);
    });

    test('next with the playing row picked keeps it as the anchor', () async {
      final songs = await load([1, 2, 3, 4, 5], 2);
      await notifier.moveQueueIndicesToNext({0, 2, 4});
      expectConsistent([
        songs[1],
        songs[2],
        songs[0],
        songs[4],
        songs[3],
      ], songs[2]);
    });

    test('next with only the playing row picked is a no-op', () async {
      final songs = await load([1, 2, 3], 1);
      expect(await notifier.moveQueueIndicesToNext({1}), isFalse);
      expectConsistent(songs, songs[1]);
    });

    test(
      'next when the rows already follow the playing one is a no-op',
      () async {
        final songs = await load([1, 2, 3, 4], 1);
        expect(await notifier.moveQueueIndicesToNext({2, 3}), isFalse);
        expectConsistent(songs, songs[1]);
      },
    );

    test('moving rows to the end keeps their order', () async {
      final songs = await load([1, 2, 3, 4, 5], 3);
      expect(await notifier.moveQueueIndicesToEnd({0, 3}), isTrue);
      expectConsistent([
        songs[1],
        songs[2],
        songs[4],
        songs[0],
        songs[3],
      ], songs[3]);
      expect(state().currentIndex, 4);
    });

    test(
      'all rows picked: to the end changes nothing, next keeps the anchor',
      () async {
        final songs = await load([1, 2, 3], 1);
        expect(await notifier.moveQueueIndicesToEnd({0, 1, 2}), isFalse);
        expectConsistent(songs, songs[1]);
        // The playing row stays the anchor; the others follow it in order.
        expect(await notifier.moveQueueIndicesToNext({0, 1, 2}), isTrue);
        expectConsistent([songs[1], songs[0], songs[2]], songs[1]);
      },
    );

    test('shuffle on: queue index is still source index', () async {
      final songs = await load([1, 2, 3, 4], 0);
      player.shuffled = true;
      player.shuffleOrder = [0, 2, 1, 3];
      await notifier.moveQueueIndicesToEnd({0, 1});
      expectConsistent([songs[2], songs[3], songs[0], songs[1]], songs[0]);
    });

    test('a rejected call rolls the queue back as a whole', () async {
      final songs = await load([1, 2, 3, 4], 1);
      player.failNextEdit = true;
      expect(await notifier.removeQueueIndices({0, 3}), isFalse);
      expectConsistent(songs, songs[1]);
      player.failNextEdit = true;
      expect(await notifier.moveQueueIndicesToEnd({0}), isFalse);
      expectConsistent(songs, songs[1]);
      player.failNextEdit = true;
      expect(await notifier.moveQueueIndicesToNext({3}), isFalse);
      expectConsistent(songs, songs[1]);
      expect(state().currentIndex, 1);
    });

    test('a failure half way undoes the calls already made', () async {
      final songs = await load([1, 2, 3, 4, 5, 6], 2);
      // Three moves; the third is rejected.
      player.failEditAfter = 2;
      expect(await notifier.moveQueueIndicesToNext({0, 4, 5}), isFalse);
      expectConsistent(songs, songs[2]);
      expect(state().currentIndex, 2);

      player.failEditAfter = 1;
      expect(await notifier.removeQueueIndices({0, 3, 5}), isFalse);
      expectConsistent(songs, songs[2]);

      player.failEditAfter = 1;
      expect(await notifier.moveQueueIndicesToEnd({0, 1, 3}), isFalse);
      expectConsistent(songs, songs[2]);
    });

    test('random picks end with the expected order in both lists', () async {
      final random = math.Random(42);
      for (var round = 0; round < 250; round++) {
        final n = 1 + random.nextInt(9);
        // Few distinct ids, so duplicates are common.
        final ids = [for (var i = 0; i < n; i++) random.nextInt(4)];
        final current = random.nextInt(n);
        final songs = await load(ids, current);
        final picks = {
          for (var i = 0; i < n; i++)
            if (random.nextInt(3) == 0) i,
        };
        final playing = songs[current];
        final kind = random.nextInt(3);
        final List<SongModel> expected;
        switch (kind) {
          case 0:
            await notifier.removeQueueIndices(picks);
            expected = [
              for (var i = 0; i < n; i++)
                if (!picks.contains(i)) songs[i],
            ];
          case 1:
            await notifier.moveQueueIndicesToNext(picks);
            final moved = [
              for (var i = 0; i < n; i++)
                if (picks.contains(i) && i != current) songs[i],
            ];
            final rest = [
              for (var i = 0; i < n; i++)
                if (!picks.contains(i) || i == current) songs[i],
            ];
            expected = [...rest]..insertAll(rest.indexOf(playing) + 1, moved);
          default:
            await notifier.moveQueueIndicesToEnd(picks);
            expected = [
              for (var i = 0; i < n; i++)
                if (!picks.contains(i)) songs[i],
              for (var i = 0; i < n; i++)
                if (picks.contains(i)) songs[i],
            ];
        }
        final reason =
            'round $round kind $kind ids $ids current $current '
            'picks $picks';
        if (expected.isEmpty) {
          expect(state().queue, isEmpty, reason: reason);
          continue;
        }
        expect(player.sources.length, expected.length, reason: reason);
        for (var i = 0; i < expected.length; i++) {
          expect(
            identical((player.sources[i] as dynamic).tag, expected[i]),
            isTrue,
            reason: '$reason source $i',
          );
          expect(
            identical(state().queue[i], expected[i]),
            isTrue,
            reason: '$reason queue $i',
          );
        }
        if (expected.contains(playing)) {
          expect(
            identical(state().queue[state().currentIndex], playing),
            isTrue,
            reason: '$reason playing row',
          );
        }
      }
    });
  });

  group('QueueSelectionNotifier', () {
    late MemoryPlayer player;
    late ProviderContainer container;

    setUp(() async {
      player = MemoryPlayer();
      container = ProviderContainer(
        overrides: [audioPlayerProvider.overrideWithValue(player)],
      );
      final songs = [for (var i = 1; i <= 4; i++) testSong(i)];
      await container
          .read(playerProvider.notifier)
          .playSong(songs[0], contextList: songs);
      container.listen(queueSelectionProvider, (_, _) {});
    });
    tearDown(() async {
      container.dispose();
      await player.close();
    });

    QueueSelection sel() => container.read(queueSelectionProvider);
    QueueSelectionNotifier n() =>
        container.read(queueSelectionProvider.notifier);

    test('starts off, then picks by index', () {
      expect(sel().active, isFalse);
      n().start(2);
      expect(sel().active, isTrue);
      expect(sel().sorted, [2]);
      n().toggle(0);
      n().toggle(3);
      expect(sel().sorted, [0, 2, 3]);
      n().toggle(2);
      expect(sel().contains(2), isFalse);
      expect(sel().count, 2);
    });

    test('dropping the last pick keeps selecting until cancelled', () {
      n().start(1);
      n().toggle(1);
      expect(sel().active, isTrue);
      expect(sel().count, 0);
      n().clear();
      expect(sel().active, isFalse);
    });

    test('select all and none', () {
      n().start(0);
      n().selectAll();
      expect(sel().sorted, [0, 1, 2, 3]);
      n().selectNone();
      expect(sel().active, isTrue);
      expect(sel().picked, isEmpty);
    });

    test('ignores bad indices and toggles when not selecting', () {
      n().toggle(1);
      n().selectAll();
      expect(sel().active, isFalse);
      n().start(9);
      n().start(-1);
      expect(sel().active, isFalse);
    });

    test(
      'adding to the end keeps the picks, other edits end selecting',
      () async {
        n().start(1);
        final player = container.read(playerProvider.notifier);
        await player.addToQueue(testSong(9));
        expect(sel().sorted, [1]);

        await player.moveQueueItem(0, 3);
        expect(sel().active, isFalse);

        n().start(0);
        await player.removeFromQueue(4);
        expect(sel().active, isFalse);
      },
    );

    test('is disposed with the last listener', () async {
      final c = ProviderContainer(
        overrides: [audioPlayerProvider.overrideWithValue(MemoryPlayer())],
      );
      final sub = c.listen(queueSelectionProvider, (_, _) {});
      await c
          .read(playerProvider.notifier)
          .playSong(testSong(1), contextList: [testSong(1), testSong(2)]);
      c.read(queueSelectionProvider.notifier).start(0);
      expect(c.read(queueSelectionProvider).active, isTrue);
      sub.close();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(queueSelectionProvider).active, isFalse);
      c.dispose();
    });
  });

  group('Queue page selecting', () {
    final songs = [for (var i = 1; i <= 5; i++) testSong(i, albumId: 100)];

    late MemoryPlayer player;

    /// Opens the sheet as a pushed route (so Back can be tried) on the Queue
    /// page, with row 2 playing.
    Future<ProviderContainer> open(
      WidgetTester tester, {
      bool dark = false,
      double scale = 1,
      Size size = const Size(411, 900),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      player = MemoryPlayer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioPlayerProvider.overrideWithValue(player),
            libraryProvider.overrideWith(() => _Library(songs)),
            playlistsProvider.overrideWith(_Playlists.new),
            positionProvider.overrideWith(_Position.new),
            durationProvider.overrideWith(_Duration.new),
            favoritesStoreProvider.overrideWithValue(_FavStore()),
            rateStoreProvider.overrideWithValue(_Rates()),
            ytDlpEngineProvider.overrideWithValue(FakeYtDlpEngine()),
            downloadStoreProvider.overrideWithValue(FakeDownloadStore()),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: WavvyTheme.light(WvAppearance.aqua),
            darkTheme: WavvyTheme.dark(WvAppearance.aqua),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FullPlayerSheet(initialPage: 1),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      final c = ProviderScope.containerOf(
        tester.element(find.byType(TextButton)),
      );
      await c
          .read(playerProvider.notifier)
          .playSong(songs[1], contextList: songs);
      player.emit(1);
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return c;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a long press starts, taps pick instead of jumping', (
      tester,
    ) async {
      final c = await open(tester);
      expect(find.byType(AquaCheckbox), findsNothing);
      expect(find.byTooltip('Remove from queue'), findsWidgets);

      await tester.longPress(find.text('Track 4'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(AquaCheckbox), findsNWidgets(5));
      expect(find.byTooltip('Remove from queue'), findsNothing);
      expect(find.byTooltip('Reorder Track 4'), findsNothing);
      expect(c.read(queueSelectionProvider).sorted, [3]);

      await tester.tap(find.text('Track 5'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.text('Track 4'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(player.seeks, isEmpty); // no jump while selecting
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Cancel selection'));
      await tester.pump();
      expect(find.byType(AquaCheckbox), findsNothing);
      expect(find.text('Up next'), findsOneWidget);
      await tester.tap(find.text('Track 5'));
      await tester.pump();
      expect(player.seeks, hasLength(1)); // a tap jumps again
    });

    testWidgets('select all and none', (tester) async {
      await open(tester);
      await tester.longPress(find.text('Track 1'));
      await tester.pump();
      await tester.tap(find.text('Select all'));
      await tester.pump();
      expect(find.text('5 selected'), findsOneWidget);
      await tester.tap(find.text('Select none'));
      await tester.pump();
      expect(find.text('0 selected'), findsOneWidget);
      // Actions wait for a pick.
      await tester.tap(find.byTooltip('Move to end'));
      await tester.pump();
      expect(player.nativeOrder, [1, 2, 3, 4, 5]);
    });

    testWidgets('Play next and Move to end call through', (tester) async {
      await open(tester);
      await tester.longPress(find.text('Track 4'));
      await tester.pump();
      await tester.tap(find.text('Track 5'));
      await tester.pump();
      await tester.tap(find.byTooltip('Play next'));
      await settle(tester);
      expect(player.nativeOrder, [1, 2, 4, 5, 3]);
      expect(find.byType(AquaCheckbox), findsNothing); // selecting ended

      await tester.longPress(find.text('Track 1'));
      await tester.pump();
      await tester.tap(find.byTooltip('Move to end'));
      await settle(tester);
      expect(player.nativeOrder, [2, 4, 5, 3, 1]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Remove skips the question unless the playing row is picked', (
      tester,
    ) async {
      final c = await open(tester);
      await tester.longPress(find.text('Track 4'));
      await tester.pump();
      await tester.tap(find.byTooltip('Remove'));
      await settle(tester);
      expect(player.nativeOrder, [1, 2, 3, 5]);
      expect(c.read(playerProvider).queue, hasLength(4));

      // Row 1 (Track 2) is playing: Remove asks first.
      await tester.longPress(find.text('Track 2'));
      await tester.pump();
      await tester.tap(find.byTooltip('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Remove the playing song?'), findsOneWidget);
      expect(player.nativeOrder, [1, 2, 3, 5]);
      await tester.tap(find.text('Remove').last);
      await settle(tester);
      expect(player.nativeOrder, [1, 3, 5]);
    });

    testWidgets('Back ends selecting first, then closes', (tester) async {
      await open(tester);
      await tester.longPress(find.text('Track 3'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1 selected'), findsNothing);
      expect(find.text('Up next'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(FullPlayerSheet), findsNothing);
    });

    testWidgets('leaving the Queue page ends selecting', (tester) async {
      final c = await open(tester);
      await tester.longPress(find.text('Track 3'));
      await tester.pump();
      await tester.tap(find.byTooltip('Player'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byTooltip('Queue'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(c.read(queueSelectionProvider).active, isFalse);
      expect(find.byType(AquaCheckbox), findsNothing);
    });

    testWidgets('another queue edit does not leave stale picks', (
      tester,
    ) async {
      final c = await open(tester);
      await tester.longPress(find.text('Track 4'));
      await tester.pump();
      await c.read(playerProvider.notifier).removeFromQueue(0);
      await tester.pump();
      expect(find.byType(AquaCheckbox), findsNothing);
      expect(c.read(queueSelectionProvider).picked, isEmpty);
    });

    for (final dark in [false, true]) {
      testWidgets('fits at 320 wide and 1.5x text, dark $dark', (tester) async {
        await open(tester, dark: dark, scale: 1.5, size: const Size(320, 640));
        await tester.longPress(find.text('Track 4'));
        await tester.pump();
        await tester.tap(find.text('Select all'));
        await tester.pump();
        expect(find.text('5 selected'), findsOneWidget);
        for (final tip in const [
          'Remove',
          'Play next',
          'Move to end',
          'Add to playlist',
          'Save as playlist',
          'Cancel selection',
        ]) {
          expect(find.byTooltip(tip), findsOneWidget, reason: tip);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
