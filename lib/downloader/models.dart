/// What the downloader knows about one piece of online media (a yt-dlp result).
class MediaInfo {
  final String id;
  final String title;

  /// The artist if yt-dlp knows one, otherwise the channel or uploader.
  final String artist;
  final String thumbnail;
  final int? durationSeconds;

  /// The page to download from.
  final String url;
  final String extractor;

  const MediaInfo({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.url,
    this.durationSeconds,
    this.extractor = '',
  });

  /// Reads one entry of yt-dlp's JSON. Search results are "flat" entries with
  /// fewer fields, so everything but the id and title is optional.
  factory MediaInfo.fromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] ?? '').toString();
    String firstNonEmpty(List<String> keys) {
      for (final k in keys) {
        final v = text(k).trim();
        if (v.isNotEmpty && v != 'null') return v;
      }
      return '';
    }

    final id = text('id');
    final title = firstNonEmpty(['track', 'title', 'description']);
    var thumbnail = text('thumbnail');
    if (thumbnail.isEmpty && json['thumbnails'] is List) {
      final list = json['thumbnails'] as List;
      if (list.isNotEmpty && list.last is Map) {
        thumbnail = (list.last as Map)['url']?.toString() ?? '';
      }
    }
    final extractor = firstNonEmpty(['extractor_key', 'ie_key', 'extractor']);
    var url = firstNonEmpty(['webpage_url', 'original_url', 'url']);
    // Flat YouTube search entries only carry an id.
    if (url.isEmpty && id.isNotEmpty) {
      url = 'https://www.youtube.com/watch?v=$id';
    }
    final duration = json['duration'];
    return MediaInfo(
      id: id,
      title: title.isEmpty ? 'Untitled' : title,
      artist: cleanArtist(
        firstNonEmpty(['artist', 'creator', 'uploader', 'channel']),
      ),
      thumbnail: thumbnail,
      url: url,
      durationSeconds: duration is num ? duration.round() : null,
      extractor: extractor,
    );
  }

  /// YouTube auto-generated channels end in " - Topic".
  static String cleanArtist(String name) =>
      name.endsWith(' - Topic') ? name.substring(0, name.length - 8) : name;

  /// Whether [text] is something to resolve directly, not a search.
  static bool looksLikeUrl(String text) {
    final uri = Uri.tryParse(text.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.contains('.');
  }
}

enum DownloadStatus {
  queued,
  running,

  /// Downloaded; being tagged and added to the music library.
  publishing,
  complete,
  failed,
  canceled;

  bool get active => this == queued || this == running || this == publishing;

  static DownloadStatus parse(String? value) => DownloadStatus.values
      .firstWhere((s) => s.name == value, orElse: () => DownloadStatus.failed);
}

/// One download, kept in the database so it survives restarts.
class DownloadTask {
  final String id;
  final String url;
  final String videoId;
  final String title;
  final String artist;
  final String thumbnail;
  final int? durationSeconds;
  final DownloadStatus status;
  final int progress;
  final String error;

  /// Where the file was downloaded (private staging) until it is published.
  final String filePath;

  /// The content URI in the music library, once published.
  final String mediaUri;
  final DateTime createdAt;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.videoId,
    required this.title,
    this.artist = '',
    this.thumbnail = '',
    this.durationSeconds,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.error = '',
    this.filePath = '',
    this.mediaUri = '',
    required this.createdAt,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    int? progress,
    String? error,
    String? filePath,
    String? mediaUri,
  }) => DownloadTask(
    id: id,
    url: url,
    videoId: videoId,
    title: title,
    artist: artist,
    thumbnail: thumbnail,
    durationSeconds: durationSeconds,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    error: error ?? this.error,
    filePath: filePath ?? this.filePath,
    mediaUri: mediaUri ?? this.mediaUri,
    createdAt: createdAt,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'url': url,
    'video_id': videoId,
    'title': title,
    'artist': artist,
    'thumbnail': thumbnail,
    'duration': durationSeconds,
    'status': status.name,
    'progress': progress,
    'error': error,
    'file_path': filePath,
    'media_uri': mediaUri,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory DownloadTask.fromRow(Map<String, Object?> row) => DownloadTask(
    id: row['id'] as String,
    url: row['url'] as String,
    videoId: row['video_id'] as String,
    title: row['title'] as String,
    artist: (row['artist'] as String?) ?? '',
    thumbnail: (row['thumbnail'] as String?) ?? '',
    durationSeconds: row['duration'] as int?,
    status: DownloadStatus.parse(row['status'] as String?),
    progress: (row['progress'] as int?) ?? 0,
    error: (row['error'] as String?) ?? '',
    filePath: (row['file_path'] as String?) ?? '',
    mediaUri: (row['media_uri'] as String?) ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
  );
}

/// A file name for [title] that is safe on Android: illegal characters removed,
/// whitespace collapsed, and no more than [maxBytes] of UTF-8 (the file system
/// limit is 255 bytes, and a long title in another script can exceed it).
String sanitizeFileName(String title, {int maxBytes = 120}) {
  var name = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Leading dots and spaces would make a hidden file, or a name like "..".
  name = name.replaceAll(RegExp(r'^[.\s]+'), '');
  if (name.isEmpty) return 'download';
  var bytes = 0;
  final out = StringBuffer();
  for (final rune in name.runes) {
    final char = String.fromCharCode(rune);
    final size = rune <= 0x7F
        ? 1
        : rune <= 0x7FF
        ? 2
        : rune <= 0xFFFF
        ? 3
        : 4;
    if (bytes + size > maxBytes) break;
    bytes += size;
    out.write(char);
  }
  final result = out.toString().trim();
  return result.isEmpty ? 'download' : result;
}
