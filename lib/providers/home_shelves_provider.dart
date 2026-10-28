import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/db/db.dart';
import 'package:wavvy/playback/history.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';

/// Albums in "Continue listening".
const continueLimit = 10;

/// Songs in "Rediscover", and how few candidates hide the shelf.
const rediscoverLimit = 20;
const rediscoverMinCandidates = 8;

/// A song not played for this long counts as forgotten.
const rediscoverAfter = Duration(days: 90);

/// How often and when a song was played (a `song_stats` row).
class SongStat {
  const SongStat({this.playCount = 0, this.lastPlayedMs});
  final int playCount;
  final int? lastPlayedMs;
}

/// Where the per-song play stats are read from. Overridden in tests.
abstract class SongStatsStore {
  Future<Map<int, SongStat>> load();
}

class DbSongStatsStore implements SongStatsStore {
  @override
  Future<Map<int, SongStat>> load() async {
    final rows = await DbHelper().getMostPlayed(100000);
    return {
      for (final r in rows)
        (r['song_id'] as num).toInt(): SongStat(
          playCount: (r['play_count'] as num?)?.toInt() ?? 0,
          lastPlayedMs: (r['last_played'] as num?)?.toInt(),
        ),
    };
  }
}

final songStatsStoreProvider = Provider<SongStatsStore>(
  (ref) => DbSongStatsStore(),
);

/// The albums played most recently, newest first, one tile per album. A play
/// maps to its album by song id, else by album name and artist; albums no
/// longer in the library are skipped.
List<AlbumModel> buildContinueListening({
  required List<Map<String, Object?>> rows,
  required List<SongModel> songs,
  required List<AlbumModel> albums,
  int limit = continueLimit,
}) {
  if (rows.isEmpty || albums.isEmpty) return const [];
  final plays = [for (final r in rows) PlayEntry.fromRow(r)]
    ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
  final albumById = {for (final a in albums) a.id: a};
  final songAlbum = {
    for (final s in songs)
      if (s.albumId != null) s.id: s.albumId!,
  };
  String key(String? album, String? artist) =>
      '${album?.trim().toLowerCase()}\u0000${artist?.trim().toLowerCase()}';
  final byName = <String, AlbumModel>{};
  for (final a in albums) {
    byName.putIfAbsent(key(a.album, a.artist), () => a);
  }

  final seen = <int>{};
  final out = <AlbumModel>[];
  for (final p in plays) {
    final byId = albumById[songAlbum[p.songId]];
    final album =
        byId ??
        ((p.album ?? '').trim().isEmpty
            ? null
            : byName[key(p.album, p.artist)]);
    if (album == null || !seen.add(album.id)) continue;
    out.add(album);
    if (out.length >= limit) break;
  }
  return out;
}

/// The seed for [now]'s day; [reroll] moves it to another pick.
int shelfSeed(DateTime now, [int reroll = 0]) =>
    (now.year * 10000 + now.month * 100 + now.day) * 31 + 7 + reroll * 7919;

/// Up to [limit] songs not played for 90 days (or never), picked at random
/// but the same for a given [seed]. Empty below [rediscoverMinCandidates].
List<SongModel> buildRediscover({
  required List<SongModel> songs,
  required Map<int, SongStat> stats,
  required DateTime now,
  required int seed,
  int limit = rediscoverLimit,
}) {
  final cutoff = now.subtract(rediscoverAfter).millisecondsSinceEpoch;
  final candidates = [
    for (final s in songs)
      if (stats[s.id]?.lastPlayedMs == null ||
          stats[s.id]!.lastPlayedMs! < cutoff)
        s,
  ];
  if (candidates.length < rediscoverMinCandidates) return const [];
  // Sorted first so the pick does not depend on the library's sort order.
  candidates.sort((a, b) => a.id.compareTo(b.id));
  candidates.shuffle(Random(seed));
  return candidates.take(limit).toList();
}

/// Recent plays, re-read whenever the recent list changes (a counted play).
final _historyRowsProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  ref.watch(playlistsProvider.select((s) => s.recent));
  try {
    final since = DateTime.now()
        .subtract(const Duration(days: 90))
        .millisecondsSinceEpoch;
    return await ref.read(historyStoreProvider).rows(sinceMs: since);
  } catch (e) {
    debugPrint('could not read history for Home: $e');
    return const [];
  }
});

/// Empty until the history is read, and when nothing was recorded.
final continueListeningProvider = Provider<List<AlbumModel>>((ref) {
  final rows = ref.watch(_historyRowsProvider).valueOrNull;
  if (rows == null || rows.isEmpty) return const [];
  return buildContinueListening(
    rows: rows,
    songs: ref.watch(libraryProvider.select((s) => s.songs)),
    albums: ref.watch(libraryProvider.select((s) => s.albums)),
  );
});

/// Read once per session: a song played now stays on the shelf until the
/// next launch, which keeps the day's pick steady.
final songStatsProvider = FutureProvider<Map<int, SongStat>>((ref) async {
  try {
    return await ref.read(songStatsStoreProvider).load();
  } catch (e) {
    debugPrint('could not read song stats for Home: $e');
    return const {};
  }
});

/// How many times "Shuffle" was pressed on the Rediscover shelf.
final rediscoverRerollProvider =
    NotifierProvider<RediscoverRerollNotifier, int>(
      RediscoverRerollNotifier.new,
    );

class RediscoverRerollNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void reroll() => state++;
}

/// Empty until the stats are read (so nothing looks "never played" early).
final rediscoverProvider = Provider<List<SongModel>>((ref) {
  final stats = ref.watch(songStatsProvider).valueOrNull;
  if (stats == null) return const [];
  final now = DateTime.now();
  return buildRediscover(
    songs: ref.watch(libraryProvider.select((s) => s.songs)),
    stats: stats,
    now: now,
    seed: shelfSeed(now, ref.watch(rediscoverRerollProvider)),
  );
});
