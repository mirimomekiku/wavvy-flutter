import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:wavvy/downloader/failure.dart';
import 'package:wavvy/downloader/models.dart';

/// The downloader's engine (yt-dlp) as the app sees it. The real one talks to
/// native code; tests use a fake.
abstract class YtDlpEngine {
  /// Whether the engine is set up, and which yt-dlp version it has.
  Future<EngineStatus> status();

  /// Sets the engine up, or updates it to the newest yt-dlp. The first time
  /// this downloads yt-dlp, so it needs a connection.
  Future<EngineStatus> install();

  /// Looks up one link. Throws [DownloaderException] when it can't be used.
  Future<MediaInfo> resolve(String url);

  /// Searches YouTube.
  Future<List<MediaInfo>> search(String query, {int count = 15});

  /// Starts downloading [request]'s audio. Progress and the result arrive as
  /// [TaskEvent]s on [events].
  Future<void> download(DownloadRequest request);

  Future<void> cancel(String id);

  /// Adds a finished file to the music library and returns where it is.
  Future<String> publish(String path, String displayName);

  /// Results of downloads that ended while nobody was listening, and the ids of
  /// downloads still running.
  Future<PendingWork> pending();

  /// Tells the engine a result was handled, so it stops reporting it.
  Future<void> ack(String id);

  Stream<EngineEvent> get events;
}

enum EngineState { unknown, missing, installing, ready, failed }

class EngineStatus {
  final EngineState state;
  final String? version;

  /// What is happening or went wrong, for the user.
  final String message;

  const EngineStatus(this.state, {this.version, this.message = ''});

  bool get isReady => state == EngineState.ready;
  bool get isBusy => state == EngineState.installing;
}

class DownloadRequest {
  final String id;
  final String url;
  final String videoId;
  final String title;

  /// Private folder the file is downloaded into.
  final String dir;
  final bool wifiOnly;

  const DownloadRequest({
    required this.id,
    required this.url,
    required this.videoId,
    required this.title,
    required this.dir,
    this.wifiOnly = false,
  });
}

sealed class EngineEvent {
  const EngineEvent();
}

/// Progress of setting the engine up: starting, downloading, ready.
class EngineProgress extends EngineEvent {
  final String phase;
  final String? version;
  const EngineProgress(this.phase, {this.version});
}

class TaskEvent extends EngineEvent {
  final String id;
  final DownloadStatus status;
  final int progress;

  /// The downloaded file, when [status] is complete.
  final String? path;
  final String? error;

  const TaskEvent({
    required this.id,
    required this.status,
    this.progress = 0,
    this.path,
    this.error,
  });
}

class PendingWork {
  final List<TaskEvent> results;
  final Set<String> activeIds;
  const PendingWork({this.results = const [], this.activeIds = const {}});
}

/// A failure with a message that is fit to show.
class DownloaderException implements Exception {
  final String message;
  const DownloaderException(this.message);

  @override
  String toString() => message;
}

/// The real engine: yt-dlp running in the app's native side (full flavor).
class PlatformYtDlpEngine implements YtDlpEngine {
  static const MethodChannel _channel = MethodChannel(
    'com.mirimomekiku.wavvy/ytdlp',
  );
  static const EventChannel _events = EventChannel(
    'com.mirimomekiku.wavvy/ytdlp_events',
  );

  Stream<EngineEvent>? _stream;

  @override
  Stream<EngineEvent> get events => _stream ??= _events
      .receiveBroadcastStream()
      .map(_parseEvent)
      .where((e) => e != null)
      .cast<EngineEvent>()
      .asBroadcastStream();

  static EngineEvent? _parseEvent(dynamic raw) {
    if (raw is! Map) return null;
    switch (raw['type']) {
      case 'engine':
        return EngineProgress(
          '${raw['phase']}',
          version: raw['version'] as String?,
        );
      case 'task':
        return _parseTask(raw);
    }
    return null;
  }

  static TaskEvent _parseTask(Map raw) => TaskEvent(
    id: '${raw['id']}',
    status: DownloadStatus.parse(raw['status'] as String?),
    progress: (raw['progress'] as num?)?.toInt() ?? 0,
    path: raw['path'] as String?,
    error: raw['error'] as String?,
  );

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw DownloaderException(describeDownloadFailure(e.message ?? e.code));
    } on MissingPluginException {
      throw const DownloaderException(
        'The downloader is not part of this version of Wavvy.',
      );
    }
  }

  EngineStatus _status(Map? raw) {
    if (raw == null) return const EngineStatus(EngineState.unknown);
    return EngineStatus(
      raw['state'] == 'ready' ? EngineState.ready : EngineState.missing,
      version: raw['version'] as String?,
    );
  }

  @override
  Future<EngineStatus> status() async => _status(await _call<Map>('status'));

  @override
  Future<EngineStatus> install() async => _status(await _call<Map>('install'));

  @override
  Future<MediaInfo> resolve(String url) async {
    final json = await _call<String>('resolve', {'url': url});
    try {
      return MediaInfo.fromJson(jsonDecode(json!) as Map<String, dynamic>);
    } catch (_) {
      throw const DownloaderException(
        'That link is not something the downloader can use.',
      );
    }
  }

  @override
  Future<List<MediaInfo>> search(String query, {int count = 15}) async {
    final json = await _call<String>('search', {
      'query': query,
      'count': count,
    });
    try {
      final data = jsonDecode(json!) as Map<String, dynamic>;
      return [
        for (final e in (data['entries'] as List? ?? const []))
          if (e is Map<String, dynamic>) MediaInfo.fromJson(e),
      ];
    } catch (_) {
      throw const DownloaderException('The search returned nothing usable.');
    }
  }

  @override
  Future<void> download(DownloadRequest r) => _call<void>('download', {
    'id': r.id,
    'url': r.url,
    'videoId': r.videoId,
    'title': r.title,
    'dir': r.dir,
    'wifiOnly': r.wifiOnly,
  });

  @override
  Future<void> cancel(String id) => _call<void>('cancel', {'id': id});

  @override
  Future<String> publish(String path, String displayName) async =>
      (await _call<String>('publish', {
        'path': path,
        'displayName': displayName,
      }))!;

  @override
  Future<PendingWork> pending() async {
    final raw = await _call<Map>('pending');
    if (raw == null) return const PendingWork();
    return PendingWork(
      results: [
        for (final r in (raw['results'] as List? ?? const []))
          if (r is Map) _parseTask(r),
      ],
      activeIds: {for (final id in (raw['active'] as List? ?? const [])) '$id'},
    );
  }

  @override
  Future<void> ack(String id) => _call<void>('ack', {'id': id});
}
