import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:wavvy/artwork/album_art_match.dart';

/// Contact URL sent in the User-Agent, as MusicBrainz asks. Replace with the
/// project's real page before release.
const String kArtContactUrl = 'https://example.com/wavvy-contact';

/// Largest cover accepted; a bigger or unbounded body is dropped.
const int kMaxArtBytes = 2 * 1024 * 1024;

/// MusicBrainz allows one request per second; the same pace is kept for the
/// Cover Art Archive.
const Duration kArtRequestInterval = Duration(seconds: 1);

/// How long one request may take before it counts as being offline.
const Duration kArtRequestTimeout = Duration(seconds: 12);

/// What a lookup came to.
enum ArtOutcome {
  /// A cover was downloaded.
  found,

  /// The services answered but have no cover for this album.
  notFound,

  /// No connection or a timeout.
  offline,

  /// The service asked to slow down or is overloaded (429, 503).
  rateLimited,

  /// Anything else unexpected (other status codes, malformed answers).
  error,
}

/// The result of [AlbumArtClient.find].
class ArtResult {
  final ArtOutcome outcome;
  final Uint8List? bytes;

  /// `jpg` or `png` when [bytes] is set.
  final String? extension;

  const ArtResult(this.outcome, {this.bytes, this.extension});

  /// Whether a batch should stop after this result.
  bool get stopsBatch =>
      outcome == ArtOutcome.offline ||
      outcome == ArtOutcome.rateLimited ||
      outcome == ArtOutcome.error;
}

/// Spaces calls at least [interval] apart, shared by everything that uses the
/// same instance. [now] and [sleep] can be faked.
class RateLimiter {
  final Duration interval;
  final DateTime Function() now;
  final Future<void> Function(Duration) sleep;

  DateTime? _last;
  Future<void>? _tail;

  RateLimiter({
    this.interval = kArtRequestInterval,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  }) : now = now ?? DateTime.now,
       sleep = sleep ?? Future<void>.delayed;

  /// Completes when the caller may send one request. Callers go in order.
  Future<void> acquire() {
    final previous = _tail;
    final turn = Completer<void>();
    _tail = turn.future;
    return () async {
      try {
        if (previous != null) await previous;
        final last = _last;
        if (last != null) {
          final wait = last.add(interval).difference(now());
          if (wait > Duration.zero) await sleep(wait);
        }
        _last = now();
      } finally {
        turn.complete();
      }
    }();
  }
}

/// Finds a cover through MusicBrainz and the Cover Art Archive. Sends only the
/// album and artist names, always over https, one request per second, every
/// request with a timeout and a descriptive User-Agent. Never throws.
class AlbumArtClient {
  final http.Client _http;
  final Future<String> Function() _userAgent;
  final RateLimiter limiter;
  final Duration timeout;
  final int maxBytes;

  String? _agent;

  AlbumArtClient({
    required http.Client client,
    required Future<String> Function() userAgent,
    RateLimiter? limiter,
    this.timeout = kArtRequestTimeout,
    this.maxBytes = kMaxArtBytes,
  }) : _http = client,
       _userAgent = userAgent,
       limiter = limiter ?? RateLimiter();

  /// Looks for the front cover of [album] by [artist]: the best matching
  /// releases first, then the best match's release group.
  Future<ArtResult> find({
    required String album,
    required String artist,
  }) async {
    try {
      final search = await _getBytes(buildSearchUri(album, artist), json: true);
      if (search.failure != null) return ArtResult(search.failure!);

      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(search.bytes!));
      } catch (_) {
        return const ArtResult(ArtOutcome.error);
      }
      final candidates = pickReleases(decoded, album: album, artist: artist);
      if (candidates.isEmpty) return const ArtResult(ArtOutcome.notFound);

      final best = candidates.first;
      final sources = <Uri>[
        _front('release', best.id),
        if (best.groupId != null) _front('release-group', best.groupId!),
      ];
      for (final uri in sources) {
        final r = await _getBytes(uri, json: false);
        if (r.failure == ArtOutcome.notFound) continue;
        if (r.failure != null) return ArtResult(r.failure!);
        final ext = _imageExtension(r.contentType, r.bytes!);
        // A wrong type is as good as no cover: try the next source.
        if (ext == null) continue;
        return ArtResult(ArtOutcome.found, bytes: r.bytes, extension: ext);
      }
      return const ArtResult(ArtOutcome.notFound);
    } catch (_) {
      return const ArtResult(ArtOutcome.error);
    }
  }

  Uri _front(String kind, String mbid) =>
      Uri.https('coverartarchive.org', '/$kind/$mbid/front-500');

  Future<_Fetched> _getBytes(Uri uri, {required bool json}) async {
    assert(uri.scheme == 'https');
    try {
      await limiter.acquire();
      final agent = _agent ??= await _userAgent();
      final request = http.Request('GET', uri)
        ..headers['User-Agent'] = agent
        ..headers['Accept'] = json ? 'application/json' : 'image/*';
      final response = await _http.send(request).timeout(timeout);

      // A redirect to plain http is refused (the client follows redirects).
      final finalUrl = response is http.BaseResponseWithUrl
          ? (response as http.BaseResponseWithUrl).url
          : uri;
      if (finalUrl.scheme != 'https') {
        await response.stream.listen(null).cancel();
        return const _Fetched.fail(ArtOutcome.error);
      }

      final status = response.statusCode;
      if (status == 404) {
        await response.stream.listen(null).cancel();
        return const _Fetched.fail(ArtOutcome.notFound);
      }
      if (status == 429 || status == 503) {
        await response.stream.listen(null).cancel();
        return const _Fetched.fail(ArtOutcome.rateLimited);
      }
      if (status != 200) {
        await response.stream.listen(null).cancel();
        return const _Fetched.fail(ArtOutcome.error);
      }

      final limit = json ? 1024 * 1024 : maxBytes;
      final declared = response.contentLength;
      if (declared != null && declared > limit) {
        await response.stream.listen(null).cancel();
        // Too big counts as no usable cover for this source.
        return const _Fetched.fail(ArtOutcome.notFound);
      }
      final type = response.headers['content-type']?.toLowerCase();
      if (!json && !(type?.startsWith('image/') ?? false)) {
        await response.stream.listen(null).cancel();
        return const _Fetched.fail(ArtOutcome.notFound);
      }

      final body = BytesBuilder(copy: false);
      var oversize = false;
      await for (final chunk in response.stream.timeout(timeout)) {
        body.add(chunk);
        if (body.length > limit) {
          oversize = true;
          break;
        }
      }
      if (oversize) return const _Fetched.fail(ArtOutcome.notFound);
      return _Fetched.ok(body.takeBytes(), type);
    } on TimeoutException {
      return const _Fetched.fail(ArtOutcome.offline);
    } on SocketException {
      return const _Fetched.fail(ArtOutcome.offline);
    } on http.ClientException {
      return const _Fetched.fail(ArtOutcome.offline);
    } on HandshakeException {
      return const _Fetched.fail(ArtOutcome.offline);
    } catch (_) {
      return const _Fetched.fail(ArtOutcome.error);
    }
  }

  /// `jpg` or `png` when the content type and the file signature agree, else
  /// null (HTML error pages, SVG, GIF and anything else are refused).
  static String? _imageExtension(String? contentType, Uint8List bytes) {
    final type = contentType?.split(';').first.trim();
    final isJpeg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    final isPng =
        bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    if ((type == 'image/jpeg' || type == 'image/jpg') && isJpeg) return 'jpg';
    if (type == 'image/png' && isPng) return 'png';
    return null;
  }
}

class _Fetched {
  final Uint8List? bytes;
  final String? contentType;
  final ArtOutcome? failure;

  const _Fetched.ok(this.bytes, this.contentType) : failure = null;
  const _Fetched.fail(ArtOutcome this.failure)
    : bytes = null,
      contentType = null;
}
