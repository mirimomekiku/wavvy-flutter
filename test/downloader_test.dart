import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/core/media_store.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/downloader/failure.dart';
import 'package:wavvy/downloader/models.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

import 'helpers/fake_engine.dart';

class _Library extends LibraryNotifier {
  _Library(this.songs);
  final List<SongModel> songs;
  int fetches = 0;
  final removed = <int>[];

  @override
  LibraryState build() => LibraryState(songs: songs, filteredSongs: songs);

  @override
  Future<void> fetchAllSongs({bool silent = false}) async => fetches++;

  @override
  void removeSongLocally(int songId) => removed.add(songId);
}

class _Player extends PlayerNotifier {
  final played = <int>[];

  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> playSong(SongModel song, {List<SongModel>? contextList}) async =>
      played.add(song.id);
}

class _Settings extends SettingsNotifier {
  _Settings(this.wifiOnly);
  final bool wifiOnly;

  @override
  SettingsState build() => SettingsState(downloadWifiOnly: wifiOnly);
}

class _MediaStore extends MediaStoreChannel {
  _MediaStore(this.allow);
  final bool allow;
  final deleted = <int>[];

  @override
  Future<bool> deleteAudio(int id) async {
    deleted.add(id);
    return allow;
  }
}

SongModel _song(int id) => SongModel({
  '_id': id,
  '_data': '/music/$id.m4a',
  '_uri': 'content://media/external/audio/media/$id',
  'title': 'Song $id',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  group('MediaInfo', () {
    test('reads a full yt-dlp video', () {
      final info = MediaInfo.fromJson(
        jsonDecode('''
{"id":"Z-48u_uWMHY","title":"Kendrick Lamar - Alright","uploader":"Kendrick Lamar",
 "duration":415,"thumbnail":"https://i.ytimg.com/vi/x/maxres.jpg",
 "webpage_url":"https://www.youtube.com/watch?v=Z-48u_uWMHY","extractor_key":"Youtube"}
''')
            as Map<String, dynamic>,
      );
      expect(info.id, 'Z-48u_uWMHY');
      expect(info.title, 'Kendrick Lamar - Alright');
      expect(info.artist, 'Kendrick Lamar');
      expect(info.durationSeconds, 415);
      expect(info.url, 'https://www.youtube.com/watch?v=Z-48u_uWMHY');
      expect(info.extractor, 'Youtube');
    });

    test('a flat search entry only needs an id', () {
      final info = MediaInfo.fromJson({
        'id': 'abc123',
        'title': 'A song',
        'channel': 'Some Channel',
        'duration': 200.0,
        'thumbnails': [
          {'url': 'https://t/small.jpg'},
          {'url': 'https://t/large.jpg'},
        ],
      });
      expect(info.url, 'https://www.youtube.com/watch?v=abc123');
      expect(info.thumbnail, 'https://t/large.jpg');
      expect(info.artist, 'Some Channel');
      expect(info.durationSeconds, 200);
    });

    test('prefers the track name and artist, and drops " - Topic"', () {
      final info = MediaInfo.fromJson({
        'id': 'x',
        'title': 'Official Video (4K)',
        'track': 'Real Title',
        'artist': 'The Band',
        'uploader': 'The Band - Topic',
      });
      expect(info.title, 'Real Title');
      expect(info.artist, 'The Band');
      expect(MediaInfo.cleanArtist('Someone - Topic'), 'Someone');
    });

    test('missing fields do not break it', () {
      final info = MediaInfo.fromJson({'id': 'x'});
      expect(info.title, 'Untitled');
      expect(info.artist, '');
      expect(info.durationSeconds, isNull);
    });

    test('tells links from searches', () {
      expect(MediaInfo.looksLikeUrl('https://youtu.be/abc'), isTrue);
      expect(MediaInfo.looksLikeUrl(' https://vm.tiktok.com/Zx/ '), isTrue);
      expect(MediaInfo.looksLikeUrl('lofi hip hop'), isFalse);
      expect(MediaInfo.looksLikeUrl('ftp://example.com/a'), isFalse);
      expect(MediaInfo.looksLikeUrl('https://localhost'), isFalse);
      expect(MediaInfo.looksLikeUrl('javascript:alert(1)'), isFalse);
    });
  });

  group('sanitizeFileName', () {
    test('removes characters Android does not allow', () {
      expect(sanitizeFileName('AC/DC: Back in Black?'), 'AC DC Back in Black');
      expect(sanitizeFileName('a<b>c|d"e'), 'a b c d e');
    });
    test('never returns a path or nothing', () {
      expect(sanitizeFileName('..'), 'download');
      expect(sanitizeFileName('   '), 'download');
      expect(sanitizeFileName('../../etc'), 'etc');
    });
    test('keeps long names within the byte limit in any script', () {
      for (final title in ['a' * 400, '中' * 200, '\u{1F3B5}' * 100]) {
        final name = sanitizeFileName(title);
        expect(utf8.encode(name).length, lessThanOrEqualTo(120));
        expect(name, isNotEmpty);
      }
      // Cut on a character boundary, never in the middle of one.
      final cut = sanitizeFileName('\u{1F3B5}' * 100);
      expect(cut.runes.every((r) => r == 0x1F3B5), isTrue);
    });
  });

  group('describeDownloadFailure', () {
    test('explains common failures', () {
      expect(
        describeDownloadFailure("ERROR: Sign in to confirm you're not a bot"),
        contains('not a bot'),
      );
      expect(
        describeDownloadFailure('ERROR: [youtube] x: Private video'),
        contains('private'),
      );
      expect(
        describeDownloadFailure('ERROR: Video unavailable'),
        contains('no longer available'),
      );
      expect(
        describeDownloadFailure('ERROR: Unsupported URL: https://x'),
        contains('not something'),
      );
      expect(
        describeDownloadFailure('Unable to download webpage: timed out'),
        contains('Could not reach'),
      );
      expect(
        describeDownloadFailure('HTTP Error 403: Forbidden'),
        contains('update the downloader'),
      );
    });
    test('falls back to the last line, cleaned up', () {
      expect(
        describeDownloadFailure('warning\nERROR: [generic] Something odd'),
        'Something odd',
      );
      expect(describeDownloadFailure(''), 'Unknown error');
      expect(describeDownloadFailure('x' * 300).length, lessThanOrEqualTo(140));
    });
  });

  test('a task survives a round trip through the database row', () {
    final task = fakeTask(
      '5',
      status: DownloadStatus.failed,
      error: 'oops',
      mediaUri: 'content://x/1',
    );
    final back = DownloadTask.fromRow(task.toRow());
    expect(back.id, '5');
    expect(back.status, DownloadStatus.failed);
    expect(back.error, 'oops');
    expect(back.mediaUri, 'content://x/1');
    expect(back.createdAt, task.createdAt);
    expect(DownloadStatus.parse('nonsense'), DownloadStatus.failed);
  });

  group('engine state', () {
    late FakeYtDlpEngine engine;
    late ProviderContainer container;
    ProviderContainer make() => ProviderContainer(
      overrides: [ytDlpEngineProvider.overrideWithValue(engine)],
    );

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      engine = FakeYtDlpEngine();
      container = make();
    });
    tearDown(() => container.dispose());

    EngineStatus status() => container.read(engineProvider);

    test('reads the engine status on start', () async {
      container.read(engineProvider);
      await Future<void>.delayed(Duration.zero);
      expect(status().isReady, isTrue);
      expect(status().version, '2026.01.01');
    });

    test('first setup goes installing, then ready', () async {
      engine.current = const EngineStatus(EngineState.missing);
      container.read(engineProvider);
      await Future<void>.delayed(Duration.zero);
      expect(status().state, EngineState.missing);

      final gate = Completer<void>();
      engine.installGate = gate;
      final done = container.read(engineProvider.notifier).install();
      await Future<void>.delayed(Duration.zero);
      expect(status().isBusy, isTrue);
      expect(status().message, 'Starting the engine…');
      gate.complete();
      await done;
      expect(status().isReady, isTrue);
      expect(status().version, '2026.02.02');
    });

    test('a failed first setup is a failure with the reason', () async {
      engine
        ..current = const EngineStatus(EngineState.missing)
        ..installError = const DownloaderException('No connection.');
      container.read(engineProvider);
      await Future<void>.delayed(Duration.zero);
      await container.read(engineProvider.notifier).install();
      expect(status().state, EngineState.failed);
      expect(status().message, 'No connection.');
    });

    test('a failed update keeps the working engine', () async {
      engine.installError = const DownloaderException('No connection.');
      container.read(engineProvider);
      await Future<void>.delayed(Duration.zero);
      await container.read(engineProvider.notifier).install();
      expect(status().isReady, isTrue);
      expect(status().version, '2026.01.01');
      expect(status().message, 'Update failed: No connection.');
    });

    test('only one setup runs at a time', () async {
      engine.current = const EngineStatus(EngineState.missing);
      container.read(engineProvider);
      await Future<void>.delayed(Duration.zero);
      final gate = Completer<void>();
      engine.installGate = gate;
      final notifier = container.read(engineProvider.notifier);
      final first = notifier.install();
      await Future<void>.delayed(Duration.zero);
      await notifier.install();
      gate.complete();
      await first;
      expect(engine.installs, hasLength(1));
    });

    test('updates yt-dlp at most once a day', () async {
      final notifier = container.read(engineProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await notifier.updateIfDue(); // never checked: due
      expect(engine.installs, hasLength(1));
      await notifier.updateIfDue(); // just checked: not due
      expect(engine.installs, hasLength(1));
    });

    test('does not update an engine that is not set up', () async {
      engine.current = const EngineStatus(EngineState.missing);
      final notifier = container.read(engineProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await notifier.updateIfDue();
      expect(engine.installs, isEmpty);
    });
  });

  group('downloads', () {
    late FakeYtDlpEngine engine;
    late FakeDownloadStore store;
    late _Library library;
    late _Player player;
    late _MediaStore mediaStore;
    late List<String> tagged;
    late ProviderContainer container;

    Future<ProviderContainer> make({
      bool wifiOnly = false,
      bool allowDelete = true,
      List<SongModel> songs = const [],
    }) async {
      engine = FakeYtDlpEngine();
      store = FakeDownloadStore();
      library = _Library(songs);
      player = _Player();
      mediaStore = _MediaStore(allowDelete);
      tagged = [];
      return ProviderContainer(
        overrides: [
          ytDlpEngineProvider.overrideWithValue(engine),
          downloadStoreProvider.overrideWithValue(store),
          downloadDirectoryProvider.overrideWithValue(() async => '/tmp/dl'),
          tagWriterProvider.overrideWithValue((path, task) async {
            tagged.add('$path|${task.title}');
          }),
          mediaStoreProvider.overrideWithValue(mediaStore),
          libraryProvider.overrideWith(() => library),
          playerProvider.overrideWith(() => player),
          settingsProvider.overrideWith(() => _Settings(wifiOnly)),
        ],
      );
    }

    Future<DownloadsNotifier> start() async {
      container.read(downloadsProvider);
      await Future<void>.delayed(Duration.zero);
      return container.read(downloadsProvider.notifier);
    }

    List<DownloadTask> tasks() => container.read(downloadsProvider);

    tearDown(() => container.dispose());

    test('enqueue saves the task and starts the engine', () async {
      container = await make(wifiOnly: true);
      final downloads = await start();
      final task = await downloads.enqueue(fakeMedia('abc', title: 'Alright'));
      expect(tasks().single.status, DownloadStatus.queued);
      expect(store.tasks[task.id]!.title, 'Alright');
      final request = engine.started.single;
      expect(request.id, task.id);
      expect(request.videoId, 'abc');
      expect(request.dir, '/tmp/dl');
      expect(request.wifiOnly, isTrue);
    });

    test('the same song is not queued twice', () async {
      container = await make();
      final downloads = await start();
      final first = await downloads.enqueue(fakeMedia('abc'));
      final second = await downloads.enqueue(fakeMedia('abc'));
      expect(second.id, first.id);
      expect(engine.started, hasLength(1));
      expect(tasks(), hasLength(1));
    });

    test('progress updates the task without saving every tick', () async {
      container = await make();
      final downloads = await start();
      final task = await downloads.enqueue(fakeMedia('abc'));
      engine.emit(
        TaskEvent(id: task.id, status: DownloadStatus.running, progress: 10),
      );
      await Future<void>.delayed(Duration.zero);
      expect(tasks().single.status, DownloadStatus.running);
      expect(store.tasks[task.id]!.status, DownloadStatus.running);
      engine.emit(
        TaskEvent(id: task.id, status: DownloadStatus.running, progress: 55),
      );
      await Future<void>.delayed(Duration.zero);
      expect(tasks().single.progress, 55);
      // The saved copy still has the earlier progress.
      expect(store.tasks[task.id]!.progress, 10);
    });

    test(
      'a finished file is tagged, published and the library refreshed',
      () async {
        container = await make();
        final downloads = await start();
        final task = await downloads.enqueue(
          fakeMedia('abc', title: 'Alright', artist: 'Kendrick Lamar'),
        );
        engine.emit(
          TaskEvent(
            id: task.id,
            status: DownloadStatus.complete,
            path: '/tmp/dl/abc.m4a',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(tagged, ['/tmp/dl/abc.m4a|Alright']);
        expect(engine.published.single.$1, '/tmp/dl/abc.m4a');
        expect(engine.published.single.$2, 'Kendrick Lamar - Alright.m4a');
        expect(tasks().single.status, DownloadStatus.complete);
        expect(tasks().single.mediaUri, engine.publishUri);
        expect(tasks().single.filePath, isEmpty);
        expect(store.tasks[task.id]!.status, DownloadStatus.complete);
        expect(engine.acked, contains(task.id));
        expect(library.fetches, 1);
      },
    );

    test('the file name does not repeat the artist', () async {
      container = await make();
      final downloads = await start();
      final task = await downloads.enqueue(
        fakeMedia(
          'abc',
          title: 'Kendrick Lamar - Alright',
          artist: 'Kendrick Lamar',
        ),
      );
      engine.emit(
        TaskEvent(
          id: task.id,
          status: DownloadStatus.complete,
          path: '/d/abc.webm',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(engine.published.single.$2, 'Kendrick Lamar - Alright.webm');
    });

    test('a tagging failure does not lose the download', () async {
      container = await make();
      // Replace the tag writer with one that throws.
      container.dispose();
      engine = FakeYtDlpEngine();
      store = FakeDownloadStore();
      container = ProviderContainer(
        overrides: [
          ytDlpEngineProvider.overrideWithValue(engine),
          downloadStoreProvider.overrideWithValue(store),
          downloadDirectoryProvider.overrideWithValue(() async => '/tmp/dl'),
          tagWriterProvider.overrideWithValue((p, t) async => throw 'no tags'),
          libraryProvider.overrideWith(() => _Library(const [])),
          settingsProvider.overrideWith(() => _Settings(false)),
        ],
      );
      final downloads = await start();
      final task = await downloads.enqueue(fakeMedia('abc'));
      engine.emit(
        TaskEvent(
          id: task.id,
          status: DownloadStatus.complete,
          path: '/d/abc.m4a',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(tasks().single.status, DownloadStatus.complete);
      expect(engine.published, hasLength(1));
    });

    test(
      'a publish failure keeps the file so retry only republishes',
      () async {
        container = await make();
        engine.publishError = const DownloaderException('disk full');
        final downloads = await start();
        final task = await downloads.enqueue(fakeMedia('abc'));
        engine.emit(
          TaskEvent(
            id: task.id,
            status: DownloadStatus.complete,
            path: '/d/abc.m4a',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(tasks().single.status, DownloadStatus.failed);
        expect(tasks().single.error, contains('disk full'));
        expect(tasks().single.filePath, '/d/abc.m4a');
        expect(engine.started, hasLength(1));
      },
    );

    test('a failure is saved with a readable reason', () async {
      container = await make();
      final downloads = await start();
      final task = await downloads.enqueue(fakeMedia('abc'));
      engine.emit(
        TaskEvent(
          id: task.id,
          status: DownloadStatus.failed,
          error: 'ERROR: Video unavailable',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(tasks().single.status, DownloadStatus.failed);
      expect(tasks().single.error, 'This video is no longer available.');
      expect(store.tasks[task.id]!.error, isNotEmpty);
      expect(engine.acked, contains(task.id));
    });

    test('retry starts a failed download again from the start', () async {
      container = await make();
      final downloads = await start();
      final task = await downloads.enqueue(fakeMedia('abc'));
      engine.emit(
        TaskEvent(
          id: task.id,
          status: DownloadStatus.failed,
          error: 'timed out',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await downloads.retry(task.id);
      expect(tasks().single.status, DownloadStatus.queued);
      expect(tasks().single.error, isEmpty);
      expect(engine.started, hasLength(2));
    });

    test(
      'cancel asks the engine, and the canceled event settles the task',
      () async {
        container = await make();
        final downloads = await start();
        final task = await downloads.enqueue(fakeMedia('abc'));
        await downloads.cancel(task.id);
        expect(engine.canceled, [task.id]);
        engine.emit(TaskEvent(id: task.id, status: DownloadStatus.canceled));
        await Future<void>.delayed(Duration.zero);
        expect(tasks().single.status, DownloadStatus.canceled);
      },
    );

    test('an engine error on start fails the task with its message', () async {
      container = await make();
      engine.downloadError = const DownloaderException('Nope.');
      final downloads = await start();
      await downloads.enqueue(fakeMedia('abc'));
      expect(tasks().single.status, DownloadStatus.failed);
      expect(tasks().single.error, 'Nope.');
    });

    test('events for unknown tasks are acknowledged and ignored', () async {
      container = await make();
      await start();
      engine.emit(
        const TaskEvent(
          id: 'ghost',
          status: DownloadStatus.complete,
          path: '/x',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(engine.acked, ['ghost']);
      expect(engine.published, isEmpty);
    });

    test(
      'on start, saved tasks load and results from while closed apply',
      () async {
        container = await make();
        store.tasks.addAll({
          '1': fakeTask('1', status: DownloadStatus.running),
          '2': fakeTask('2', status: DownloadStatus.running),
          '3': fakeTask('3', status: DownloadStatus.complete),
        });
        engine.pendingWork = const PendingWork(
          results: [
            TaskEvent(
              id: '1',
              status: DownloadStatus.complete,
              path: '/d/v1.m4a',
            ),
          ],
        );
        await start();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final byId = {for (final t in tasks()) t.id: t};
        expect(byId['1']!.status, DownloadStatus.complete);
        // Nothing is working on task 2, so it cannot stay "running".
        expect(byId['2']!.status, DownloadStatus.failed);
        expect(byId['2']!.error, contains('interrupted'));
        expect(byId['3']!.status, DownloadStatus.complete);
      },
    );

    test('a task the engine is still working on stays running', () async {
      container = await make();
      store.tasks['1'] = fakeTask('1', status: DownloadStatus.running);
      engine.pendingWork = const PendingWork(activeIds: {'1'});
      await start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(tasks().single.status, DownloadStatus.running);
    });

    test(
      'remove with deleteFile deletes the audio and drops the task',
      () async {
        container = await make();
        store.tasks['1'] = fakeTask(
          '1',
          status: DownloadStatus.complete,
          mediaUri: 'content://media/external_primary/audio/media/42',
        );
        final downloads = await start();
        await downloads.remove('1', deleteFile: true);
        expect(mediaStore.deleted, [42]);
        expect(library.removed, [42]);
        expect(tasks(), isEmpty);
        expect(store.tasks, isEmpty);
      },
    );

    test('if the user declines the delete, nothing changes', () async {
      container = await make(allowDelete: false);
      store.tasks['1'] = fakeTask(
        '1',
        status: DownloadStatus.complete,
        mediaUri: 'content://media/external_primary/audio/media/42',
      );
      final downloads = await start();
      await downloads.remove('1', deleteFile: true);
      expect(tasks(), hasLength(1));
      expect(store.tasks, hasLength(1));
    });

    test('plain remove keeps the file', () async {
      container = await make();
      store.tasks['1'] = fakeTask(
        '1',
        status: DownloadStatus.complete,
        mediaUri: 'content://media/external_primary/audio/media/42',
      );
      final downloads = await start();
      await downloads.remove('1');
      expect(mediaStore.deleted, isEmpty);
      expect(tasks(), isEmpty);
    });

    test('removing an active task cancels it first', () async {
      container = await make();
      final downloads = await start();
      final task = await downloads.enqueue(fakeMedia('abc'));
      await downloads.remove(task.id);
      expect(engine.canceled, [task.id]);
      expect(tasks(), isEmpty);
    });

    test('play finds the song by its id, whatever the URI form', () async {
      container = await make(songs: [_song(41), _song(42)]);
      store.tasks['1'] = fakeTask(
        '1',
        status: DownloadStatus.complete,
        mediaUri: 'content://media/external_primary/audio/media/42',
      );
      final downloads = await start();
      expect(await downloads.play(tasks().single), isTrue);
      expect(player.played, [42]);
    });

    test('play says so when the song is not in the library yet', () async {
      container = await make(songs: [_song(1)]);
      store.tasks['1'] = fakeTask(
        '1',
        status: DownloadStatus.complete,
        mediaUri: 'content://media/external_primary/audio/media/42',
      );
      final downloads = await start();
      expect(await downloads.play(tasks().single), isFalse);
      expect(library.fetches, 1); // It rescanned once before giving up.
    });
  });
}
