import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:wavvy/db/db.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

/// Local playlists plus the history-based smart lists (most played, recent).
class PlaylistsState {
  /// Rows of the `playlists` table: {id, name, created_at}.
  final List<Map<String, dynamic>> playlists;
  final List<SongModel> mostPlayed;
  final List<SongModel> recent;

  /// Bumped whenever playlist membership changes so family providers that
  /// read it (playlistSongsProvider) refresh.
  final int revision;

  const PlaylistsState({
    this.playlists = const [],
    this.mostPlayed = const [],
    this.recent = const [],
    this.revision = 0,
  });

  PlaylistsState copyWith({
    List<Map<String, dynamic>>? playlists,
    List<SongModel>? mostPlayed,
    List<SongModel>? recent,
    int? revision,
  }) => PlaylistsState(
    playlists: playlists ?? this.playlists,
    mostPlayed: mostPlayed ?? this.mostPlayed,
    recent: recent ?? this.recent,
    revision: revision ?? this.revision,
  );
}

final playlistsProvider = NotifierProvider<PlaylistsNotifier, PlaylistsState>(
  PlaylistsNotifier.new,
);

/// Songs of one playlist, in insertion order, refreshed when the library or
/// playlist membership changes.
final playlistSongsProvider = FutureProvider.family<List<SongModel>, int>((
  ref,
  playlistId,
) {
  ref.watch(playlistsProvider.select((s) => s.revision));
  return ref.read(playlistsProvider.notifier).getSongsInPlaylist(playlistId);
});

/// Playlist and smart-playlist logic over DbHelper (lib/db/db.dart).
class PlaylistsNotifier extends Notifier<PlaylistsState> {
  final DbHelper _dbHelper = DbHelper();
  bool _disposed = false;

  /// Loads playlists + smart playlists on first build (not awaited).
  @override
  PlaylistsState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    Future.microtask(() async {
      try {
        await refreshLocalPlaylists();
        await refreshSmartPlaylists();
      } catch (_) {}
    });
    return const PlaylistsState();
  }

  Future<void> refreshLocalPlaylists() async {
    final db = await _dbHelper.db;
    final List<Map<String, dynamic>> maps = await db.query('playlists');
    if (_disposed) return;
    state = state.copyWith(playlists: List<Map<String, dynamic>>.from(maps));
  }

  Future<void> createLocalPlaylist(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = await _dbHelper.db;
    await db.insert('playlists', {
      'name': trimmed,
      'created_at': DateTime.now().toIso8601String(),
    });
    await refreshLocalPlaylists();
  }

  Future<void> deleteLocalPlaylist(int playlistId) async {
    await _dbHelper.deletePlaylist(playlistId);
    await refreshLocalPlaylists();
    _bumpRevision();
  }

  /// Unique-index insert with ConflictAlgorithm.ignore; rowId > 0 => "Success"
  /// snackbar, else "Song is already in this playlist". Bumps revision.
  Future<void> addSongToLocalPlaylist(int playlistId, int songId) async {
    final db = await _dbHelper.db;
    // A unique index on (playlist_id, song_id) rejects duplicates atomically.
    final rowId = await db.insert('playlist_songs', {
      'playlist_id': playlistId,
      'song_id': songId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    if (rowId > 0) {
      AppSnackbar.showSuccess("Success", "Added to your playlist");
    } else {
      AppSnackbar.showSnackbar("Notice", "Song is already in this playlist");
    }
    _bumpRevision();
  }

  /// Adds several songs in one go, skipping the ones already in the
  /// playlist, and says how many were new.
  Future<void> addSongsToLocalPlaylist(
    int playlistId,
    List<int> songIds,
  ) async {
    final db = await _dbHelper.db;
    var added = 0;
    await db.transaction((txn) async {
      for (final songId in songIds) {
        final rowId = await txn.insert('playlist_songs', {
          'playlist_id': playlistId,
          'song_id': songId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (rowId > 0) added++;
      }
    });
    if (added == 0) {
      AppSnackbar.showSnackbar("Notice", "Already in this playlist");
    } else if (added == songIds.length) {
      AppSnackbar.showSuccess(
        "Success",
        added == 1 ? "Added to your playlist" : "Added $added songs",
      );
    } else {
      AppSnackbar.showSuccess(
        "Success",
        "Added $added songs; ${songIds.length - added} were already there",
      );
    }
    _bumpRevision();
  }

  Future<void> removeFromLocalPlaylist(int playlistId, int songId) async {
    final db = await _dbHelper.db;
    await db.delete(
      'playlist_songs',
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
    );
    _bumpRevision();
  }

  /// Reads libraryProvider songs; keeps insertion order, skips missing songs.
  Future<List<SongModel>> getSongsInPlaylist(int playlistId) async {
    final db = await _dbHelper.db;
    final List<Map<String, dynamic>> results = await db.query(
      'playlist_songs',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'id ASC',
    );

    // Keep insertion order; skip songs no longer on the device.
    final songMap = {for (var s in ref.read(libraryProvider).songs) s.id: s};
    return [
      for (final row in results)
        if (songMap[row['song_id'] as int] != null)
          songMap[row['song_id'] as int]!,
    ];
  }

  /// Rebuilds mostPlayed / recent (top 20) from DbHelper + library songs.
  /// [bumpRevision] is true when the library itself changed, so playlist song
  /// lists get re-resolved against the new library.
  Future<void> refreshSmartPlaylists({bool bumpRevision = false}) async {
    final mostPlayedMaps = await _dbHelper.getMostPlayed(20);
    final recentMaps = await _dbHelper.getRecentlyPlayed(20);
    if (_disposed) return;

    final songMap = {for (var s in ref.read(libraryProvider).songs) s.id: s};

    final List<SongModel> tempMostPlayed = [];
    for (var map in mostPlayedMaps) {
      final song = songMap[map['song_id']];
      if (song != null) tempMostPlayed.add(song);
    }

    final List<SongModel> tempRecent = [];
    for (var map in recentMaps) {
      final song = songMap[map['song_id']];
      if (song != null) tempRecent.add(song);
    }

    state = state.copyWith(
      mostPlayed: tempMostPlayed,
      recent: tempRecent,
      revision: bumpRevision ? state.revision + 1 : state.revision,
    );
  }

  /// DbHelper.logSongPlay then refreshSmartPlaylists.
  Future<void> logSongPlay(int songId) async {
    await _dbHelper.logSongPlay(songId);
    await refreshSmartPlaylists();
  }

  void _bumpRevision() {
    if (_disposed) return;
    state = state.copyWith(revision: state.revision + 1);
  }
}
