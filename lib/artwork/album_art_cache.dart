import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:wavvy/artwork/album_art_client.dart';
import 'package:wavvy/artwork/album_art_match.dart';

/// Fetched album covers in a private folder: one `<key>.jpg` or `<key>.png`
/// per album, plus `misses.json` (album key -> time of the last failed
/// lookup, so a miss is not asked again for [kArtMissTtl]).
///
/// The folder is listed once by [load]; after that [files] answers from
/// memory, so a list row never touches the file system.
class AlbumArtCache {
  final Future<Directory> Function() _directory;
  final DateTime Function() _now;
  final int maxBytes;

  Directory? _dir;
  Future<void>? _loading;
  final Map<String, File> _files = {};
  final Map<String, DateTime> _misses = {};

  AlbumArtCache({
    required Future<Directory> Function() directory,
    DateTime Function()? now,
    this.maxBytes = kMaxArtBytes,
  }) : _directory = directory,
       _now = now ?? DateTime.now;

  static const _missesFile = 'misses.json';

  /// Cached covers by album key, as loaded and updated so far.
  Map<String, File> get files => Map.unmodifiable(_files);

  /// Lists the folder and reads the miss index. Safe to call again; failures
  /// leave the cache empty.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final dir = await _ensureDir();
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (ext != '.jpg' && ext != '.png') continue;
        _files[p.basenameWithoutExtension(entity.path)] = entity;
      }
      final index = File(p.join(dir.path, _missesFile));
      if (await index.exists()) {
        final json = jsonDecode(await index.readAsString());
        if (json is Map) {
          json.forEach((k, v) {
            if (k is String && v is int) {
              _misses[k] = DateTime.fromMillisecondsSinceEpoch(v);
            }
          });
        }
      }
    } catch (_) {
      // An unreadable folder or index is the same as an empty cache.
    }
  }

  Future<Directory> _ensureDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final dir = await _directory();
    await dir.create(recursive: true);
    return _dir = dir;
  }

  File? lookup(String key) => _files[key];

  /// Whether [key] was looked up without luck within [kArtMissTtl].
  bool hasFreshMiss(String key) {
    final at = _misses[key];
    return at != null && isMissFresh(at, _now());
  }

  /// Saves [bytes] as the cover of [key] (replacing any earlier one). Returns
  /// null, storing nothing, for an empty or oversize image or a disk error.
  Future<File?> store(String key, Uint8List bytes, String extension) async {
    if (bytes.isEmpty || bytes.length > maxBytes) return null;
    if (extension != 'jpg' && extension != 'png') return null;
    try {
      final dir = await _ensureDir();
      final file = File(p.join(dir.path, '$key.$extension'));
      // Write beside, then rename: a crash never leaves half a picture.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await _deleteFiles(key, except: file.path);
      await tmp.rename(file.path);
      _files[key] = file;
      if (_misses.remove(key) != null) await _saveMisses();
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the cover of [key]. It is not counted as a miss: asking again is
  /// the user's choice.
  Future<void> remove(String key) async {
    _files.remove(key);
    try {
      await _ensureDir();
      await _deleteFiles(key);
    } catch (_) {}
  }

  Future<void> _deleteFiles(String key, {String? except}) async {
    final dir = _dir;
    if (dir == null) return;
    for (final ext in const ['jpg', 'png']) {
      final f = File(p.join(dir.path, '$key.$ext'));
      if (f.path != except && await f.exists()) await f.delete();
    }
  }

  /// Notes that the services have no cover for [key] right now.
  Future<void> recordMiss(String key) async {
    _misses[key] = _now();
    await _saveMisses();
  }

  Future<void> _saveMisses() async {
    try {
      final dir = await _ensureDir();
      final json = jsonEncode({
        for (final e in _misses.entries) e.key: e.value.millisecondsSinceEpoch,
      });
      await File(p.join(dir.path, _missesFile)).writeAsString(json);
    } catch (_) {}
  }
}
