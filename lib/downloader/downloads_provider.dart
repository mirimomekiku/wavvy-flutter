import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:metadata_god/metadata_god.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wavvy/core/media_store.dart';
import 'package:wavvy/db/db.dart';
import 'package:wavvy/downloader/engine.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/downloader/failure.dart';
import 'package:wavvy/downloader/models.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

/// Where download tasks are saved. Overridden in tests.
abstract class DownloadStore {
  Future<List<DownloadTask>> load();
  Future<void> save(DownloadTask task);
  Future<void> delete(String id);
}

class DbDownloadStore implements DownloadStore {
  final DbHelper _db = DbHelper();

  @override
  Future<List<DownloadTask>> load() async => [
    for (final row in await _db.downloadRows()) DownloadTask.fromRow(row),
  ];

  @override
  Future<void> save(DownloadTask task) => _db.saveDownload(task.toRow());

  @override
  Future<void> delete(String id) => _db.deleteDownload(id);
}

final downloadStoreProvider = Provider<DownloadStore>(
  (ref) => DbDownloadStore(),
);

/// The private folder downloads are made in before they are published.
final downloadDirectoryProvider = Provider<Future<String> Function()>(
  (ref) => () async {
    final base = await getApplicationSupportDirectory();
    return '${base.path}/downloads';
  },
);

/// Writes title, artist and cover into a downloaded file. Best effort: the
/// download is still usable without tags. Overridden in tests.
final tagWriterProvider =
    Provider<Future<void> Function(String path, DownloadTask task)>(
      (ref) => (path, task) async {
        Picture? cover;
        if (task.thumbnail.isNotEmpty) {
          try {
            final res = await http
                .get(Uri.parse(task.thumbnail))
                .timeout(const Duration(seconds: 10));
            if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
              cover = Picture(
                mimeType: res.headers['content-type'] ?? 'image/jpeg',
                data: res.bodyBytes,
              );
            }
          } catch (e) {
            debugPrint('cover download failed: $e');
          }
        }
        await MetadataGod.writeMetadata(
          file: path,
          metadata: Metadata(
            title: task.title,
            artist: task.artist.isEmpty ? null : task.artist,
            picture: cover,
          ),
        );
      },
    );

final downloadsProvider =
    NotifierProvider<DownloadsNotifier, List<DownloadTask>>(
      DownloadsNotifier.new,
    );

/// The download queue: starts downloads, follows their progress, and when a file
/// arrives tags it, adds it to the music library and refreshes the library.
class DownloadsNotifier extends Notifier<List<DownloadTask>> {
  YtDlpEngine get _engine => ref.read(ytDlpEngineProvider);
  DownloadStore get _store => ref.read(downloadStoreProvider);

  @override
  List<DownloadTask> build() {
    final sub = _engine.events.listen(_onEvent);
    ref.onDispose(sub.cancel);
    Future.microtask(_load);
    return const [];
  }

  // ---------------------------------------------------------------- Loading

  Future<void> _load() async {
    final saved = await _store.load();
    final known = {for (final t in saved) t.id};
    state = [...state.where((t) => !known.contains(t.id)), ...saved];

    PendingWork pending;
    try {
      pending = await _engine.pending();
    } on DownloaderException {
      pending = const PendingWork();
    }
    // Downloads that ended while the app was closed.
    for (final result in pending.results) {
      await _onEvent(result);
    }
    // Tasks the app thinks are running but nothing is working on.
    final handled = {for (final r in pending.results) r.id};
    for (final task in [...state]) {
      if (task.status.active &&
          !pending.activeIds.contains(task.id) &&
          !handled.contains(task.id)) {
        await _set(
          task.copyWith(
            status: DownloadStatus.failed,
            error: 'This download was interrupted. Try again.',
          ),
        );
      }
    }
  }

  // ----------------------------------------------------------------- Update

  DownloadTask? _find(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Replaces [task] in the list and saves it.
  Future<void> _set(DownloadTask task, {bool save = true}) async {
    state = [for (final t in state) t.id == task.id ? task : t];
    if (save) await _store.save(task);
  }

  // ----------------------------------------------------------------- Starting

  /// Queues [info]. A song that is already downloading or downloaded is not
  /// queued again; that task is returned.
  Future<DownloadTask> enqueue(MediaInfo info) async {
    for (final t in state) {
      if (t.videoId == info.id &&
          (t.status.active || t.status == DownloadStatus.complete)) {
        AppSnackbar.showSnackbar(
          t.status == DownloadStatus.complete
              ? 'Already downloaded'
              : 'Already queued',
          t.title,
        );
        return t;
      }
    }
    final task = DownloadTask(
      id: _newId(),
      url: info.url,
      videoId: info.id,
      title: info.title,
      artist: info.artist,
      thumbnail: info.thumbnail,
      durationSeconds: info.durationSeconds,
      createdAt: DateTime.now(),
    );
    state = [task, ...state];
    await _store.save(task);
    await _start(task);
    return task;
  }

  Future<void> _start(DownloadTask task) async {
    try {
      await _engine.download(
        DownloadRequest(
          id: task.id,
          url: task.url,
          videoId: task.videoId,
          title: task.title,
          dir: await ref.read(downloadDirectoryProvider)(),
          wifiOnly: ref.read(settingsProvider).downloadWifiOnly,
        ),
      );
    } on DownloaderException catch (e) {
      await _set(
        task.copyWith(status: DownloadStatus.failed, error: e.message),
      );
    }
  }

  static String _newId() {
    final r = Random.secure();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${r.nextInt(1 << 32).toRadixString(36)}';
  }

  /// Tries a failed or canceled download again. If the file was downloaded but
  /// could not be added to the library, only that step is repeated.
  Future<void> retry(String id) async {
    final task = _find(id);
    if (task == null || task.status.active) return;
    if (task.filePath.isNotEmpty && await File(task.filePath).exists()) {
      await _publish(task, task.filePath);
      return;
    }
    final fresh = task.copyWith(
      status: DownloadStatus.queued,
      progress: 0,
      error: '',
    );
    await _set(fresh);
    await _start(fresh);
  }

  Future<void> cancel(String id) async {
    final task = _find(id);
    if (task == null || !task.status.active) return;
    await _engine.cancel(id);
  }

  // ----------------------------------------------------------------- Events

  Future<void> _onEvent(EngineEvent event) async {
    if (event is! TaskEvent) return;
    final task = _find(event.id);
    if (task == null) {
      // Not ours (or already removed): just stop it being reported.
      await _engine.ack(event.id);
      return;
    }
    switch (event.status) {
      case DownloadStatus.queued:
      case DownloadStatus.running:
        // Progress is not saved on every tick.
        await _set(
          task.copyWith(
            status: DownloadStatus.running,
            progress: event.progress,
          ),
          save: task.status != DownloadStatus.running,
        );
      case DownloadStatus.complete:
        final path = event.path;
        if (path == null || path.isEmpty) {
          await _fail(
            task,
            'The download finished but produced no audio file.',
          );
        } else if (task.status != DownloadStatus.complete) {
          await _publish(task, path);
        }
      case DownloadStatus.failed:
        await _fail(task, describeDownloadFailure(event.error ?? ''));
      case DownloadStatus.canceled:
        await _set(task.copyWith(status: DownloadStatus.canceled, progress: 0));
        await _engine.ack(task.id);
      case DownloadStatus.publishing:
        break;
    }
  }

  Future<void> _fail(DownloadTask task, String message) async {
    await _set(task.copyWith(status: DownloadStatus.failed, error: message));
    await _engine.ack(task.id);
  }

  // ---------------------------------------------------------------- Publish

  /// The file name in the library: "Artist - Title" unless the title has it.
  String _displayName(DownloadTask task, String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot);
    final base =
        task.artist.isEmpty ||
            task.title.toLowerCase().contains(task.artist.toLowerCase())
        ? task.title
        : '${task.artist} - ${task.title}';
    return '${sanitizeFileName(base)}$ext';
  }

  Future<void> _publish(DownloadTask task, String path) async {
    var current = task.copyWith(
      status: DownloadStatus.publishing,
      progress: 100,
      filePath: path,
      error: '',
    );
    await _set(current);
    try {
      try {
        await ref.read(tagWriterProvider)(path, current);
      } catch (e) {
        debugPrint('tagging failed (the file is kept untagged): $e');
      }
      final uri = await _engine.publish(path, _displayName(current, path));
      current = current.copyWith(
        status: DownloadStatus.complete,
        mediaUri: uri,
        filePath: '',
      );
      await _set(current);
      await _engine.ack(task.id);
      AppSnackbar.showSuccess('Downloaded', task.title);
      await ref.read(libraryProvider.notifier).fetchAllSongs(silent: true);
    } on DownloaderException catch (e) {
      await _set(
        current.copyWith(
          status: DownloadStatus.failed,
          error: 'Could not add it to your music library: ${e.message}',
        ),
      );
    }
  }

  // ------------------------------------------------------- Open and delete

  /// The MediaStore id at the end of a content URI, or null.
  static int? mediaIdFromUri(String uri) => int.tryParse(uri.split('/').last);

  /// Plays a finished download. Returns false if it is not in the library yet.
  Future<bool> play(DownloadTask task) async {
    final id = mediaIdFromUri(task.mediaUri);
    if (id == null) return false;
    var songs = ref.read(libraryProvider).songs;
    if (!songs.any((s) => s.id == id)) {
      await ref.read(libraryProvider.notifier).fetchAllSongs(silent: true);
      songs = ref.read(libraryProvider).songs;
    }
    final song = songs.where((s) => s.id == id).firstOrNull;
    if (song == null) return false;
    await ref.read(playerProvider.notifier).playSong(song, contextList: [song]);
    return true;
  }

  /// Removes the task. With [deleteFile], a finished download's file is also
  /// deleted from the device (Android asks you to confirm).
  Future<void> remove(String id, {bool deleteFile = false}) async {
    final task = _find(id);
    if (task == null) return;
    if (task.status.active) await _engine.cancel(id);
    if (deleteFile && task.status == DownloadStatus.complete) {
      final mediaId = mediaIdFromUri(task.mediaUri);
      if (mediaId != null) {
        final deleted = await ref.read(mediaStoreProvider).deleteAudio(mediaId);
        if (!deleted) return; // The user declined: keep everything.
        ref.read(libraryProvider.notifier).removeSongLocally(mediaId);
      }
    }
    if (task.filePath.isNotEmpty) {
      try {
        await File(task.filePath).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
    state = [
      for (final t in state)
        if (t.id != id) t,
    ];
    await _store.delete(id);
  }

  /// Clears finished entries from the list (the files stay).
  Future<void> clearFinished() async {
    for (final t in [...state]) {
      if (!t.status.active) await remove(t.id);
    }
  }
}
