import 'package:flutter_test/flutter_test.dart';
import 'package:wavvy/playback/history.dart';

// A Wednesday at noon, local time.
final _now = DateTime(2025, 6, 11, 12);

Map<String, Object?> _row(
  int song,
  DateTime at, {
  String? title,
  String? artist = 'Artist',
  String? album = 'Album',
  int duration = 60000,
}) => {
  'song_id': song,
  'played_at': at.millisecondsSinceEpoch,
  'title': title ?? 'Song $song',
  'artist': artist,
  'album': album,
  'duration': duration,
};

DateTime _ago({int days = 0, int hours = 0, int minutes = 0}) =>
    _now.subtract(Duration(days: days, hours: hours, minutes: minutes));

StatsSummary _sum(List<Map<String, Object?>> rows, StatsPeriod p) =>
    StatsSummary.fromRows(rows, now: _now, period: p);

void main() {
  group('periods', () {
    final rows = [
      _row(1, _ago(hours: 1)),
      _row(2, _ago(days: 6)),
      _row(3, _ago(days: 20)),
      _row(4, _ago(days: 100)),
    ];

    test('week, month and all select by age', () {
      expect(_sum(rows, StatsPeriod.week).totalPlays, 2);
      expect(_sum(rows, StatsPeriod.month).totalPlays, 3);
      expect(_sum(rows, StatsPeriod.all).totalPlays, 4);
    });

    test('empty input is empty', () {
      final s = _sum(const [], StatsPeriod.all);
      expect(s.isEmpty, isTrue);
      expect(s.dailyPlays, List.filled(14, 0));
      expect(s.topSongs, isEmpty);
      expect(s.listening, Duration.zero);
    });

    test('plays in the future are ignored', () {
      final s = _sum([
        _row(1, _now.add(const Duration(days: 1))),
      ], StatsPeriod.all);
      expect(s.totalPlays, 0);
    });
  });

  group('totals', () {
    test('unique songs and artists, and estimated listening time', () {
      final rows = [
        _row(1, _ago(hours: 1), artist: 'A', duration: 120000),
        _row(1, _ago(hours: 2), artist: 'A', duration: 120000),
        _row(2, _ago(hours: 3), artist: 'B', duration: 30000),
        _row(3, _ago(hours: 4), artist: '<unknown>', duration: 0),
      ];
      final s = _sum(rows, StatsPeriod.week);
      expect(s.totalPlays, 4);
      expect(s.uniqueSongs, 3);
      expect(s.uniqueArtists, 2);
      expect(s.listening, const Duration(minutes: 4, seconds: 30));
    });

    test('a null duration counts as zero', () {
      final r = _row(1, _ago(hours: 1))..['duration'] = null;
      expect(_sum([r], StatsPeriod.all).listening, Duration.zero);
    });
  });

  group('top lists', () {
    test('ranked by plays, at most ten', () {
      final rows = [
        for (var song = 1; song <= 12; song++)
          for (var n = 0; n < song; n++)
            _row(song, _ago(minutes: song * 20 + n)),
      ];
      final top = _sum(rows, StatsPeriod.week).topSongs;
      expect(top.length, 10);
      expect(top.first.songId, 12);
      expect(top.first.plays, 12);
      expect(top.last.songId, 3);
    });

    test('ties go to the most recently played', () {
      final rows = [
        _row(1, _ago(hours: 5)),
        _row(2, _ago(hours: 1)),
        _row(3, _ago(hours: 3)),
      ];
      final top = _sum(rows, StatsPeriod.week).topSongs;
      expect([for (final t in top) t.songId], [2, 3, 1]);
    });

    test('a tie is broken by the latest play, not the first', () {
      final rows = [
        _row(1, _ago(hours: 10)),
        _row(1, _ago(hours: 1)),
        _row(2, _ago(hours: 3)),
        _row(2, _ago(hours: 4)),
      ];
      final top = _sum(rows, StatsPeriod.week).topSongs;
      expect([for (final t in top) t.songId], [1, 2]);
    });

    test('rows are accepted in any order', () {
      final rows = [_row(1, _ago(hours: 5)), _row(2, _ago(hours: 1))];
      final top = _sum(rows.reversed.toList(), StatsPeriod.week).topSongs;
      expect(top.first.songId, 2);
    });

    test('artists and albums skip empty and unknown names', () {
      final rows = [
        _row(1, _ago(hours: 1), artist: '<unknown>', album: '<unknown>'),
        _row(2, _ago(hours: 2), artist: '', album: ''),
        _row(3, _ago(hours: 3), artist: null, album: null),
        _row(4, _ago(hours: 4), artist: 'Real', album: 'Disc'),
        _row(5, _ago(hours: 5), artist: 'Real', album: 'Disc'),
      ];
      final s = _sum(rows, StatsPeriod.week);
      expect([for (final t in s.topArtists) t.name], ['Real']);
      expect(s.topArtists.single.plays, 2);
      expect([for (final t in s.topAlbums) t.name], ['Disc']);
      // Songs still count even without an artist.
      expect(s.topSongs.length, 5);
      expect(s.uniqueArtists, 1);
    });

    test('a song keeps its latest title', () {
      final rows = [
        _row(1, _ago(hours: 1), title: 'New name'),
        _row(1, _ago(hours: 2), title: 'Old name'),
      ];
      expect(_sum(rows, StatsPeriod.week).topSongs.single.name, 'New name');
    });
  });

  group('daily buckets', () {
    test('14 local days, oldest first, today last', () {
      final rows = [
        _row(1, DateTime(2025, 6, 11, 0, 5)),
        _row(1, DateTime(2025, 6, 11, 11)),
        _row(2, DateTime(2025, 6, 10, 23, 59)),
        _row(3, DateTime(2025, 5, 29, 8)),
        _row(4, DateTime(2025, 5, 28, 8)),
      ];
      final d = _sum(rows, StatsPeriod.all).dailyPlays;
      expect(d.length, 14);
      expect(d.last, 2);
      expect(d[12], 1);
      // 13 days ago is the first bucket; 14 days ago falls off.
      expect(d.first, 1);
      expect(d.fold<int>(0, (a, b) => a + b), 4);
    });

    test('the chart ignores the period', () {
      final rows = [_row(1, _ago(days: 10))];
      final s = _sum(rows, StatsPeriod.week);
      expect(s.totalPlays, 0);
      expect(s.dailyPlays.fold<int>(0, (a, b) => a + b), 1);
    });
  });

  group('recent', () {
    test('newest first and capped at 100', () {
      final rows = [
        for (var i = 0; i < 130; i++) _row(i, _ago(minutes: i + 1)),
      ];
      final s = _sum(rows, StatsPeriod.week);
      expect(s.recent.length, 100);
      expect(s.recent.first.songId, 0);
      expect(s.recent.last.songId, 99);
    });
  });

  group('formatting', () {
    test('listening time', () {
      expect(formatListening(Duration.zero), '0 min');
      expect(formatListening(const Duration(minutes: 35)), '35 min');
      expect(formatListening(const Duration(hours: 4, minutes: 5)), '4h 05m');
      expect(formatListening(const Duration(hours: 120, minutes: 5)), '120h');
    });

    test('relative time', () {
      expect(relativeTime(_ago(), _now), 'Just now');
      expect(relativeTime(_ago(minutes: 5), _now), '5 min ago');
      expect(relativeTime(_ago(hours: 3), _now), '3 h ago');
      expect(relativeTime(DateTime(2025, 6, 10, 23), _now), 'Yesterday');
      expect(relativeTime(DateTime(2025, 6, 8, 9), _now), '3 days ago');
      expect(relativeTime(DateTime(2025, 5, 1, 9), _now), 'May 1');
      expect(relativeTime(DateTime(2024, 5, 1, 9), _now), 'May 1 2024');
    });
  });
}
