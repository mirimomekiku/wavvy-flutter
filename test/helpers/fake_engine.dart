import 'dart:async';

import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/engine.dart';
import 'package:wavvy/downloader/models.dart';

/// A yt-dlp engine that does nothing real: tests script what it returns and
/// inspect what it was asked to do.
class FakeYtDlpEngine implements YtDlpEngine {
  EngineStatus current = const EngineStatus(
    EngineState.ready,
    version: '2026.01.01',
  );
  EngineStatus afterInstall = const EngineStatus(
    EngineState.ready,
    version: '2026.02.02',
  );
  DownloaderException? installError;
  Completer<void>? installGate;

  List<MediaInfo> searchResults = const [];
  MediaInfo? resolved;
  DownloaderException? lookupError;

  /// When set, search waits for this (to test out-of-order answers).
  Completer<List<MediaInfo>>? searchGate;

  DownloaderException? downloadError;
  DownloaderException? publishError;
  String publishUri = 'content://media/external_primary/audio/media/42';
  PendingWork pendingWork = const PendingWork();

  final installs = <int>[];
  final searches = <String>[];
  final resolves = <String>[];
  final started = <DownloadRequest>[];
  final canceled = <String>[];
  final published = <(String, String)>[];
  final acked = <String>[];

  final _events = StreamController<EngineEvent>.broadcast(sync: true);
  void emit(EngineEvent event) => _events.add(event);

  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  Future<EngineStatus> status() async => current;

  @override
  Future<EngineStatus> install() async {
    installs.add(installs.length);
    emit(const EngineProgress('starting'));
    if (installGate != null) await installGate!.future;
    emit(const EngineProgress('downloading'));
    if (installError != null) throw installError!;
    current = afterInstall;
    return current;
  }

  @override
  Future<MediaInfo> resolve(String url) async {
    resolves.add(url);
    if (lookupError != null) throw lookupError!;
    return resolved!;
  }

  @override
  Future<List<MediaInfo>> search(String query, {int count = 15}) async {
    searches.add(query);
    if (lookupError != null) throw lookupError!;
    if (searchGate != null) return searchGate!.future;
    return searchResults;
  }

  @override
  Future<void> download(DownloadRequest request) async {
    if (downloadError != null) throw downloadError!;
    started.add(request);
  }

  @override
  Future<void> cancel(String id) async => canceled.add(id);

  @override
  Future<String> publish(String path, String displayName) async {
    published.add((path, displayName));
    if (publishError != null) throw publishError!;
    return publishUri;
  }

  @override
  Future<PendingWork> pending() async => pendingWork;

  @override
  Future<void> ack(String id) async => acked.add(id);
}

/// Download tasks kept in memory.
class FakeDownloadStore implements DownloadStore {
  FakeDownloadStore([Iterable<DownloadTask> initial = const []])
    : tasks = {for (final t in initial) t.id: t};

  final Map<String, DownloadTask> tasks;

  @override
  Future<List<DownloadTask>> load() async => tasks.values.toList();

  @override
  Future<void> save(DownloadTask task) async => tasks[task.id] = task;

  @override
  Future<void> delete(String id) async => tasks.remove(id);
}

MediaInfo fakeMedia(
  String id, {
  String title = 'A song',
  String artist = 'An artist',
  int seconds = 200,
}) => MediaInfo(
  id: id,
  title: title,
  artist: artist,
  thumbnail: '',
  url: 'https://www.youtube.com/watch?v=$id',
  durationSeconds: seconds,
);

DownloadTask fakeTask(
  String id, {
  DownloadStatus status = DownloadStatus.queued,
  int progress = 0,
  String title = 'A song',
  String error = '',
  String mediaUri = '',
  String filePath = '',
}) => DownloadTask(
  id: id,
  url: 'https://www.youtube.com/watch?v=v$id',
  videoId: 'v$id',
  title: title,
  artist: 'An artist',
  status: status,
  progress: progress,
  error: error,
  mediaUri: mediaUri,
  filePath: filePath,
  createdAt: DateTime(2026, 1, 1).add(Duration(minutes: int.tryParse(id) ?? 0)),
);
