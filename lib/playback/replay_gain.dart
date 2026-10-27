import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// ReplayGain values found in a file's tags (decibels, and linear peak).
class ReplayGainTags {
  final double? trackGain;
  final double? albumGain;
  final double? trackPeak;
  final double? albumPeak;

  const ReplayGainTags({
    this.trackGain,
    this.albumGain,
    this.trackPeak,
    this.albumPeak,
  });

  bool get isEmpty => trackGain == null && albumGain == null;
}

/// 0 off, 1 track gain, 2 album gain (the saved setting).
enum ReplayGainMode {
  off,
  track,
  album;

  static ReplayGainMode fromIndex(int i) =>
      i >= 0 && i < values.length ? values[i] : off;
}

/// The cap on boosting a quiet track. Cutting a loud one is always safe.
const double maxReplayGainBoostDb = 9;

/// Finds ReplayGain tags in the raw bytes of an audio file.
///
/// The tag formats differ (ID3v2 TXXX frames, Vorbis comments in FLAC / Ogg /
/// Opus, APE tags, MP4 freeform atoms) but all of them hold the field name and
/// the value as text, UTF-16 in some ID3 files. So this does not parse
/// containers: it drops zero bytes, which turns UTF-16 into plain text, and
/// looks for the field name followed by a number.
ReplayGainTags? parseReplayGain(Uint8List bytes) {
  // Drop NULs so UTF-16 text reads as ASCII. Everything else is kept, as the
  // search below skips over the binary separators between a name and its value.
  final text = String.fromCharCodes(
    bytes.where((b) => b != 0),
  ).replaceAll(RegExp(r'[^\x20-\x7e]'), ' ');

  double? find(String name, {required bool db}) {
    final pattern = RegExp(
      '$name.{0,24}?([-+]?\\d+(?:[.,]\\d+)?)${db ? r'\s*db' : ''}',
      caseSensitive: false,
    );
    final m = pattern.firstMatch(text);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    return v != null && v.isFinite ? v : null;
  }

  final tags = ReplayGainTags(
    trackGain: find('replaygain_track_gain', db: true),
    albumGain: find('replaygain_album_gain', db: true),
    trackPeak: find('replaygain_track_peak', db: false),
    albumPeak: find('replaygain_album_peak', db: false),
  );
  return tags.isEmpty ? null : tags;
}

/// Reads the tags from the start and end of a file, where they live. An ID3v2
/// tag at the start says how long it is, so a large one (with cover art) is
/// read whole.
Future<ReplayGainTags?> readReplayGain(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final length = await file.length();
    final head = await file.read(math.min(length, 262144));
    var headEnd = head.length;
    // "ID3", version, flags, then a 4 x 7-bit size.
    if (head.length >= 10 &&
        head[0] == 0x49 &&
        head[1] == 0x44 &&
        head[2] == 0x33) {
      final size = (head[6] << 21) | (head[7] << 14) | (head[8] << 7) | head[9];
      final want = math.min(size + 10, math.min(length, 8 * 1024 * 1024));
      if (want > head.length) {
        await file.setPosition(0);
        final whole = await file.read(want);
        final found = parseReplayGain(whole);
        if (found != null) return found;
        headEnd = whole.length;
      }
    }
    final fromHead = parseReplayGain(head);
    if (fromHead != null) return fromHead;
    // APE / ID3v1 tags and MP4 files with the metadata at the end.
    if (length > headEnd) {
      final tailLen = math.min(length - headEnd, 524288);
      await file.setPosition(length - tailLen);
      return parseReplayGain(await file.read(tailLen));
    }
    return null;
  } on FileSystemException {
    return null;
  } finally {
    await file?.close();
  }
}

/// The gain to apply, in decibels, for [tags] in [mode]: the track gain or the
/// album gain (falling back to the other when one is missing), kept from
/// clipping by the peak value and capped at [maxReplayGainBoostDb]. 0 when the
/// file has no ReplayGain tags or the mode is off.
double replayGainDb(
  ReplayGainTags? tags,
  ReplayGainMode mode, {
  double preampDb = 0,
}) {
  if (tags == null || mode == ReplayGainMode.off) return 0;
  final wantAlbum = mode == ReplayGainMode.album;
  final gain = wantAlbum
      ? (tags.albumGain ?? tags.trackGain)
      : (tags.trackGain ?? tags.albumGain);
  if (gain == null) return 0;
  final peak = wantAlbum
      ? (tags.albumPeak ?? tags.trackPeak)
      : (tags.trackPeak ?? tags.albumPeak);
  var db = gain + preampDb;
  if (db > 0) {
    db = math.min(db, maxReplayGainBoostDb);
    // Boosting must not push the loudest sample past full scale.
    if (peak != null && peak > 0) {
      final headroom = -20 * math.log(peak) / math.ln10;
      db = math.min(db, math.max(0.0, headroom));
    }
  }
  return db;
}

/// Reads tags from a song's file, once. Overridden in tests.
final replayGainReaderProvider =
    Provider<Future<ReplayGainTags?> Function(SongModel)>(
      (ref) =>
          (song) => readReplayGain(song.data),
    );

/// Looks up (and remembers) the ReplayGain tags of songs.
class ReplayGainCache {
  ReplayGainCache(this._read);
  final Future<ReplayGainTags?> Function(SongModel) _read;
  final Map<int, ReplayGainTags?> _tags = {};
  final Map<int, Future<ReplayGainTags?>> _pending = {};
  static const _limit = 300;

  Future<ReplayGainTags?> tagsFor(SongModel song) {
    if (_tags.containsKey(song.id)) {
      return Future.value(_tags[song.id]);
    }
    return _pending[song.id] ??= _read(song)
        .then((t) {
          if (_tags.length >= _limit) _tags.remove(_tags.keys.first);
          _tags[song.id] = t;
          return t;
        })
        // A block, not an expression: whenComplete would wait for a returned
        // future, and remove() hands back this very one.
        .whenComplete(() {
          _pending.remove(song.id);
        });
  }
}

final replayGainCacheProvider = Provider<ReplayGainCache>(
  (ref) => ReplayGainCache(ref.watch(replayGainReaderProvider)),
);
