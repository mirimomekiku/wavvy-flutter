import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wavvy/artwork/album_art_cache.dart';
import 'package:wavvy/artwork/album_art_client.dart';
import 'package:wavvy/artwork/album_art_match.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

// ------------------------------------------------------------ Plumbing
// Everything that touches the network, the disk or a plugin is behind a
// provider, so tests replace it.

final albumArtHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// `<app support dir>/album_art`: private to the app.
final albumArtDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory(
        p.join((await getApplicationSupportDirectory()).path, 'album_art'),
      ),
);

/// `Wavvy/<version> ( <contact url> )`, as MusicBrainz asks.
final albumArtUserAgentProvider = Provider<Future<String> Function()>(
  (ref) => () async {
    var version = '1.0';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    return 'Wavvy/$version ( $kArtContactUrl )';
  },
);

/// One limiter for every lookup in the app.
final albumArtLimiterProvider = Provider<RateLimiter>((ref) => RateLimiter());

final albumArtClientProvider = Provider<AlbumArtClient>(
  (ref) => AlbumArtClient(
    client: ref.watch(albumArtHttpClientProvider),
    userAgent: ref.watch(albumArtUserAgentProvider),
    limiter: ref.watch(albumArtLimiterProvider),
  ),
);

final albumArtCacheProvider = Provider<AlbumArtCache>(
  (ref) => AlbumArtCache(directory: ref.watch(albumArtDirectoryProvider)),
);

/// Whether MediaStore has a picture for an album. Does not decode anything:
/// `queryArtwork` returns null or nothing when there is none.
final albumArtProbeProvider = Provider<Future<bool> Function(int albumId)>((
  ref,
) {
  final query = ref.watch(audioQueryProvider);
  return (albumId) async {
    try {
      final bytes = await query.queryArtwork(
        albumId,
        ArtworkType.ALBUM,
        format: ArtworkFormat.JPEG,
        size: 64,
        quality: 50,
      );
      return bytes != null && bytes.isNotEmpty;
    } catch (_) {
      // When in doubt do not go looking online.
      return true;
    }
  };
});

/// Completes once the app is in the foreground (immediately in tests).
final albumArtForegroundGateProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    try {
      final binding = WidgetsBinding.instance;
      bool inBackground() {
        final s = binding.lifecycleState;
        return s == AppLifecycleState.paused ||
            s == AppLifecycleState.hidden ||
            s == AppLifecycleState.detached;
      }

      while (inBackground()) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    } catch (_) {}
  },
);

// ------------------------------------------------------- Library mapping

AlbumRef albumRefForAlbum(AlbumModel a) => AlbumRef(
  key: albumKey(albumId: a.id),
  album: a.album,
  artist: a.artist ?? '',
);

/// The album of a song, or null for a song with no album (a single).
AlbumRef? albumRefForSong(SongModel s) {
  if (isUnknownTag(s.album)) return null;
  return AlbumRef(
    key: albumKey(albumId: s.albumId, album: s.album, artist: s.artist),
    album: s.album!.trim(),
    artist: s.artist ?? '',
  );
}

/// Song id -> album, built once per library change.
final songArtRefsProvider = Provider<Map<int, AlbumRef>>((ref) {
  final songs = ref.watch(libraryProvider.select((s) => s.songs));
  final out = <int, AlbumRef>{};
  for (final s in songs) {
    final r = albumRefForSong(s);
    if (r != null) out[s.id] = r;
  }
  return out;
});

// ------------------------------------------------------------ The index

/// Cached covers by album key, in memory. Loaded from disk once; rows read it
/// with a `select` on their own key, so only a changed album rebuilds.
final albumArtIndexProvider =
    NotifierProvider<AlbumArtIndex, Map<String, File>>(AlbumArtIndex.new);

class AlbumArtIndex extends Notifier<Map<String, File>> {
  bool _alive = true;

  AlbumArtCache get _cache => ref.read(albumArtCacheProvider);

  @override
  Map<String, File> build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    unawaited(Future<void>.microtask(_load));
    return const {};
  }

  Future<void> _load() async {
    try {
      await _cache.load();
    } catch (_) {}
    if (_alive) state = _cache.files;
  }

  /// The cache changed for [key]: drop the stale decoded picture and publish.
  void changed(String key, {File? before}) {
    try {
      final images = PaintingBinding.instance.imageCache;
      final old = before ?? state[key];
      if (old != null) images.evict(FileImage(old));
      final now = _cache.lookup(key);
      if (now != null) images.evict(FileImage(now));
    } catch (_) {}
    if (_alive) state = _cache.files;
  }

  /// Deletes the fetched cover of [key].
  Future<void> remove(String key) async {
    final before = state[key];
    await _cache.remove(key);
    changed(key, before: before);
  }
}

/// The cached cover of one album, or null. A family per album key.
final albumArtFileProvider = Provider.family<File?, String>(
  (ref, key) => ref.watch(albumArtIndexProvider.select((m) => m[key])),
);

// ------------------------------------------------------------ The finder

/// What one lookup came to, for the UI.
enum ArtFetch {
  found,
  notFound,
  offline,
  rateLimited,
  error,

  /// Not asked: nothing to look up, already cached, or a recent miss.
  skipped,
}

/// Looks one album up and keeps the cache: a found cover is stored, a plain
/// miss is remembered for 30 days, network trouble is not recorded.
class AlbumArtFinder {
  final AlbumArtClient client;
  final AlbumArtCache cache;
  final void Function(String key) onChanged;
  final Set<String> _inFlight = {};

  AlbumArtFinder({
    required this.client,
    required this.cache,
    required this.onChanged,
  });

  /// [force] ignores a cached cover and a recent miss (the user asked for this
  /// album by hand).
  Future<ArtFetch> fetch(AlbumRef album, {bool force = false}) async {
    if (!isLookupWorthy(album.album, album.artist)) return ArtFetch.skipped;
    await cache.load();
    if (!force) {
      if (cache.lookup(album.key) != null) return ArtFetch.skipped;
      if (cache.hasFreshMiss(album.key)) return ArtFetch.skipped;
    }
    if (!_inFlight.add(album.key)) return ArtFetch.skipped;
    try {
      final r = await client.find(album: album.album, artist: album.artist);
      switch (r.outcome) {
        case ArtOutcome.found:
          final file = await cache.store(album.key, r.bytes!, r.extension!);
          if (file == null) return ArtFetch.error;
          onChanged(album.key);
          return ArtFetch.found;
        case ArtOutcome.notFound:
          await cache.recordMiss(album.key);
          return ArtFetch.notFound;
        case ArtOutcome.offline:
          return ArtFetch.offline;
        case ArtOutcome.rateLimited:
          return ArtFetch.rateLimited;
        case ArtOutcome.error:
          return ArtFetch.error;
      }
    } finally {
      _inFlight.remove(album.key);
    }
  }
}

final albumArtFinderProvider = Provider<AlbumArtFinder>(
  (ref) => AlbumArtFinder(
    client: ref.watch(albumArtClientProvider),
    cache: ref.watch(albumArtCacheProvider),
    onChanged: (key) => ref.read(albumArtIndexProvider.notifier).changed(key),
  ),
);

// ------------------------------------------------------------- The batch

enum ArtBatchStatus {
  idle,

  /// Looking through the library for albums without a picture.
  scanning,
  running,
  done,
  cancelled,

  /// Ended early because the network or the service said stop.
  stopped,
}

class ArtBatchState {
  final ArtBatchStatus status;

  /// Albums to look up in this run, and how many are finished / found.
  final int total;
  final int done;
  final int found;

  /// Why a run ended early: offline, rateLimited or error.
  final ArtFetch? stopReason;

  const ArtBatchState({
    this.status = ArtBatchStatus.idle,
    this.total = 0,
    this.done = 0,
    this.found = 0,
    this.stopReason,
  });

  bool get active =>
      status == ArtBatchStatus.scanning || status == ArtBatchStatus.running;
}

/// Albums looked up per automatic run, and the pause before the next one.
const int kAutoArtBatch = 25;
const Duration kAutoArtPause = Duration(minutes: 2);

/// After a network failure the automatic run stays quiet this long.
const Duration kAutoArtBackoff = Duration(hours: 1);

final albumArtBatchProvider =
    NotifierProvider<AlbumArtBatchNotifier, ArtBatchState>(
      AlbumArtBatchNotifier.new,
    );

/// Looks up covers for albums without one, one at a time at the rate limit.
/// State lives here, so a run goes on when the Settings screen is left. Both
/// the manual run (Settings) and the automatic one need the
/// `fetchMissingArt` setting.
class AlbumArtBatchNotifier extends Notifier<ArtBatchState> {
  bool _cancel = false;
  bool _alive = true;
  Timer? _nextBatch;
  DateTime? _autoQuietUntil;

  /// Albums known to have a picture, so a library reload does not probe the
  /// whole library again.
  final Set<String> _hasArt = {};

  @override
  ArtBatchState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _cancel = true;
      _nextBatch?.cancel();
    });
    return const ArtBatchState();
  }

  bool get _enabled => ref.read(settingsProvider).fetchMissingArt;

  void _set(ArtBatchState s) {
    if (_alive) state = s;
  }

  /// The Settings "Find missing artwork" button. Does nothing while a run is
  /// going or when the setting is off.
  Future<void> startManual() => _run(auto: false);

  /// A small batch in the background after a library load; the next one
  /// follows after a pause while albums remain.
  Future<void> startAuto() async {
    final quiet = _autoQuietUntil;
    if (quiet != null && DateTime.now().isBefore(quiet)) return;
    await _run(auto: true);
  }

  /// Stops the current run after the request in flight.
  void cancel() {
    _nextBatch?.cancel();
    if (state.active) _cancel = true;
  }

  Future<void> _run({required bool auto}) async {
    if (state.active || !_enabled) return;
    _nextBatch?.cancel();
    _cancel = false;
    _set(const ArtBatchState(status: ArtBatchStatus.scanning));

    final finder = ref.read(albumArtFinderProvider);
    final gate = ref.read(albumArtForegroundGateProvider);
    final (queue, more) = await _collect(auto ? kAutoArtBatch : null);
    if (_cancel || !_alive) {
      _set(const ArtBatchState(status: ArtBatchStatus.cancelled));
      return;
    }

    var done = 0;
    var found = 0;
    ArtFetch? stop;
    _set(ArtBatchState(status: ArtBatchStatus.running, total: queue.length));
    for (final album in queue) {
      if (_cancel || !_alive) break;
      await gate();
      if (_cancel || !_alive) break;
      // The setting can be turned off while a background run is going.
      if (auto && !_enabled) {
        _cancel = true;
        break;
      }
      ArtFetch result;
      try {
        result = await finder.fetch(album);
      } catch (_) {
        result = ArtFetch.error;
      }
      done++;
      if (result == ArtFetch.found) found++;
      _set(
        ArtBatchState(
          status: ArtBatchStatus.running,
          total: queue.length,
          done: done,
          found: found,
        ),
      );
      if (result == ArtFetch.offline ||
          result == ArtFetch.rateLimited ||
          result == ArtFetch.error) {
        stop = result;
        break;
      }
    }

    final status = stop != null
        ? ArtBatchStatus.stopped
        : (_cancel ? ArtBatchStatus.cancelled : ArtBatchStatus.done);
    _set(
      ArtBatchState(
        status: status,
        total: queue.length,
        done: done,
        found: found,
        stopReason: stop,
      ),
    );

    if (stop != null && auto) {
      // No retry storm: stay quiet for a while.
      _autoQuietUntil = DateTime.now().add(kAutoArtBackoff);
    } else if (auto && more && status == ArtBatchStatus.done && _alive) {
      _nextBatch = Timer(kAutoArtPause, () => unawaited(startAuto()));
    }
  }

  /// Albums worth asking about: a real album and artist, no picture in
  /// MediaStore, no cached cover, no recent miss. At most [limit] of them;
  /// the second value says whether more were left.
  Future<(List<AlbumRef>, bool)> _collect(int? limit) async {
    final cache = ref.read(albumArtCacheProvider);
    final probe = ref.read(albumArtProbeProvider);
    await cache.load();
    final albums = ref.read(libraryProvider).albums;
    final out = <AlbumRef>[];
    var checked = 0;
    for (final a in albums) {
      if (_cancel || !_alive) break;
      final r = albumRefForAlbum(a);
      if (!isLookupWorthy(r.album, r.artist)) continue;
      if (_hasArt.contains(r.key)) continue;
      if (cache.lookup(r.key) != null || cache.hasFreshMiss(r.key)) continue;
      if (++checked % 16 == 0) await Future<void>.delayed(Duration.zero);
      if (await probe(a.id)) {
        _hasArt.add(r.key);
        continue;
      }
      if (limit != null && out.length >= limit) return (out, true);
      out.add(r);
    }
    return (out, false);
  }
}

/// Starts the automatic runs and hands the notification the cached covers.
/// Watch it once from the app root (the audio coordinator does).
///
/// With the setting on, a library load or switching the setting on starts a
/// small batch after [albumArtAutoDelayProvider]; switching it off stops it.
final albumArtAutoProvider = Provider<void>((ref) {
  Timer? pending;
  ref.onDispose(() => pending?.cancel());

  void schedule() {
    pending?.cancel();
    if (!ref.read(settingsProvider).fetchMissingArt) return;
    if (ref.read(libraryProvider).albums.isEmpty) return;
    final delay = ref.read(albumArtAutoDelayProvider);
    void go() =>
        unawaited(ref.read(albumArtBatchProvider.notifier).startAuto());
    if (delay == Duration.zero) {
      // Not while this provider is still being built.
      scheduleMicrotask(go);
    } else {
      pending = Timer(delay, go);
    }
  }

  ref.listen(settingsProvider.select((s) => s.fetchMissingArt), (_, on) {
    if (on) {
      schedule();
    } else {
      pending?.cancel();
      ref.read(albumArtBatchProvider.notifier).cancel();
    }
  });
  ref.listen(libraryProvider.select((s) => s.albums), (_, _) => schedule());
  schedule();

  // Notification and lock screen: a fetched cover as a file URI.
  try {
    ref.read(audioHandlerProvider).cachedArtUri = (song) {
      final r = albumRefForSong(song);
      if (r == null) return null;
      return ref.read(albumArtIndexProvider)[r.key]?.uri;
    };
  } catch (_) {
    // No audio handler (tests).
  }
});

/// Wait before the first automatic batch, so it does not compete with start-up.
final albumArtAutoDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 8),
);

// --------------------------------------------------------- Cached pictures

/// The fetched cover of a song's album as a small PNG (about [px] wide), for
/// the palette and the home widget; null when there is none or it cannot be
/// read. The file is only read when this is called.
Future<Uint8List?> cachedArtThumbForSong(
  Ref ref,
  int songId, {
  int px = 200,
}) async {
  try {
    final key = ref.read(songArtRefsProvider)[songId]?.key;
    if (key == null) return null;
    final file = ref.read(albumArtIndexProvider)[key];
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: px);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
