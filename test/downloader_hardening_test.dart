import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:on_audio_query/on_audio_query.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/downloader/cover.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/downloader/integrity.dart';
import 'package:wavvy/downloader/models.dart';
import 'package:wavvy/downloader/staging.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

import 'helpers/fake_engine.dart';

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _other =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

String _sums({String hash = _sha}) =>
    '$_other  yt-dlp.exe\n'
    '$hash  yt-dlp\n'
    '${_other.toUpperCase()} *yt-dlp_linux\n'
    'not a checksum line\n';

class _Library extends LibraryNotifier {
  @override
  LibraryState build() => const LibraryState();

  @override
  Future<void> fetchAllSongs({bool silent = false}) async {}

  @override
  void removeSongLocally(int songId) {}
}

class _Player extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> playSong(SongModel song, {List<SongModel>? contextList}) async {}
}

class _Settings extends SettingsNotifier {
  _Settings({this.downloader = true});
  final bool downloader;

  @override
  SettingsState build() => SettingsState(enableDownloader: downloader);
}

http.Client _sumsClient(
  String body, {
  int status = 200,
  List<Uri>? requested,
}) => MockClient((request) async {
  requested?.add(request.url);
  return http.Response(body, status);
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('SHA2-256SUMS', () {
    test('parses entries, binary markers and ignores other lines', () {
      final sums = parseSha256Sums(_sums());
      expect(sums['yt-dlp'], _sha);
      expect(sums['yt-dlp.exe'], _other);
      expect(sums['yt-dlp_linux'], _other); // lowercased, "*" dropped
      expect(sums, hasLength(3));
    });

    test('compares the yt-dlp entry', () {
      final sums = parseSha256Sums(_sums());
      expect(compareChecksum(sums, _sha), IntegrityResult.match);
      expect(compareChecksum(sums, _sha.toUpperCase()), IntegrityResult.match);
      expect(compareChecksum(sums, _other), IntegrityResult.mismatch);
      expect(
        compareChecksum({'yt-dlp.exe': _sha}, _sha),
        IntegrityResult.noEntry,
      );
    });

    test('only a release tag is put in the URL', () {
      expect(
        EngineIntegrity.sumsUri('2025.10.22').toString(),
        'https://github.com/yt-dlp/yt-dlp/releases/download/2025.10.22/'
        'SHA2-256SUMS',
      );
      expect(EngineIntegrity.sumsUri('../evil'), isNull);
      expect(EngineIntegrity.sumsUri('1/2'), isNull);
      expect(EngineIntegrity.sumsUri(''), isNull);
    });

    test('check: match, mismatch and a missing entry', () async {
      final requested = <Uri>[];
      Future<IntegrityResult> run(String body, String sha) => EngineIntegrity(
        client: _sumsClient(body, requested: requested),
      ).check('2025.10.22', sha);
      expect(await run(_sums(), _sha), IntegrityResult.match);
      expect(await run(_sums(), _other), IntegrityResult.mismatch);
      expect(
        await run('$_other  something-else\n', _sha),
        IntegrityResult.noEntry,
      );
      expect(requested.first.path, endsWith('/2025.10.22/SHA2-256SUMS'));
    });

    test('check: a failed or unusable fetch is unavailable', () async {
      Future<IntegrityResult> run(http.Client c, [String v = '2025.10.22']) =>
          EngineIntegrity(client: c).check(v, _sha);
      expect(
        await run(_sumsClient('', status: 404)),
        IntegrityResult.unavailable,
      );
      expect(
        await run(MockClient((_) async => throw const SocketException('no'))),
        IntegrityResult.unavailable,
      );
      // Not a tag: never even requested.
      final requested = <Uri>[];
      expect(
        await run(_sumsClient(_sums(), requested: requested), 'a/b'),
        IntegrityResult.unavailable,
      );
      expect(requested, isEmpty);
    });

    test('check: a huge body is not read to the end', () async {
      final big = MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          Stream.fromIterable(List.filled(10, List.filled(1024, 0x61))),
          200,
        );
      });
      expect(
        await EngineIntegrity(client: big, maxBytes: 4096).check('1', _sha),
        IntegrityResult.unavailable,
      );
    });
  });

  group('engine integrity flow', () {
    const channel = MethodChannel('com.mirimomekiku.wavvy/ytdlp');
    late List<String> calls;
    late Map<String, Object?> Function(String method) native;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return native(call.method);
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    PlatformYtDlpEngine engine(String sums, {int status = 200}) =>
        PlatformYtDlpEngine(
          integrity: EngineIntegrity(client: _sumsClient(sums, status: status)),
        );

    Map<String, Object?> unverified() => {
      'state': 'unverified',
      'version': '2025.10.22',
      'sha256': _sha,
    };

    test('a matching hash is trusted and the engine is ready', () async {
      native = (m) => switch (m) {
        'install' => unverified(),
        'trust' => {'state': 'ready', 'version': '2025.10.22'},
        _ => {},
      };
      final status = await engine(_sums()).install();
      expect(status.isReady, isTrue);
      expect(status.version, '2025.10.22');
      expect(calls, ['install', 'trust']);
    });

    test('a mismatch is refused and the file is distrusted', () async {
      native = (m) => m == 'install' ? unverified() : {};
      await expectLater(
        engine(_sums(hash: _other)).install(),
        throwsA(isA<IntegrityException>()),
      );
      expect(calls, ['install', 'distrust']);
    });

    test('sums that cannot be fetched fail closed', () async {
      native = (m) => m == 'install' ? unverified() : {};
      await expectLater(
        engine('', status: 503).install(),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.message,
            'message',
            contains('not used until it is verified'),
          ),
        ),
      );
      expect(calls, ['install', 'distrust']);
      expect(calls, isNot(contains('trust')));
    });

    test('a file that is already verified is not checked again', () async {
      native = (m) => {'state': 'ready', 'version': '2025.10.22'};
      final status = await engine('', status: 500).install();
      expect(status.isReady, isTrue);
      expect(calls, ['install']);
    });

    test('a file that changed since it was verified is a failure', () async {
      native = (m) => {
        'state': 'failed',
        'version': '2025.10.22',
        'message': 'yt-dlp changed since it was verified, so it was not run.',
      };
      final status = await engine(_sums()).status();
      expect(status.state, EngineState.failed);
      expect(status.message, contains('changed since it was verified'));
    });
  });

  group('engine provider', () {
    late FakeYtDlpEngine engine;
    late ProviderContainer container;

    ProviderContainer make({bool downloader = true}) => ProviderContainer(
      overrides: [
        ytDlpEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(() => _Settings(downloader: downloader)),
      ],
    );

    setUp(() => engine = FakeYtDlpEngine());
    tearDown(() => container.dispose());

    test(
      'a failed verification of an update leaves the engine failed',
      () async {
        engine.installError = const IntegrityException('Does not match.');
        container = make();
        container.read(engineProvider);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(engineProvider).isReady, isTrue);
        await container.read(engineProvider.notifier).install();
        final s = container.read(engineProvider);
        expect(s.state, EngineState.failed); // not "ready, update failed"
        expect(s.message, 'Does not match.');
      },
    );

    test('a failed verification of a first setup is a failure', () async {
      engine
        ..current = const EngineStatus(EngineState.missing)
        ..installError = const IntegrityException('Not verified.');
      container = make();
      container.read(engineProvider);
      await Future<void>.delayed(Duration.zero);
      await container.read(engineProvider.notifier).install();
      expect(container.read(engineProvider).state, EngineState.failed);
      expect(container.read(engineProvider).message, 'Not verified.');
    });

    test('the daily update runs when the downloader is on', () async {
      container = make();
      container.read(engineProvider);
      await Future<void>.delayed(Duration.zero);
      await container.read(engineProvider.notifier).updateIfDue();
      expect(engine.installs, hasLength(1));
    });

    test('the daily update does not run when the downloader is off', () async {
      container = make(downloader: false);
      container.read(engineProvider);
      await Future<void>.delayed(Duration.zero);
      await container.read(engineProvider.notifier).updateIfDue();
      expect(engine.installs, isEmpty);
    });
  });

  group('downloads', () {
    late FakeYtDlpEngine engine;
    late FakeDownloadStore store;
    late Directory staging;
    late List<String> tagged;
    late ProviderContainer container;

    setUp(() {
      staging = Directory.systemTemp.createTempSync('wavvy_staging');
    });
    tearDown(() {
      container.dispose();
      staging.deleteSync(recursive: true);
    });

    ProviderContainer make([Iterable<DownloadTask> tasks = const []]) {
      engine = FakeYtDlpEngine();
      store = FakeDownloadStore(tasks);
      tagged = [];
      return container = ProviderContainer(
        overrides: [
          ytDlpEngineProvider.overrideWithValue(engine),
          downloadStoreProvider.overrideWithValue(store),
          downloadDirectoryProvider.overrideWithValue(() async => staging.path),
          tagWriterProvider.overrideWithValue((path, task) async {
            tagged.add(path);
          }),
          libraryProvider.overrideWith(_Library.new),
          playerProvider.overrideWith(_Player.new),
          settingsProvider.overrideWith(_Settings.new),
        ],
      );
    }

    Future<void> start() async {
      container.read(downloadsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    TaskEvent complete(String id, String path) => TaskEvent(
      id: id,
      status: DownloadStatus.complete,
      progress: 100,
      path: path,
    );

    test('a result delivered twice is published once', () async {
      make([fakeTask('1', status: DownloadStatus.running)]);
      await start();
      final gate = Completer<void>();
      engine.publishGate = gate;
      final path = '${staging.path}/wv1.m4a';
      engine.emit(complete('1', path)); // live
      engine.emit(complete('1', path)); // replayed
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(engine.published, hasLength(1));
      expect(tagged, hasLength(1));
      expect(
        container.read(downloadsProvider).single.status,
        DownloadStatus.complete,
      );
    });

    test('a task left publishing by a crash is published again', () async {
      final path = '${staging.path}/wv1.m4a';
      make([fakeTask('1', status: DownloadStatus.publishing, filePath: path)]);
      engine.pendingWork = PendingWork(results: [complete('1', path)]);
      await start();
      expect(engine.published, hasLength(1));
      expect(
        container.read(downloadsProvider).single.status,
        DownloadStatus.complete,
      );
    });

    test('a result for an unknown task deletes its staged file', () async {
      make();
      await start();
      final file = File('${staging.path}/wv9.m4a')..writeAsStringSync('x');
      engine.emit(complete('9', file.path));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(file.existsSync(), isFalse);
      expect(engine.acked, contains('9'));
      expect(engine.published, isEmpty);
    });

    test('a result path outside the staging folder is left alone', () async {
      make();
      await start();
      final outside = Directory.systemTemp.createTempSync('wavvy_outside');
      addTearDown(() => outside.deleteSync(recursive: true));
      final file = File('${outside.path}/keep.m4a')..writeAsStringSync('x');
      engine.emit(complete('9', file.path));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(file.existsSync(), isTrue);
      expect(engine.acked, contains('9'));
    });

    test('startup sweeps old orphans and keeps what is needed', () async {
      final old = DateTime.now().subtract(const Duration(days: 3));
      File write(String name, DateTime modified) =>
          File('${staging.path}${Platform.pathSeparator}$name')
            ..writeAsStringSync('x')
            ..setLastModifiedSync(modified);
      final orphan = write('wvold.m4a.part', old);
      final fresh = write('wvnew.m4a.part', DateTime.now());
      final needed = write('wvkeep.m4a', old);
      make([
        fakeTask('1', status: DownloadStatus.failed, filePath: needed.path),
      ]);
      await start();
      expect(orphan.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(needed.existsSync(), isTrue);
    });
  });

  group('staging', () {
    final now = DateTime(2026, 6, 10);
    StagedFile f(String p, int hoursOld) =>
        (path: p, modified: now.subtract(Duration(hours: hoursOld)));

    test('only old files nothing needs are orphans', () {
      final orphans = orphanedStagingFiles(
        [f('a', 30), f('b', 2), f('c', 100), f('d', 24)],
        keep: {'c'},
        now: now,
      );
      expect(orphans, ['a', 'd']);
    });

    test('a path that climbs out of the folder is not inside it', () async {
      final dir = Directory.systemTemp.createTempSync('wavvy_in');
      addTearDown(() => dir.deleteSync(recursive: true));
      final inside = File('${dir.path}/a.m4a')..writeAsStringSync('x');
      final sibling = File('${dir.path}-sibling.m4a')..writeAsStringSync('x');
      addTearDown(sibling.deleteSync);
      expect(await isInsideStaging(inside.path, dir.path), isTrue);
      expect(await isInsideStaging(sibling.path, dir.path), isFalse);
      expect(
        await isInsideStaging(
          '${dir.path}/../${sibling.uri.pathSegments.last}',
          dir.path,
        ),
        isFalse,
      );
      expect(await isInsideStaging('${dir.path}/missing', dir.path), isFalse);
    });
  });

  group('cover policy', () {
    test('only https and public hosts are allowed', () {
      for (final ok in [
        'https://i.ytimg.com/vi/x/hq.jpg',
        'https://8.8.8.8/a.jpg',
      ]) {
        expect(isAllowedCoverUrl(ok), isTrue, reason: ok);
      }
      for (final bad in [
        'http://i.ytimg.com/vi/x/hq.jpg',
        'ftp://i.ytimg.com/a.jpg',
        'file:///etc/passwd',
        '',
        'not a url',
        'https://localhost/a.jpg',
        'https://intranet/a.jpg',
        'https://printer.local/a.jpg',
        'https://a.localhost/a.jpg',
        'https://127.0.0.1/a.jpg',
        'https://10.1.2.3/a.jpg',
        'https://172.16.0.1/a.jpg',
        'https://172.31.255.1/a.jpg',
        'https://192.168.1.1/a.jpg',
        'https://169.254.169.254/latest/meta-data',
        'https://100.64.0.1/a.jpg',
        'https://0.0.0.0/a.jpg',
        'https://[::1]/a.jpg',
        'https://[fe80::1]/a.jpg',
        'https://[fd00::1]/a.jpg',
        'https://[::ffff:10.0.0.1]/a.jpg',
        'https://user:pw@i.ytimg.com/a.jpg',
      ]) {
        expect(isAllowedCoverUrl(bad), isFalse, reason: bad);
      }
      expect(isAllowedCoverUrl('https://172.32.0.1/a.jpg'), isTrue);
    });

    Future<List<InternetAddress>> publicHost(String _) async => [
      InternetAddress('93.184.216.34'),
    ];

    http.Client images({
      int status = 200,
      String type = 'image/png',
      List<int>? bytes,
      int? length,
      List<Uri>? requested,
    }) => MockClient.streaming((request, _) async {
      requested?.add(request.url);
      final body = bytes ?? List.filled(100, 7);
      return http.StreamedResponse(
        Stream.value(body),
        status,
        contentLength: length ?? body.length,
        headers: {'content-type': type},
      );
    });

    test('fetches a small image', () async {
      final image = await fetchCover(
        'https://i.ytimg.com/a.png',
        client: images(),
        resolve: publicHost,
      );
      expect(image, isNotNull);
      expect(image!.mime, 'image/png');
      expect(image.bytes, hasLength(100));
    });

    test('refuses http and private hosts without a request', () async {
      final requested = <Uri>[];
      final client = images(requested: requested);
      for (final url in [
        'http://i.ytimg.com/a.png',
        'https://127.0.0.1/a.png',
        'https://169.254.169.254/a.png',
        'https://localhost/a.png',
      ]) {
        expect(
          await fetchCover(url, client: client, resolve: publicHost),
          isNull,
          reason: url,
        );
      }
      expect(requested, isEmpty);
    });

    test('refuses a name that resolves to a private address', () async {
      final requested = <Uri>[];
      final image = await fetchCover(
        'https://evil.example.com/a.png',
        client: images(requested: requested),
        resolve: (_) async => [
          InternetAddress('93.184.216.34'),
          InternetAddress('10.0.0.5'),
        ],
      );
      expect(image, isNull);
      expect(requested, isEmpty);
    });

    test('a redirect to a private address is refused', () async {
      final requested = <Uri>[];
      final client = MockClient.streaming((request, _) async {
        requested.add(request.url);
        return http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {'location': 'https://192.168.0.1/a.png'},
        );
      });
      expect(
        await fetchCover(
          'https://i.ytimg.com/a.png',
          client: client,
          resolve: publicHost,
        ),
        isNull,
      );
      expect(requested, hasLength(1));
    });

    test('a redirect to another public host is followed', () async {
      var hop = 0;
      final client = MockClient.streaming((request, _) async {
        if (hop++ == 0) {
          return http.StreamedResponse(
            const Stream.empty(),
            301,
            headers: {'location': '/moved.png'},
          );
        }
        expect(request.url.path, '/moved.png');
        return http.StreamedResponse(
          Stream.value([1, 2, 3]),
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      });
      final image = await fetchCover(
        'https://i.ytimg.com/a.png',
        client: client,
        resolve: publicHost,
      );
      expect(image?.bytes, [1, 2, 3]);
    });

    test('an oversize image is refused by length and by stream', () async {
      expect(
        await fetchCover(
          'https://i.ytimg.com/a.png',
          client: images(length: 10 << 20, bytes: [1]),
          resolve: publicHost,
          maxBytes: 1024,
        ),
        isNull,
      );
      // A server that lies about (or leaves out) the length.
      var read = 0;
      final lying = MockClient.streaming((request, _) async {
        final chunks = Stream.fromIterable(
          Iterable.generate(100, (_) {
            read++;
            return List.filled(100, 1);
          }),
        );
        return http.StreamedResponse(
          chunks,
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      expect(
        await fetchCover(
          'https://i.ytimg.com/a.png',
          client: lying,
          resolve: publicHost,
          maxBytes: 1000,
        ),
        isNull,
      );
      expect(read, lessThan(100)); // stopped early
    });

    test('errors and odd answers give null, never an exception', () async {
      Future<CoverImage?> run(http.Client c) => fetchCover(
        'https://i.ytimg.com/a.png',
        client: c,
        resolve: publicHost,
      );
      expect(await run(images(status: 404)), isNull);
      expect(await run(images(type: 'text/html')), isNull);
      expect(await run(images(bytes: [])), isNull);
      expect(
        await run(MockClient((_) async => throw const SocketException('x'))),
        isNull,
      );
      expect(
        await fetchCover(
          'https://i.ytimg.com/a.png',
          client: images(),
          resolve: (_) async => throw const SocketException('dns'),
        ),
        isNull,
      );
    });
  });
}
