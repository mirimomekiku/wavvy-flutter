import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/db/db.dart';

/// Where the listening history is kept. Overridden in tests.
abstract class HistoryStore {
  Future<void> log(Map<String, Object?> row);

  /// Plays at or after [sinceMs] (milliseconds since the epoch), newest first.
  Future<List<Map<String, Object?>>> rows({int? sinceMs});
  Future<void> clear();
}

class DbHistoryStore implements HistoryStore {
  final DbHelper _db = DbHelper();

  @override
  Future<void> log(Map<String, Object?> row) => _db.logHistory(row);

  @override
  Future<List<Map<String, Object?>>> rows({int? sinceMs}) =>
      _db.historyRows(sinceMs: sinceMs);

  @override
  Future<void> clear() => _db.clearHistory();
}

final historyStoreProvider = Provider<HistoryStore>((ref) => DbHistoryStore());

/// Records counted plays. The caller has already decided a play counts (and
/// that incognito mode is off).
class HistoryLogger {
  HistoryLogger(this._store);
  final HistoryStore _store;

  Future<void> logPlay(SongModel song) async {
    try {
      await _store.log({
        'song_id': song.id,
        'played_at': DateTime.now().millisecondsSinceEpoch,
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
        'duration': song.duration,
      });
    } catch (e) {
      // A missed history row is better than a broken player.
      debugPrint('could not log play: $e');
    }
  }
}

final historyLoggerProvider = Provider<HistoryLogger>(
  (ref) => HistoryLogger(ref.watch(historyStoreProvider)),
);

// ---------------------------------------------------------------- statistics

enum StatsPeriod {
  week('7 days', 7),
  month('30 days', 30),
  all('All time', null);

  const StatsPeriod(this.label, this.days);
  final String label;

  /// Null for all time.
  final int? days;
}

/// One play, read back from a `play_history` row.
class PlayEntry {
  const PlayEntry({
    required this.songId,
    required this.playedAt,
    required this.title,
    this.artist,
    this.album,
    this.durationMs,
  });

  final int songId;
  final DateTime playedAt;
  final String title;
  final String? artist;
  final String? album;
  final int? durationMs;

  factory PlayEntry.fromRow(Map<String, Object?> row) => PlayEntry(
    songId: (row['song_id'] as num?)?.toInt() ?? 0,
    playedAt: DateTime.fromMillisecondsSinceEpoch(
      (row['played_at'] as num?)?.toInt() ?? 0,
    ),
    title: (row['title'] as String?) ?? '',
    artist: row['artist'] as String?,
    album: row['album'] as String?,
    durationMs: (row['duration'] as num?)?.toInt(),
  );
}

/// A ranked name (or song) with how often it was played.
class TopItem {
  const TopItem({
    required this.name,
    required this.plays,
    this.songId,
    this.subtitle,
  });
  final String name;
  final int plays;

  /// Set for songs only.
  final int? songId;

  /// The artist, for songs.
  final String? subtitle;
}

class StatsSummary {
  const StatsSummary({
    required this.totalPlays,
    required this.uniqueSongs,
    required this.uniqueArtists,
    required this.listening,
    required this.topSongs,
    required this.topArtists,
    required this.topAlbums,
    required this.dailyPlays,
    required this.recent,
  });

  static const empty = StatsSummary(
    totalPlays: 0,
    uniqueSongs: 0,
    uniqueArtists: 0,
    listening: Duration.zero,
    topSongs: [],
    topArtists: [],
    topAlbums: [],
    dailyPlays: [
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
    ],
    recent: [],
  );

  final int totalPlays;
  final int uniqueSongs;
  final int uniqueArtists;

  /// Estimated: the summed length of the songs played, whether or not each
  /// one was heard to the end.
  final Duration listening;
  final List<TopItem> topSongs;
  final List<TopItem> topArtists;
  final List<TopItem> topAlbums;

  /// Plays on each of the last 14 local days, oldest first (today is last).
  /// Not limited by the period.
  final List<int> dailyPlays;

  /// The most recent 100 plays in the period, newest first.
  final List<PlayEntry> recent;

  static const days = 14;
  static const topCount = 10;
  static const recentCount = 100;

  /// True when the chosen period has no plays.
  bool get isEmpty => totalPlays == 0;

  static bool _named(String? s) {
    final t = s?.trim().toLowerCase() ?? '';
    return t.isNotEmpty && t != '<unknown>';
  }

  factory StatsSummary.fromRows(
    Iterable<Map<String, Object?>> rows, {
    required DateTime now,
    required StatsPeriod period,
  }) {
    final all = [for (final r in rows) PlayEntry.fromRow(r)]
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));

    // Local-day buckets: whole days between local midnights (DST safe).
    final today = DateTime(now.year, now.month, now.day);
    final daily = List<int>.filled(days, 0);
    for (final e in all) {
      final d = DateTime(e.playedAt.year, e.playedAt.month, e.playedAt.day);
      final ago = (today.difference(d).inHours / 24).round();
      if (ago >= 0 && ago < days) daily[days - 1 - ago]++;
    }

    final span = period.days;
    final cutoff = span == null ? null : now.subtract(Duration(days: span));
    final plays = [
      for (final e in all)
        if ((cutoff == null || !e.playedAt.isBefore(cutoff)) &&
            !e.playedAt.isAfter(now))
          e,
    ];

    var ms = 0;
    final songs = <int, _Tally>{};
    final artists = <String, _Tally>{};
    final albums = <String, _Tally>{};
    // Newest first, so the first sight of a key is its latest play and name.
    for (final e in plays) {
      ms += e.durationMs ?? 0;
      songs.putIfAbsent(e.songId, () => _Tally(e.title, e.artist)).plays++;
      if (_named(e.artist)) {
        artists
            .putIfAbsent(e.artist!.trim(), () => _Tally(e.artist!.trim()))
            .plays++;
      }
      if (_named(e.album)) {
        albums
            .putIfAbsent(
              e.album!.trim(),
              () => _Tally(e.album!.trim(), e.artist),
            )
            .plays++;
      }
    }

    List<TopItem> top<K>(Map<K, _Tally> m, {bool ids = false}) {
      // Map order is first insertion = most recent play, and sort is stable.
      final entries = m.entries.toList()
        ..sort((a, b) => b.value.plays.compareTo(a.value.plays));
      return [
        for (final e in entries.take(topCount))
          TopItem(
            name: e.value.name,
            plays: e.value.plays,
            songId: ids ? e.key as int : null,
            subtitle: e.value.sub,
          ),
      ];
    }

    return StatsSummary(
      totalPlays: plays.length,
      uniqueSongs: songs.length,
      uniqueArtists: artists.length,
      listening: Duration(milliseconds: ms),
      topSongs: top(songs, ids: true),
      topArtists: top(artists),
      topAlbums: top(albums),
      dailyPlays: daily,
      recent: plays.take(recentCount).toList(),
    );
  }
}

class _Tally {
  _Tally(this.name, [this.sub]);
  final String name;
  final String? sub;
  int plays = 0;
}

/// "4h 05m", "35 min", "0 min".
String formatListening(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h < 100) return '${h}h ${m.toString().padLeft(2, '0')}m';
  return '${h}h';
}

/// "Just now", "5 min ago", "3 h ago", "Yesterday", "4 days ago", else a date.
String relativeTime(DateTime then, DateTime now) {
  final diff = now.difference(then);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(then.year, then.month, then.day);
  final daysAgo = (today.difference(day).inHours / 24).round();
  if (daysAgo <= 0) return '${diff.inHours} h ago';
  if (daysAgo == 1) return 'Yesterday';
  if (daysAgo < 7) return '$daysAgo days ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final year = then.year == now.year ? '' : ' ${then.year}';
  return '${months[then.month - 1]} ${then.day}$year';
}

/// The period shown on the stats screen.
final statsPeriodProvider = NotifierProvider<StatsPeriodNotifier, StatsPeriod>(
  StatsPeriodNotifier.new,
);

class StatsPeriodNotifier extends Notifier<StatsPeriod> {
  @override
  StatsPeriod build() => StatsPeriod.week;

  void set(StatsPeriod p) => state = p;
}

/// The summary for the chosen period: loading, error or data.
final statsProvider = AsyncNotifierProvider<StatsNotifier, StatsSummary>(
  StatsNotifier.new,
);

class StatsNotifier extends AsyncNotifier<StatsSummary> {
  @override
  Future<StatsSummary> build() async {
    final period = ref.watch(statsPeriodProvider);
    final store = ref.read(historyStoreProvider);
    final now = DateTime.now();
    // The 14-day chart needs two weeks even for the 7-day period.
    final span = period.days;
    final since = span == null
        ? null
        : now
              .subtract(
                Duration(
                  days: span < StatsSummary.days ? StatsSummary.days : span,
                ),
              )
              // Start of that day, so the oldest chart day is complete.
              .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0)
              .millisecondsSinceEpoch;
    final rows = await store.rows(sinceMs: since);
    return StatsSummary.fromRows(rows, now: now, period: period);
  }

  /// Deletes every recorded play and reloads.
  Future<void> clear() async {
    await ref.read(historyStoreProvider).clear();
    ref.invalidateSelf();
    await future;
  }
}
