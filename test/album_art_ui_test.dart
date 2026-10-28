import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/artwork/album_art_client.dart';
import 'package:wavvy/providers/album_art_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/settings/album_art_setting.dart';
import 'package:wavvy/screens/settings/settings.screen.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_theme.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/album_art_fallback.dart';

/// A real 1x1 PNG, so Image.file can decode it.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

AlbumModel _album(int id, {String? artist, String? name}) => AlbumModel({
  '_id': id,
  'album': name ?? 'Album $id',
  'artist': artist ?? 'Artist $id',
  'numsongs': 5,
});

SongModel _song(int id, {int? albumId, String? album, String? artist}) =>
    SongModel({
      '_id': id,
      '_data': '/music/$id.mp3',
      '_uri': 'content://media/$id',
      '_display_name': '$id.mp3',
      '_display_name_wo_ext': 'Song $id',
      '_size': 1024,
      'title': 'Song $id',
      'artist': artist ?? 'Artist $id',
      'album': album ?? 'Album ${albumId ?? id}',
      'album_id': albumId,
      'duration': 180000,
      'is_music': true,
    });

List<AlbumModel> _albums = [];
List<SongModel> _songs = [];

class _Library extends LibraryNotifier {
  @override
  LibraryState build() =>
      LibraryState(songs: _songs, filteredSongs: _songs, albums: _albums);
}

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
}

class _Player extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}

String _searchJson(String title, String artist) => jsonEncode({
  'releases': [
    {
      'id': 'rel-${title.hashCode}',
      'title': title,
      'score': 100,
      'artist-credit': [
        {'name': artist},
      ],
      'release-group': {'id': 'grp'},
    },
  ],
});

class _Rig {
  final Directory dir = Directory.systemTemp.createTempSync('wavvy_art_ui');
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request) handler = (r) async =>
      http.Response('', 404);

  /// Ids MediaStore "has art" for.
  final withArt = <int>{};
  Future<void> Function()? onGate;

  _Rig() {
    handler = (r) async {
      if (r.url.host == 'musicbrainz.org') {
        final q = r.url.queryParameters['query']!;
        final m = RegExp(r'release:"(.*)" AND artist:"(.*)"').firstMatch(q)!;
        return http.Response(_searchJson(m[1]!, m[2]!), 200);
      }
      return http.Response.bytes(
        _png,
        200,
        headers: {'content-type': 'image/png'},
      );
    };
  }

  List<Override> overrides({
    bool settingOn = true,
    List<Override> extra = const [],
  }) => [
    libraryProvider.overrideWith(_Library.new),
    playerProvider.overrideWith(_Player.new),
    settingsProvider.overrideWith(
      () => _Settings(SettingsState(fetchMissingArt: settingOn)),
    ),
    albumArtHttpClientProvider.overrideWithValue(
      MockClient((r) async {
        requests.add(r);
        return handler(r);
      }),
    ),
    albumArtUserAgentProvider.overrideWithValue(() async => 'Wavvy/test ( x )'),
    albumArtLimiterProvider.overrideWithValue(RateLimiter(sleep: (_) async {})),
    albumArtDirectoryProvider.overrideWithValue(
      () async => Directory('${dir.path}/album_art'),
    ),
    albumArtProbeProvider.overrideWithValue((id) async => withArt.contains(id)),
    albumArtForegroundGateProvider.overrideWithValue(
      () async => onGate?.call(),
    ),
    albumArtAutoDelayProvider.overrideWithValue(Duration.zero),
    ...extra,
  ];

  void dispose() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

void main() {
  late _Rig rig;
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    rig = _Rig();
    _albums = [_album(1), _album(2), _album(3)];
    _songs = [
      _song(11, albumId: 1),
      _song(12, albumId: 2),
      _song(13, albumId: 3),
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.lucasjosino.on_audio_query'),
          (call) async => null,
        );
  });
  tearDown(() => rig.dispose());

  ProviderContainer make({bool settingOn = true}) {
    final c = ProviderContainer(overrides: rig.overrides(settingOn: settingOn));
    addTearDown(c.dispose);
    return c;
  }

  group('batch', () {
    test('runs album by album with progress, then a summary', () async {
      final c = make();
      final seen = <ArtBatchState>[];
      c.listen(albumArtBatchProvider, (_, s) => seen.add(s));
      await c.read(albumArtBatchProvider.notifier).startManual();

      final end = c.read(albumArtBatchProvider);
      expect(end.status, ArtBatchStatus.done);
      expect((end.total, end.done, end.found), (3, 3, 3));
      expect(
        seen.map((s) => s.status),
        containsAllInOrder([
          ArtBatchStatus.scanning,
          ArtBatchStatus.running,
          ArtBatchStatus.done,
        ]),
      );
      // 0, 1, 2 and 3 done were all shown.
      expect(
        seen
            .where((s) => s.status == ArtBatchStatus.running)
            .map((s) => s.done),
        [0, 1, 2, 3],
      );
      expect(artBatchReadout(end), 'Done: 3 of 3 albums got a cover');
      expect(
        artBatchReadout(
          const ArtBatchState(
            status: ArtBatchStatus.running,
            total: 48,
            done: 12,
            found: 9,
          ),
        ),
        '12 of 48 albums, 9 found',
      );
      // The covers are in the index and on disk.
      expect(c.read(albumArtIndexProvider).keys, containsAll(['id1', 'id2']));
      expect(rig.requests.every((r) => r.url.scheme == 'https'), isTrue);
    });

    test('skips albums with art, unknown tags and various artists', () async {
      _albums = [
        _album(1),
        _album(2),
        _album(3, name: '<unknown>'),
        _album(4, artist: 'Various Artists'),
        _album(5, artist: '<unknown>'),
      ];
      rig.withArt.add(2);
      final c = make();
      await c.read(albumArtBatchProvider.notifier).startManual();
      expect(c.read(albumArtBatchProvider).total, 1);
      final searched = rig.requests
          .where((r) => r.url.host == 'musicbrainz.org')
          .map((r) => r.url.queryParameters['query']);
      expect(searched, ['release:"Album 1" AND artist:"Artist 1"']);
    });

    test('skips albums that are cached or recently missed', () async {
      final c = make();
      final cache = c.read(albumArtCacheProvider);
      await cache.load();
      await cache.store('id1', _png, 'png');
      await cache.recordMiss('id2');
      await c.read(albumArtBatchProvider.notifier).startManual();
      final end = c.read(albumArtBatchProvider);
      expect((end.total, end.found), (1, 1));
    });

    test('a plain miss goes on and is remembered', () async {
      rig.handler = (r) async => r.url.host == 'musicbrainz.org'
          ? http.Response(jsonEncode({'releases': []}), 200)
          : http.Response('', 404);
      final c = make();
      await c.read(albumArtBatchProvider.notifier).startManual();
      final end = c.read(albumArtBatchProvider);
      expect((end.status, end.done, end.found), (ArtBatchStatus.done, 3, 0));
      final before = rig.requests.length;
      // Run again: nothing is asked a second time.
      await c.read(albumArtBatchProvider.notifier).startManual();
      expect(rig.requests.length, before);
      expect(c.read(albumArtBatchProvider).total, 0);
      expect(
        artBatchReadout(c.read(albumArtBatchProvider)),
        'No albums need a cover',
      );
    });

    test(
      'Cancel stops after the current album and keeps what was found',
      () async {
        final c = make();
        final n = c.read(albumArtBatchProvider.notifier);
        var gates = 0;
        rig.onGate = () async {
          if (++gates == 2) n.cancel();
        };
        await n.startManual();
        final end = c.read(albumArtBatchProvider);
        expect(end.status, ArtBatchStatus.cancelled);
        expect((end.done, end.found), (1, 1));
        expect(artBatchReadout(end), startsWith('Cancelled: 1 of 3'));
      },
    );

    test('running twice at once is one run', () async {
      final c = make();
      final n = c.read(albumArtBatchProvider.notifier);
      final a = n.startManual();
      final b = n.startManual();
      await Future.wait([a, b]);
      expect(
        rig.requests.where((r) => r.url.host == 'musicbrainz.org').length,
        3,
      );
      // And again afterwards: everything is cached, nothing to do.
      await n.startManual();
      expect(
        rig.requests.where((r) => r.url.host == 'musicbrainz.org').length,
        3,
      );
    });

    test('offline stops the batch; no retry storm from the auto run', () async {
      rig.handler = (r) async => throw const SocketException('down');
      final c = make();
      final n = c.read(albumArtBatchProvider.notifier);
      await n.startAuto();
      final end = c.read(albumArtBatchProvider);
      expect(end.status, ArtBatchStatus.stopped);
      expect(end.stopReason, ArtFetch.offline);
      expect(end.done, 1);
      expect(rig.requests.length, 1);
      expect(artBatchReadout(end), startsWith('Stopped, no connection'));

      await n.startAuto(); // quiet for a while
      expect(rig.requests.length, 1);
    });

    test('503 stops the batch', () async {
      rig.handler = (r) async => http.Response('busy', 503);
      final c = make();
      await c.read(albumArtBatchProvider.notifier).startManual();
      final end = c.read(albumArtBatchProvider);
      expect(
        (end.status, end.stopReason),
        (ArtBatchStatus.stopped, ArtFetch.rateLimited),
      );
      expect(rig.requests.length, 1);
    });

    test('with the setting off nothing runs, manual or automatic', () async {
      final c = make(settingOn: false);
      final n = c.read(albumArtBatchProvider.notifier);
      await n.startManual();
      await n.startAuto();
      c.read(albumArtAutoProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(albumArtBatchProvider).status, ArtBatchStatus.idle);
      expect(rig.requests, isEmpty);
    });

    test('with the setting on, a library load starts a small batch', () async {
      final c = make();
      c.read(albumArtAutoProvider);
      for (var i = 0; i < 1000; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (c.read(albumArtBatchProvider).status == ArtBatchStatus.done) break;
      }
      expect(c.read(albumArtBatchProvider).found, 3);
    });

    test('an automatic run is limited to one small batch', () async {
      _albums = [for (var i = 1; i <= kAutoArtBatch + 5; i++) _album(i)];
      final c = make();
      final n = c.read(albumArtBatchProvider.notifier);
      await n.startAuto();
      expect(c.read(albumArtBatchProvider).total, kAutoArtBatch);
      // Stop the follow-up timer.
      n.cancel();
    });

    test('the explicit per-album lookup works with the setting off', () async {
      final c = make(settingOn: false);
      final r = await c
          .read(albumArtFinderProvider)
          .fetch(albumRefForAlbum(_album(1)), force: true);
      expect(r, ArtFetch.found);
      expect(c.read(albumArtIndexProvider).containsKey('id1'), isTrue);
      // Removing the fetched cover.
      await c.read(albumArtIndexProvider.notifier).remove('id1');
      expect(c.read(albumArtIndexProvider).containsKey('id1'), isFalse);
    });
  });

  group('fallback widget', () {
    Widget app(Widget child) => MaterialApp(
      theme: WavvyTheme.light(WvAppearance.green),
      home: Scaffold(body: Center(child: child)),
    );

    Future<ProviderContainer> pumpWith(
      WidgetTester tester,
      Widget child,
    ) async {
      // The index loads real files: start that outside the fake-async zone.
      final c = ProviderContainer(overrides: rig.overrides(settingOn: false));
      addTearDown(c.dispose);
      await tester.runAsync(() async {
        c.read(albumArtIndexProvider);
        await c.read(albumArtCacheProvider).load();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: app(child)),
      );
      await tester.pump();
      return c;
    }

    testWidgets('shows the cached cover, else the placeholder', (tester) async {
      Directory('${rig.dir.path}/album_art').createSync(recursive: true);
      // Album 1 has a cached cover; album 2 has none.
      File('${rig.dir.path}/album_art/id1.png').writeAsBytesSync(_png);

      await pumpWith(
        tester,
        const Column(
          children: [
            AlbumArtFallback(id: 1, type: ArtworkType.ALBUM, size: 40, seed: 1),
            AlbumArtFallback(id: 2, type: ArtworkType.ALBUM, size: 40, seed: 2),
            // A song of album 1, and a song of album 2.
            AlbumArtFallback(
              id: 11,
              type: ArtworkType.AUDIO,
              size: 40,
              seed: 11,
            ),
            AlbumArtFallback(
              id: 12,
              type: ArtworkType.AUDIO,
              size: 40,
              seed: 12,
            ),
            // A song that is not in the library.
            AlbumArtFallback(
              id: 99,
              type: ArtworkType.AUDIO,
              size: 40,
              seed: 99,
            ),
          ],
        ),
      );
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byType(WvMediaPlaceholder), findsNWidgets(3));
      // A row never asks the network.
      expect(rig.requests, isEmpty);
    });

    testWidgets('shows the placeholder before the index is loaded', (
      tester,
    ) async {
      Directory('${rig.dir.path}/album_art').createSync(recursive: true);
      File('${rig.dir.path}/album_art/id1.png').writeAsBytesSync(_png);
      await tester.pumpWidget(
        ProviderScope(
          overrides: rig.overrides(settingOn: false),
          child: app(
            const AlbumArtFallback(
              id: 1,
              type: ArtworkType.ALBUM,
              size: 40,
              seed: 1,
            ),
          ),
        ),
      );
      expect(find.byType(WvMediaPlaceholder), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a cover fetched later replaces the placeholder', (
      tester,
    ) async {
      final c = await pumpWith(
        tester,
        const AlbumArtFallback(
          id: 1,
          type: ArtworkType.ALBUM,
          size: 40,
          seed: 1,
        ),
      );
      expect(find.byType(WvMediaPlaceholder), findsOneWidget);
      await tester.runAsync(() async {
        await c
            .read(albumArtFinderProvider)
            .fetch(albumRefForAlbum(_album(1)), force: true);
      });
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(WvMediaPlaceholder), findsNothing);

      await tester.runAsync(
        () => c.read(albumArtIndexProvider.notifier).remove('id1'),
      );
      await tester.pump();
      expect(find.byType(WvMediaPlaceholder), findsOneWidget);
    });
  });

  group('settings', () {
    test('the setting is off by default and persists under its key', () async {
      expect(const SettingsState().fetchMissingArt, isFalse);
      final prefs = SharedPreferencesAsync();
      expect(await prefs.getBool('feature_fetch_missing_art'), isNull);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(settingsProvider.notifier).toggleFetchMissingArt(true);
      expect(c.read(settingsProvider).fetchMissingArt, isTrue);
      expect(await prefs.getBool('feature_fetch_missing_art'), isTrue);
      await c.read(settingsProvider.notifier).toggleFetchMissingArt(false);
      expect(await prefs.getBool('feature_fetch_missing_art'), isFalse);
    });

    Future<ProviderContainer> pumpSettings(
      WidgetTester tester, {
      required bool on,
    }) async {
      tester.view.physicalSize = const Size(411 * 2, 4000 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: rig.overrides(settingOn: on),
          child: MaterialApp(
            theme: WavvyTheme.light(WvAppearance.green),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      return ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
    }

    testWidgets('toggle with an honest description; the row only when on', (
      tester,
    ) async {
      await pumpSettings(tester, on: false);
      expect(find.text('Find missing album covers'), findsOneWidget);
      expect(
        find.textContaining('Only the album and artist names are sent'),
        findsOneWidget,
      );
      expect(find.textContaining('MusicBrainz'), findsOneWidget);
      expect(find.text('Find missing artwork'), findsNothing);
    });

    testWidgets('the row runs the scan and shows progress and Cancel', (
      tester,
    ) async {
      final gate = Completer<void>();
      rig.onGate = () => gate.future;
      final c = await pumpSettings(tester, on: true);
      expect(find.text('Find missing artwork'), findsOneWidget);
      expect(
        find.text('Look up covers for albums that have none'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        unawaited(c.read(albumArtBatchProvider.notifier).startManual());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('0 of 3 albums, 0 found'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      gate.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('Cancel'), findsNothing);
      expect(c.read(albumArtBatchProvider).status, ArtBatchStatus.cancelled);
      expect(find.textContaining('Cancelled: 0 of 3'), findsOneWidget);
    });
  });

  test('cached cover as bytes is null when there is none', () async {
    final c = make();
    final out = Completer<Uint8List?>();
    final p = Provider<int>((ref) {
      cachedArtThumbForSong(ref, 11).then(out.complete);
      return 0;
    });
    c.read(p);
    expect(await out.future, isNull);
  });
}
