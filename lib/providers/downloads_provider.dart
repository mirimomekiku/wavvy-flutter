import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tiktok_scraper/enums.dart';
import 'package:tiktok_scraper/tiktok_scraper.dart';
import 'package:wavvy/utils/snackbar.utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// One progress message from the flutter_downloader background isolate.
class DownloadEvent {
  final String id;
  final DownloadTaskStatus status;
  final int progress;

  const DownloadEvent(this.id, this.status, this.progress);
}

/// Binds the 'downloader_send_port' IsolateNameServer port (see
/// main.dart's downloadCallback) and exposes the events as state. Port of
/// DownloadService. Creating this provider registers the port; release it in
/// ref.onDispose. Watch it from the app root so it lives for the whole app.
final downloadEventsProvider =
    NotifierProvider<DownloadEventsNotifier, DownloadEvent?>(
      DownloadEventsNotifier.new,
    );

class DownloadEventsNotifier extends Notifier<DownloadEvent?> {
  static const String _portName = 'downloader_send_port';

  @override
  DownloadEvent? build() {
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(_portName);
    final ok = IsolateNameServer.registerPortWithName(port.sendPort, _portName);

    ref.onDispose(() {
      IsolateNameServer.removePortNameMapping(_portName);
      port.close();
    });

    if (ok) {
      port.listen((dynamic data) {
        // data = [String id, int status, int progress]
        if (data is! List || data.length < 3) return;
        state = DownloadEvent(
          data[0] as String,
          DownloadTaskStatus.fromInt(data[1] as int),
          data[2] as int,
        );
      });
    }
    return null;
  }
}

// ---------------------------------------------------------------- YouTube

class YtdlpState {
  final Map<String, int> progressMap;
  final Map<String, DownloadTaskStatus> statusMap;

  /// taskId -> title
  final Map<String, String> taskTitles;

  /// Search results (youtube_explode Video objects).
  final List<Video> results;

  const YtdlpState({
    this.progressMap = const {},
    this.statusMap = const {},
    this.taskTitles = const {},
    this.results = const [],
  });

  YtdlpState copyWith({
    Map<String, int>? progressMap,
    Map<String, DownloadTaskStatus>? statusMap,
    Map<String, String>? taskTitles,
    List<Video>? results,
  }) => YtdlpState(
    progressMap: progressMap ?? this.progressMap,
    statusMap: statusMap ?? this.statusMap,
    taskTitles: taskTitles ?? this.taskTitles,
    results: results ?? this.results,
  );
}

final ytdlpProvider = NotifierProvider<YtdlpNotifier, YtdlpState>(
  YtdlpNotifier.new,
);

/// Port of YtdlpController minus its dialogs (those live in
/// lib/screens/downloader/downloader_dialogs.dart). Listens to
/// downloadEventsProvider (ref.listen) and only updates tasks it owns
/// (taskTitles contains the id). loadExistingDownloads skips tasks whose
/// filename starts with 'tiktok_'. Closes its YoutubeExplode in
/// ref.onDispose.
class YtdlpNotifier extends Notifier<YtdlpState> {
  final YoutubeExplode _yt = YoutubeExplode();

  @override
  YtdlpState build() {
    ref.onDispose(_yt.close);

    ref.listen<DownloadEvent?>(downloadEventsProvider, (_, event) {
      if (event == null) return;
      // Only update if this task belongs to us.
      if (!state.taskTitles.containsKey(event.id)) return;
      state = state.copyWith(
        progressMap: {...state.progressMap, event.id: event.progress},
        statusMap: {...state.statusMap, event.id: event.status},
      );
    });

    Future.microtask(loadExistingDownloads);
    return const YtdlpState();
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    try {
      final searchList = await _yt.search.search(query);
      state = state.copyWith(results: searchList.toList());
    } catch (e) {
      AppSnackbar.showErrorSnackBar("Error", "Search failed: $e");
    }
  }

  /// Audio-only manifest sorted by bitrate descending (android client), or
  /// null on failure (the caller shows the error snackbar).
  Future<List<AudioOnlyStreamInfo>?> fetchAudioStreams(Video video) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(
        video.id,
        ytClients: [YoutubeApiClient.android],
      );
      return manifest.audioOnly.sortByBitrate().reversed.toList();
    } catch (e) {
      debugPrint("fetchAudioStreams failed: $e");
      return null;
    }
  }

  Future<void> startBackgroundDownload(
    String url,
    String title,
    String ext,
  ) async {
    Directory? downloadsDir = Directory('/storage/emulated/0/Download');
    if (!await downloadsDir.exists()) {
      downloadsDir = await getExternalStorageDirectory();
    }

    // Strip only characters that are illegal in file names so non-Latin
    // titles keep their name; fall back to a timestamp if nothing is left.
    final sanitized = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]+'), '')
        .trim();
    final baseName = sanitized.isEmpty
        ? "audio_${DateTime.now().millisecondsSinceEpoch}"
        : sanitized;
    final fileName = "$baseName.$ext";

    final taskId = await FlutterDownloader.enqueue(
      url: url,
      savedDir: downloadsDir?.path ?? "",
      fileName: fileName,
      showNotification: true,
      openFileFromNotification: false, // Set false to handle opening manually
      saveInPublicStorage: true,
      allowCellular: true,
    );

    if (taskId != null) {
      state = state.copyWith(
        taskTitles: {...state.taskTitles, taskId: title},
        progressMap: {...state.progressMap, taskId: 0},
        statusMap: {...state.statusMap, taskId: DownloadTaskStatus.enqueued},
      );
    }
  }

  Future<void> loadExistingDownloads() async {
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks == null) return;
    final titles = {...state.taskTitles};
    final progress = {...state.progressMap};
    final statuses = {...state.statusMap};
    for (final task in tasks) {
      // TikTok downloads are tracked by TikTokNotifier.
      if ((task.filename ?? '').startsWith('tiktok_')) continue;
      progress[task.taskId] = task.progress;
      statuses[task.taskId] = task.status;
      titles[task.taskId] = task.filename ?? "Unknown";
    }
    state = state.copyWith(
      taskTitles: titles,
      progressMap: progress,
      statusMap: statuses,
    );
  }

  Future<void> removeDownload(String taskId) async {
    await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: true);
    state = state.copyWith(
      progressMap: {...state.progressMap}..remove(taskId),
      statusMap: {...state.statusMap}..remove(taskId),
      taskTitles: {...state.taskTitles}..remove(taskId),
    );
  }
}

// ----------------------------------------------------------------- TikTok

class TikTokState {
  final bool isLoading;

  /// {title, author, cover, videoUrl, id} or null.
  final Map<String, dynamic>? fetchedVideo;
  final Map<String, String> taskTitles;
  final Map<String, int> progressMap;
  final Map<String, DownloadTaskStatus> statusMap;

  const TikTokState({
    this.isLoading = false,
    this.fetchedVideo,
    this.taskTitles = const {},
    this.progressMap = const {},
    this.statusMap = const {},
  });

  TikTokState copyWith({
    bool? isLoading,
    Map<String, dynamic>? fetchedVideo,
    bool clearFetchedVideo = false,
    Map<String, String>? taskTitles,
    Map<String, int>? progressMap,
    Map<String, DownloadTaskStatus>? statusMap,
  }) => TikTokState(
    isLoading: isLoading ?? this.isLoading,
    fetchedVideo: clearFetchedVideo
        ? null
        : (fetchedVideo ?? this.fetchedVideo),
    taskTitles: taskTitles ?? this.taskTitles,
    progressMap: progressMap ?? this.progressMap,
    statusMap: statusMap ?? this.statusMap,
  );
}

final tiktokProvider = NotifierProvider<TikTokNotifier, TikTokState>(
  TikTokNotifier.new,
);

/// Port of TikTokController minus dialogs and the URL TextEditingController
/// (the screen owns that controller and clears it when downloadVideo returns
/// true). loadExistingDownloads only takes 'tiktok_' tasks.
class TikTokNotifier extends Notifier<TikTokState> {
  @override
  TikTokState build() {
    ref.listen<DownloadEvent?>(downloadEventsProvider, (_, event) {
      if (event == null) return;
      // Only update if this task belongs to us.
      if (!state.taskTitles.containsKey(event.id)) return;
      state = state.copyWith(
        progressMap: {...state.progressMap, event.id: event.progress},
        statusMap: {...state.statusMap, event.id: event.status},
      );
    });

    Future.microtask(loadExistingDownloads);
    return const TikTokState();
  }

  Future<void> loadExistingDownloads() async {
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks == null) return;
    final titles = {...state.taskTitles};
    final progress = {...state.progressMap};
    final statuses = {...state.statusMap};
    for (final task in tasks) {
      final name = task.filename ?? '';
      if (!name.startsWith('tiktok_')) continue;
      titles[task.taskId] = name;
      progress[task.taskId] = task.progress;
      statuses[task.taskId] = task.status;
    }
    state = state.copyWith(
      taskTitles: titles,
      progressMap: progress,
      statusMap: statuses,
    );
  }

  Future<void> fetchVideoInfo(String url) async {
    if (url.isEmpty) return;

    state = state.copyWith(isLoading: true, clearFetchedVideo: true);

    try {
      final video = await TiktokScraper.getVideoInfo(
        url,
        source: ScrapeVideoSource.OfficialSite,
      );

      if (video.downloadUrls.isEmpty) {
        throw StateError("No download URLs returned");
      }

      state = state.copyWith(
        fetchedVideo: {
          'title': video.description,
          'author': video.author.name,
          'cover': video.thumbnail,
          'videoUrl': video.downloadUrls.first,
          'id': video.id,
        },
      );
    } catch (e) {
      AppSnackbar.showSnackbar(
        "Error",
        "Could not fetch video. Link might be invalid or private.",
      );
      debugPrint("TikTok Error: $e");
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Requests storage permission (openAppSettings on permanent denial), enqueues
  /// the download, registers the task. Returns true if the download started
  /// (the screen then clears its text field). Clears fetchedVideo on success.
  Future<bool> downloadVideo(Map<String, dynamic> videoData) async {
    // Permission check
    final status = await Permission.storage.request();
    if (status.isPermanentlyDenied) {
      openAppSettings();
      return false;
    }

    // Prepare directory
    Directory? downloadsDir = Directory('/storage/emulated/0/Download');
    if (!await downloadsDir.exists()) {
      downloadsDir = await getExternalStorageDirectory();
    }

    final saveDir = downloadsDir;

    final String downloadUrl = videoData['videoUrl'] ?? '';
    final String title = videoData['title'] ?? 'TikTok video';
    final String fileName =
        "tiktok_${videoData['id'] ?? DateTime.now().millisecondsSinceEpoch}.mp4";

    if (downloadUrl.isEmpty) {
      AppSnackbar.showSnackbar("Error", "No download URL found");
      return false;
    }

    final taskId = await FlutterDownloader.enqueue(
      url: downloadUrl,
      savedDir: saveDir?.path ?? "",
      fileName: fileName,
      showNotification: true,
      openFileFromNotification: true,
      saveInPublicStorage: true,
      allowCellular: true,
    );

    if (taskId == null) return false;

    // Register the task so the event listener updates it.
    state = state.copyWith(
      taskTitles: {...state.taskTitles, taskId: title},
      progressMap: {...state.progressMap, taskId: 0},
      statusMap: {...state.statusMap, taskId: DownloadTaskStatus.enqueued},
      clearFetchedVideo: true,
    );

    AppSnackbar.showSnackbar("Success", "Download started");
    return true;
  }

  Future<void> removeDownload(String taskId) async {
    await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: true);
    state = state.copyWith(
      taskTitles: {...state.taskTitles}..remove(taskId),
      progressMap: {...state.progressMap}..remove(taskId),
      statusMap: {...state.statusMap}..remove(taskId),
    );
  }
}
