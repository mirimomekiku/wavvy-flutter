import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

enum SortOption { titleAZ, titleZA, dateNewest, dateOldest, artistAZ }

/// The device music library (replaces AudioController's songs / filteredSongs
/// / albums / artists / currentSort).
class LibraryState {
  final List<SongModel> songs;

  /// Songs matching the current search query (== songs when no query).
  final List<SongModel> filteredSongs;
  final List<AlbumModel> albums;
  final List<ArtistModel> artists;
  final SortOption sort;

  const LibraryState({
    this.songs = const [],
    this.filteredSongs = const [],
    this.albums = const [],
    this.artists = const [],
    this.sort = SortOption.titleAZ,
  });

  LibraryState copyWith({
    List<SongModel>? songs,
    List<SongModel>? filteredSongs,
    List<AlbumModel>? albums,
    List<ArtistModel>? artists,
    SortOption? sort,
  }) => LibraryState(
    songs: songs ?? this.songs,
    filteredSongs: filteredSongs ?? this.filteredSongs,
    albums: albums ?? this.albums,
    artists: artists ?? this.artists,
    sort: sort ?? this.sort,
  );
}

final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(
  LibraryNotifier.new,
);

/// The OnAudioQuery instance shared by library + palette code.
final audioQueryProvider = Provider<OnAudioQuery>((ref) => OnAudioQuery());

class LibraryNotifier extends Notifier<LibraryState> {
  @override
  LibraryState build() => const LibraryState();

  /// Checks/requests storage permissions, queries songs/albums/artists (only
  /// isMusic songs), applies the current sort, then asks playlistsProvider to
  /// refresh smart playlists.
  Future<void> fetchAllSongs() async {
    final hasPermission = await _checkAndRequestPermissions();

    if (hasPermission) {
      try {
        final audioQuery = ref.read(audioQueryProvider);
        final songsList = await audioQuery.querySongs(
          ignoreCase: true,
          orderType: OrderType.ASC_OR_SMALLER,
          uriType: UriType.EXTERNAL,
          sortType: SongSortType.TITLE,
        );

        final albumsList = await audioQuery.queryAlbums();
        final artistsList = await audioQuery.queryArtists();

        final validSongs = songsList.where((s) => s.isMusic == true).toList();
        final sorted = _sorted(validSongs, state.sort);

        // Search query is not tracked: filteredSongs resets to all songs, as
        // the GetX `ever(songs)` worker did.
        state = state.copyWith(
          songs: sorted,
          filteredSongs: List<SongModel>.from(sorted),
          albums: albumsList,
          artists: artistsList,
        );

        // Smart playlists map stored song ids onto the loaded library, so
        // they can only be built once songs are available.
        await ref
            .read(playlistsProvider.notifier)
            .refreshSmartPlaylists(bumpRevision: true);
      } catch (e) {
        debugPrint("fetchAllSongs failed: $e");
        AppSnackbar.showErrorSnackBar(
          "Cannot fetch songs",
          "Could not read your music library.",
        );
      }
    } else {
      AppSnackbar.showErrorSnackBar(
        "Cannot fetch songs",
        "Permissions not granted.",
      );
    }
  }

  List<SongModel> _sorted(List<SongModel> input, SortOption option) {
    final List<SongModel> sortedList = List.from(input);

    switch (option) {
      case SortOption.titleAZ:
        sortedList.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case SortOption.titleZA:
        sortedList.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case SortOption.dateNewest:
        sortedList.sort(
          (a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0),
        );
        break;
      case SortOption.dateOldest:
        sortedList.sort(
          (a, b) => (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0),
        );
        break;
      case SortOption.artistAZ:
        sortedList.sort(
          (a, b) => (a.artist ?? "").toLowerCase().compareTo(
            (b.artist ?? "").toLowerCase(),
          ),
        );
        break;
    }
    return sortedList;
  }

  /// Case-insensitive sorts, as in the GetX version. In GetX the sorted songs
  /// re-triggered the filteredSongs worker, so filteredSongs is reset too.
  void changeSortOption(SortOption option) {
    final sorted = _sorted(state.songs, option);
    state = state.copyWith(
      sort: option,
      songs: sorted,
      filteredSongs: List<SongModel>.from(sorted),
    );
  }

  /// Filters songs by title/artist (case-insensitive). Empty query resets
  /// filteredSongs to all songs.
  void search(String query) {
    if (query.isEmpty) {
      state = state.copyWith(filteredSongs: List<SongModel>.from(state.songs));
      return;
    }
    final q = query.toLowerCase();
    state = state.copyWith(
      filteredSongs: state.songs
          .where(
            (s) =>
                s.title.toLowerCase().contains(q) ||
                (s.artist?.toLowerCase().contains(q) ?? false),
          )
          .toList(),
    );
  }

  /// Removes a song from songs + filteredSongs (after a file delete).
  void removeSongLocally(int songId) {
    state = state.copyWith(
      songs: state.songs.where((s) => s.id != songId).toList(),
      filteredSongs: state.filteredSongs.where((s) => s.id != songId).toList(),
    );
  }

  Future<bool> _checkAndRequestPermissions() async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;

    // --- 1. Android 13+ (SDK 33+) ---
    if (androidInfo.version.sdkInt >= 33) {
      // Notification is optional for logic, but good for UX
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      // CRITICAL: on_audio_query crashes without this on Android 13+
      if (await Permission.audio.isDenied) {
        await Permission.audio.request();
      }
      return await Permission.audio.isGranted;
    }

    // --- 2. Android 11 & 12 (SDK 30-32) ---
    if (androidInfo.version.sdkInt >= 30) {
      // Scoped storage: plain read access is enough to list the library.
      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
      }
      return await Permission.storage.isGranted;
    }

    // --- 3. Older Android (SDK < 30) ---
    if (await Permission.storage.isDenied) {
      await Permission.storage.request();
    }
    return await Permission.storage.isGranted;
  }
}
