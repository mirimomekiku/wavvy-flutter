import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';

enum QuickAccessKind { playlist, album, song }

/// One compact entry of the 2-column grid at the top of Home.
class QuickAccessItem {
  final QuickAccessKind kind;
  final String title;

  /// Playlist id, album id or song id depending on [kind].
  final int id;
  final AlbumModel? album;
  final SongModel? song;

  const QuickAccessItem({
    required this.kind,
    required this.title,
    required this.id,
    this.album,
    this.song,
  });
}

/// Everything Home shows, derived from local data only.
class HomeFeed {
  final List<SongModel> recentSongs;
  final List<SongModel> mostPlayed;
  final List<AlbumModel> recentAlbums;
  final List<SongModel> recentlyAdded;
  final List<ArtistModel> topArtists;
  final ArtistModel? moreFromArtist;
  final List<SongModel> moreFrom;
  final List<SongModel> dailyMix;
  final List<SongModel> discover;
  final List<Map<String, dynamic>> playlists;
  final List<QuickAccessItem> quickAccess;

  const HomeFeed({
    this.recentSongs = const [],
    this.mostPlayed = const [],
    this.recentAlbums = const [],
    this.recentlyAdded = const [],
    this.topArtists = const [],
    this.moreFromArtist,
    this.moreFrom = const [],
    this.dailyMix = const [],
    this.discover = const [],
    this.playlists = const [],
    this.quickAccess = const [],
  });
}

bool _belongs(SongModel song, ArtistModel artist) {
  if (song.artistId != null && song.artistId == artist.id) return true;
  final name = song.artist;
  return name != null && name == artist.artist;
}

List<SongModel> _seededShuffle(List<SongModel> songs, int seed) {
  // Sort by id first so the result doesn't depend on the library's sort order.
  final list = List<SongModel>.from(songs)
    ..sort((a, b) => a.id.compareTo(b.id));
  list.shuffle(Random(seed));
  return list;
}

/// Pure derivation of the Home feed (no I/O, no Riverpod).
HomeFeed buildHomeFeed({
  required List<SongModel> songs,
  required List<AlbumModel> albums,
  required List<ArtistModel> artists,
  required List<SongModel> recent,
  required List<SongModel> mostPlayed,
  required List<Map<String, dynamic>> playlists,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final seed = today.year * 10000 + today.month * 100 + today.day;

  // Recently added songs.
  final byDate = List<SongModel>.from(songs)
    ..sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
  final recentlyAdded = byDate.take(20).toList();

  // Albums by their newest song.
  final newestPerAlbum = <int, int>{};
  for (final s in songs) {
    final albumId = s.albumId;
    if (albumId == null) continue;
    final added = s.dateAdded ?? 0;
    final prev = newestPerAlbum[albumId];
    if (prev == null || added > prev) newestPerAlbum[albumId] = added;
  }
  final indexed = [for (var i = 0; i < albums.length; i++) (i, albums[i])];
  indexed.sort((x, y) {
    final dx = newestPerAlbum[x.$2.id] ?? 0;
    final dy = newestPerAlbum[y.$2.id] ?? 0;
    final c = dy.compareTo(dx);
    return c != 0 ? c : x.$1.compareTo(y.$1);
  });
  final recentAlbums = [for (final e in indexed.take(12)) e.$2];

  // Top artists by presence in history.
  final history = [...mostPlayed, ...recent];
  final scored = <(int, int, ArtistModel)>[];
  for (var i = 0; i < artists.length; i++) {
    final artist = artists[i];
    final score = history.where((s) => _belongs(s, artist)).length;
    if (score > 0) scored.add((score, i, artist));
  }
  scored.sort((x, y) {
    final c = y.$1.compareTo(x.$1);
    return c != 0 ? c : x.$2.compareTo(y.$2);
  });
  final topArtists = [for (final e in scored.take(10)) e.$3];

  // More from the #1 artist.
  final recentIds = {for (final s in recent) s.id};
  final ArtistModel? topArtist = topArtists.isEmpty ? null : topArtists.first;
  final moreFrom = topArtist == null
      ? <SongModel>[]
      : songs
            .where((s) => _belongs(s, topArtist) && !recentIds.contains(s.id))
            .take(15)
            .toList();

  // Daily mix + discover, stable within a day.
  final dailyMix = _seededShuffle(songs, seed).take(25).toList();
  final playedIds = {...recentIds, for (final s in mostPlayed) s.id};
  final discover = _seededShuffle(
    songs.where((s) => !playedIds.contains(s.id)).toList(),
    seed + 1,
  ).take(15).toList();

  // Quick access: playlists, recent albums, albums of recent songs, then
  // recently added songs as a filler for tiny libraries.
  final quick = <QuickAccessItem>[];
  for (final p in playlists.take(2)) {
    quick.add(
      QuickAccessItem(
        kind: QuickAccessKind.playlist,
        title: '${p['name']}',
        id: p['id'] as int,
      ),
    );
  }
  final seenAlbums = <int>{};
  void addAlbum(AlbumModel album) {
    if (quick.length < 6 && seenAlbums.add(album.id)) {
      quick.add(
        QuickAccessItem(
          kind: QuickAccessKind.album,
          title: album.album,
          id: album.id,
          album: album,
        ),
      );
    }
  }

  for (final album in recentAlbums) {
    addAlbum(album);
  }
  final albumById = {for (final a in albums) a.id: a};
  for (final s in recent) {
    final album = albumById[s.albumId];
    if (album != null) addAlbum(album);
  }
  for (final s in recentlyAdded) {
    if (quick.length >= 6) break;
    quick.add(
      QuickAccessItem(
        kind: QuickAccessKind.song,
        title: s.title,
        id: s.id,
        song: s,
      ),
    );
  }

  return HomeFeed(
    recentSongs: recent,
    mostPlayed: mostPlayed,
    recentAlbums: recentAlbums,
    recentlyAdded: recentlyAdded,
    topArtists: topArtists,
    moreFromArtist: moreFrom.isEmpty ? null : topArtist,
    moreFrom: moreFrom,
    dailyMix: dailyMix,
    discover: discover,
    playlists: playlists,
    quickAccess: quick,
  );
}

final homeFeedProvider = Provider<HomeFeed>((ref) {
  final songs = ref.watch(libraryProvider.select((s) => s.songs));
  final albums = ref.watch(libraryProvider.select((s) => s.albums));
  final artists = ref.watch(libraryProvider.select((s) => s.artists));
  final recent = ref.watch(playlistsProvider.select((s) => s.recent));
  final mostPlayed = ref.watch(playlistsProvider.select((s) => s.mostPlayed));
  final playlists = ref.watch(playlistsProvider.select((s) => s.playlists));
  return buildHomeFeed(
    songs: songs,
    albums: albums,
    artists: artists,
    recent: recent,
    mostPlayed: mostPlayed,
    playlists: playlists,
  );
});
