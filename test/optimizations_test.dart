import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/error_hooks.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/theme_crossfade.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

class _FavStore implements FavoritesStore {
  final Map<int, int> rows = {};
  @override
  Future<Map<int, int>> load() async => {...rows};
  @override
  Future<void> add(int songId, int addedAt) async => rows[songId] = addedAt;
  @override
  Future<void> remove(int songId) async => rows.remove(songId);
}

SongModel _song(int id) => SongModel({
  '_id': id,
  '_data': '/music/$id.mp3',
  '_uri': 'content://media/$id',
  'title': 'Track $id',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('seek bar commits on release', () {
    Widget bar({
      required List<double> changes,
      required List<double> ends,
      double value = 0,
    }) => MaterialApp(
      theme: WavvyTheme.light(WvAppearance.aqua),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: AquaSeekBar(
              value: value,
              max: 1000,
              onChanged: changes.add,
              onChangeEnd: ends.add,
            ),
          ),
        ),
      ),
    );

    testWidgets('a drag reports every move but ends once, where it stopped', (
      tester,
    ) async {
      final changes = <double>[], ends = <double>[];
      await tester.pumpWidget(bar(changes: changes, ends: ends));
      final rect = tester.getRect(find.byType(AquaSeekBar));
      final finger = await tester.startGesture(
        Offset(rect.left + 20, rect.center.dy),
      );
      for (var i = 0; i < 4; i++) {
        await finger.moveBy(const Offset(30, 0));
      }
      await finger.up();
      await tester.pump();
      expect(changes.length, greaterThan(2));
      expect(ends, hasLength(1));
      expect(ends.single, changes.last);
    });

    testWidgets('a tap ends once at the tapped point', (tester) async {
      final changes = <double>[], ends = <double>[];
      await tester.pumpWidget(bar(changes: changes, ends: ends));
      final rect = tester.getRect(find.byType(AquaSeekBar));
      await tester.tapAt(rect.center);
      expect(ends, hasLength(1));
      expect(ends.single, closeTo(500, 40));
    });

    testWidgets('a screen reader step also ends, so it is committed', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final changes = <double>[], ends = <double>[];
      await tester.pumpWidget(bar(changes: changes, ends: ends, value: 500));
      tester.semantics.performAction(
        find.semantics.byLabel('Seek'),
        SemanticsAction.increase,
      );
      expect(changes, [550]);
      expect(ends, [550]);
      handle.dispose();
    });
  });

  group('liking several songs', () {
    late _FavStore store;
    late ProviderContainer c;
    setUp(() {
      store = _FavStore();
      c = ProviderContainer(
        overrides: [favoritesStoreProvider.overrideWithValue(store)],
      );
      c.read(favoritesProvider); // starts the (empty) load
    });
    tearDown(() => c.dispose());

    final songs = [for (var i = 1; i <= 4; i++) _song(i)];

    test('likes all of them, keeping what was already liked', () async {
      final n = c.read(favoritesProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.toggle(songs[0]);
      final firstStamp = c.read(favoritesProvider)[1];
      await n.setAll(songs, liked: true);
      expect(c.read(favoritesProvider).keys.toSet(), {1, 2, 3, 4});
      expect(c.read(favoritesProvider)[1], firstStamp);
      expect(store.rows.keys.toSet(), {1, 2, 3, 4});
    });

    test('unlikes all of them, and leaves other songs alone', () async {
      final n = c.read(favoritesProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.setAll(songs, liked: true);
      await n.setAll([songs[1], songs[2]], liked: false);
      expect(c.read(favoritesProvider).keys.toSet(), {1, 4});
      expect(store.rows.keys.toSet(), {1, 4});
    });

    test('does nothing when there is nothing to change', () async {
      final n = c.read(favoritesProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.setAll(songs, liked: false);
      expect(c.read(favoritesProvider), isEmpty);
    });
  });

  group('error hooks', () {
    late FlutterExceptionHandler? savedFlutter;
    late ErrorCallback? savedPlatform;
    setUp(() {
      savedFlutter = FlutterError.onError;
      savedPlatform = PlatformDispatcher.instance.onError;
      recentErrors.clear();
    });
    tearDown(() {
      FlutterError.onError = savedFlutter;
      PlatformDispatcher.instance.onError = savedPlatform;
    });

    test('remember framework and unhandled errors, and say handled', () {
      FlutterError.onError = (_) {}; // Flutter's own reporting is not wanted
      installErrorHooks();
      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('boom in build')),
      );
      final handled = PlatformDispatcher.instance.onError!(
        StateError('boom async'),
        StackTrace.current,
      );
      expect(handled, isTrue);
      expect(recentErrors, hasLength(2));
      expect(recentErrors.first, contains('boom in build'));
      expect(recentErrors.last, contains('boom async'));
    });

    test('keep only the latest few', () {
      FlutterError.onError = (_) {};
      installErrorHooks();
      for (var i = 0; i < 30; i++) {
        PlatformDispatcher.instance.onError!(
          StateError('error $i'),
          StackTrace.current,
        );
      }
      expect(recentErrors, hasLength(20));
      expect(recentErrors.last, contains('error 29'));
      expect(recentErrors.first, contains('error 10'));
    });
  });

  group('album color cross-fade', () {
    Widget app({required bool dark, int? tint}) => MaterialApp(
      theme: WavvyTheme.light(WvAppearance.aqua),
      darkTheme: WavvyTheme.dark(WvAppearance.aqua),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) =>
          ThemeCrossFade(themeKey: dark, tintKey: tint, child: child!),
      home: const Scaffold(body: Center(child: Text('hello'))),
    );

    testWidgets('a clearly different color fades, and is quicker', (
      tester,
    ) async {
      await tester.pumpWidget(app(dark: false, tint: 0xFFD32F2F));
      await tester.pumpWidget(app(dark: false, tint: 0xFF1976D2));
      expect(find.byType(RawImage), findsOneWidget);
      // Done within the short tint fade, not the full theme fade.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets('a nearly identical color does not fade at all', (
      tester,
    ) async {
      await tester.pumpWidget(app(dark: false, tint: 0xFFD32F2F));
      await tester.pumpWidget(app(dark: false, tint: 0xFFD53030));
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets('a color change while fading does not start another', (
      tester,
    ) async {
      await tester.pumpWidget(app(dark: false, tint: 0xFFD32F2F));
      await tester.pumpWidget(app(dark: false, tint: 0xFF1976D2));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(app(dark: false, tint: 0xFF388E3C));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('light and dark still use the full fade', (tester) async {
      await tester.pumpWidget(app(dark: false, tint: 0xFFD32F2F));
      await tester.pumpWidget(app(dark: true, tint: 0xFFD32F2F));
      expect(find.byType(RawImage), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(RawImage), findsOneWidget); // 320 ms not up yet
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(RawImage), findsNothing);
    });
  });
}
