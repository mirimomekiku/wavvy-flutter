import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// How good a file sounds, in three steps.
enum QualityTier {
  /// A lossy codec (MP3, AAC, Opus, Vorbis...).
  lossy,

  /// A lossless codec (FLAC, ALAC, WAV, APE, WavPack...).
  lossless,

  /// Lossless with more than CD resolution: 24 bits or more and a sample rate
  /// above 48 kHz (the Apple Music definition; 24-bit / 48 kHz stays Lossless).
  /// A file whose bit depth or sample rate is unknown is never Hi-Res.
  hiRes,
}

/// Codec names (as shown) that are lossless.
const _losslessCodecs = {
  'FLAC',
  'ALAC',
  'WAV',
  'AIFF',
  'APE',
  'WAVPACK',
  'PCM',
};

/// The short display name for a MIME type, e.g. `audio/mp4a-latm` -> `AAC`.
String? codecFromMime(String? mime) {
  if (mime == null) return null;
  final m = mime.trim().toLowerCase();
  if (m.isEmpty) return null;
  switch (m) {
    case 'audio/mpeg':
    case 'audio/mp3':
    case 'audio/mpeg-l1':
    case 'audio/mpeg-l2':
      return 'MP3';
    case 'audio/mp4a-latm':
    case 'audio/aac':
    case 'audio/aacp':
    case 'audio/aac-adts':
      return 'AAC';
    case 'audio/flac':
    case 'audio/x-flac':
      return 'FLAC';
    case 'audio/alac':
    case 'audio/x-alac':
      return 'ALAC';
    case 'audio/vorbis':
      return 'Vorbis';
    case 'audio/opus':
      return 'Opus';
    case 'audio/raw':
    case 'audio/wav':
    case 'audio/x-wav':
    case 'audio/wave':
    case 'audio/vnd.wave':
      return 'WAV';
  }
  final tail = m.contains('/') ? m.substring(m.indexOf('/') + 1) : m;
  final name = tail.startsWith('x-') ? tail.substring(2) : tail;
  return name.isEmpty ? null : name.toUpperCase();
}

/// The codec a file extension usually holds. `m4a` can be AAC or ALAC, so it
/// is shown as M4A until the native probe says which.
String? codecFromExtension(String? extension) {
  final e = (extension ?? '').trim().toLowerCase().replaceFirst('.', '');
  if (e.isEmpty) return null;
  switch (e) {
    case 'mp3':
      return 'MP3';
    case 'aac':
      return 'AAC';
    case 'flac':
      return 'FLAC';
    case 'wav':
    case 'wave':
      return 'WAV';
    case 'aif':
    case 'aiff':
      return 'AIFF';
    case 'ogg':
    case 'oga':
      return 'Vorbis';
    case 'opus':
      return 'Opus';
    case 'ape':
      return 'APE';
    case 'wv':
      return 'WavPack';
    default:
      return e.toUpperCase();
  }
}

/// Technical details of one audio file.
///
/// Built from the native probe ([AudioQuality.fromMap]) or, when that is not
/// available, from what MediaStore already knows ([AudioQuality.fromSong],
/// [estimated] is then true). Any field can be null.
@immutable
class AudioQuality {
  const AudioQuality({
    this.codec,
    this.mimeType,
    this.sampleRate,
    this.bitDepth,
    this.bitrate,
    this.channels,
    this.durationMs,
    this.lossless,
    this.estimated = false,
  });

  /// Short display name: MP3, AAC, FLAC, ALAC, Opus, WAV...
  final String? codec;
  final String? mimeType;

  /// Hertz.
  final int? sampleRate;
  final int? bitDepth;

  /// Bits per second.
  final int? bitrate;
  final int? channels;
  final int? durationMs;

  /// Null when unknown (judged from the codec name instead).
  final bool? lossless;

  /// True when this comes from the file name and size, not from the file.
  final bool estimated;

  /// Null when [map] is not a usable native answer.
  static AudioQuality? fromMap(Object? map) {
    if (map is! Map) return null;
    int? number(String key) {
      final v = map[key];
      return v is num && v > 0 ? v.toInt() : null;
    }

    String? text(String key) {
      final v = map[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final mime = text('mime');
    final codec = codecFromMime(mime) ?? text('codec');
    final lossless = map['lossless'];
    final depth = number('bitDepth');
    final quality = AudioQuality(
      codec: codec,
      mimeType: mime,
      sampleRate: number('sampleRate'),
      // Nothing sensible is below 8 or above 32 bits.
      bitDepth: depth != null && depth >= 8 && depth <= 32 ? depth : null,
      bitrate: number('bitrate'),
      channels: number('channels'),
      durationMs: number('durationMs'),
      lossless: lossless is bool ? lossless : null,
    );
    return quality.hasData ? quality : null;
  }

  /// What MediaStore gives: the file extension and the average bitrate from
  /// size and duration. Never throws (raw rows can lack fields).
  factory AudioQuality.fromSong(SongModel song) {
    String ext = '';
    int size = 0;
    int ms = 0;
    try {
      ext = song.fileExtension;
    } catch (_) {}
    try {
      size = song.size;
    } catch (_) {}
    try {
      ms = song.duration ?? 0;
    } catch (_) {}
    return AudioQuality.estimate(
      extension: ext,
      sizeBytes: size,
      durationMs: ms,
    );
  }

  /// [fromSong] without the model, for tests and other callers.
  factory AudioQuality.estimate({
    String? extension,
    int sizeBytes = 0,
    int durationMs = 0,
  }) {
    final codec = codecFromExtension(extension);
    final bps = sizeBytes > 0 && durationMs > 0
        ? (sizeBytes * 8 * 1000 / durationMs).round()
        : null;
    return AudioQuality(
      codec: codec,
      bitrate: bps != null && bps > 0 ? bps : null,
      durationMs: durationMs > 0 ? durationMs : null,
      lossless: codec != null && _losslessCodecs.contains(codec.toUpperCase())
          ? true
          : null,
      estimated: true,
    );
  }

  /// Fills what this lacks from [other] (the estimate for a missing bitrate).
  AudioQuality fillFrom(AudioQuality other) => AudioQuality(
    codec: codec ?? other.codec,
    mimeType: mimeType,
    sampleRate: sampleRate,
    bitDepth: bitDepth,
    bitrate: bitrate ?? other.bitrate,
    channels: channels,
    durationMs: durationMs ?? other.durationMs,
    lossless: lossless ?? other.lossless,
    estimated: estimated && other.estimated,
  );

  /// Anything worth showing.
  bool get hasData =>
      codec != null ||
      sampleRate != null ||
      bitrate != null ||
      bitDepth != null;

  bool get isLossless =>
      lossless ??
      (codec != null && _losslessCodecs.contains(codec!.toUpperCase()));

  QualityTier get tier {
    if (!isLossless) return QualityTier.lossy;
    final depth = bitDepth;
    final rate = sampleRate;
    if (depth != null && rate != null && depth >= 24 && rate > 48000) {
      return QualityTier.hiRes;
    }
    return QualityTier.lossless;
  }

  /// "Lossy", "Lossless" or "Hi-Res Lossless".
  String get tierName => switch (tier) {
    QualityTier.lossy => 'Lossy',
    QualityTier.lossless => 'Lossless',
    QualityTier.hiRes => 'Hi-Res Lossless',
  };

  int? get _kbps => bitrate == null ? null : (bitrate! / 1000).round();

  /// "FLAC 24-bit / 96 kHz", "MP3 320 kbps", "AAC 256 kbps". A lossless file
  /// with no depth or rate shows its bitrate; a lossy one without a bitrate is
  /// just its codec.
  String get label {
    final c = codec ?? '';
    final String detail;
    if (isLossless) {
      final parts = [
        if (bitDepth != null) '$bitDepth-bit',
        if (sampleRate != null) '${formatKhz(sampleRate!)} kHz',
      ];
      detail = parts.isNotEmpty
          ? parts.join(' / ')
          : (_kbps != null && _kbps! > 0 ? '$_kbps kbps' : '');
    } else {
      detail = _kbps != null && _kbps! > 0 ? '$_kbps kbps' : '';
    }
    return [c, detail].where((s) => s.isNotEmpty).join(' ');
  }

  /// A narrower [label]: "FLAC 24/96", "MP3 320k".
  String get shortLabel {
    final c = codec ?? '';
    final String detail;
    if (isLossless) {
      if (bitDepth != null && sampleRate != null) {
        detail = '$bitDepth/${formatKhz(sampleRate!)}';
      } else if (sampleRate != null) {
        detail = '${formatKhz(sampleRate!)}k';
      } else if (bitDepth != null) {
        detail = '$bitDepth-bit';
      } else {
        detail = _kbps != null && _kbps! > 0 ? '${_kbps}k' : '';
      }
    } else {
      detail = _kbps != null && _kbps! > 0 ? '${_kbps}k' : '';
    }
    return [c, detail].where((s) => s.isNotEmpty).join(' ');
  }

  /// For screen readers: "Lossless, FLAC, 24-bit, 96 kilohertz".
  String get semanticsLabel => [
    if (hasData) tierName,
    ?codec,
    if (bitDepth != null) '$bitDepth-bit',
    if (sampleRate != null) '${formatKhz(sampleRate!)} kilohertz',
    if (!isLossless && _kbps != null && _kbps! > 0)
      '$_kbps kilobits per second',
  ].join(', ');

  @override
  bool operator ==(Object other) =>
      other is AudioQuality &&
      other.codec == codec &&
      other.mimeType == mimeType &&
      other.sampleRate == sampleRate &&
      other.bitDepth == bitDepth &&
      other.bitrate == bitrate &&
      other.channels == channels &&
      other.durationMs == durationMs &&
      other.lossless == lossless &&
      other.estimated == estimated;

  @override
  int get hashCode => Object.hash(
    codec,
    mimeType,
    sampleRate,
    bitDepth,
    bitrate,
    channels,
    durationMs,
    lossless,
    estimated,
  );
}

/// 44100 -> "44.1", 48000 -> "48", 96000 -> "96", 88200 -> "88.2".
String formatKhz(int hertz) {
  final k = hertz / 1000;
  final text = k.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// "Mono", "Stereo", or "6 channels".
String channelsLabel(int channels) => switch (channels) {
  1 => 'Mono',
  2 => 'Stereo',
  _ => '$channels channels',
};

/// The native side of the quality probe. Overridden in tests.
abstract class AudioInfoChannel {
  /// The file's details, or null when they cannot be read. Never throws.
  Future<AudioQuality?> probe({String? uri, int? id});
}

class MethodAudioInfoChannel implements AudioInfoChannel {
  static const _channel = MethodChannel('com.mirimomekiku.wavvy/audio_info');

  @override
  Future<AudioQuality?> probe({String? uri, int? id}) async {
    try {
      return AudioQuality.fromMap(
        await _channel.invokeMethod<Object?>('info', {
          'uri': ?uri,
          if (id != null && id > 0) 'id': id,
        }),
      );
    } catch (e) {
      debugPrint('audio info unavailable: $e');
      return null;
    }
  }
}

final audioInfoChannelProvider = Provider<AudioInfoChannel>(
  (ref) => MethodAudioInfoChannel(),
);

/// Which song to probe, plus what MediaStore says about it for the fallback.
/// Equal when the id and URI are (the other fields follow from them).
@immutable
class QualityKey {
  const QualityKey({
    required this.id,
    this.uri,
    this.extension,
    this.sizeBytes = 0,
    this.durationMs = 0,
  });

  factory QualityKey.fromSong(SongModel song) {
    String? ext;
    int size = 0;
    int ms = 0;
    try {
      ext = song.fileExtension;
    } catch (_) {}
    try {
      size = song.size;
    } catch (_) {}
    try {
      ms = song.duration ?? 0;
    } catch (_) {}
    String? uri;
    try {
      uri = song.uri;
    } catch (_) {}
    return QualityKey(
      id: song.id,
      uri: uri,
      extension: ext,
      sizeBytes: size,
      durationMs: ms,
    );
  }

  final int id;
  final String? uri;
  final String? extension;
  final int sizeBytes;
  final int durationMs;

  /// The quick answer from the file name and size.
  AudioQuality get estimate => AudioQuality.estimate(
    extension: extension,
    sizeBytes: sizeBytes,
    durationMs: durationMs,
  );

  @override
  bool operator ==(Object other) =>
      other is QualityKey && other.id == id && other.uri == uri;

  @override
  int get hashCode => Object.hash(id, uri);
}

/// The quality of one song: the native details with the estimate filling any
/// gap, or the estimate alone when the probe has nothing. Cached per song for
/// the session; never an error.
final audioQualityProvider = FutureProvider.family<AudioQuality, QualityKey>((
  ref,
  key,
) async {
  final estimate = key.estimate;
  try {
    final native = await ref
        .read(audioInfoChannelProvider)
        .probe(uri: key.uri, id: key.id);
    return native == null ? estimate : native.fillFrom(estimate);
  } catch (e) {
    debugPrint('audio quality failed: $e');
    return estimate;
  }
});
