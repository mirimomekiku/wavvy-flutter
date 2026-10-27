import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/home_feed_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/library_section_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/screens/library/albums/view/album.screen.dart';
import 'package:wavvy/screens/library/liked/liked.screen.dart';
import 'package:wavvy/screens/library/artists/view/artist.screen.dart';
import 'package:wavvy/screens/library/playlists/view/playlist.screen.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/page_heading.dart';
import 'package:wavvy/widgets/wv_song_list.dart';
import 'package:wavvy/widgets/open_player.dart';
import 'package:wavvy/widgets/song_menu.dart';

class HomeView extends ConsumerWidget {
  const HomeView({super.key});
  static String greeting({DateTime? now}) {
    final hour = (now ?? DateTime.now()).hour;
    return hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
  }

  /// "12 h 30 m" for the library readout; "45 m" under an hour.
  static String totalTime(int milliseconds) =>
      PlayerUtils.formatTotalTime(milliseconds);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final library = ref.watch(libraryProvider);
    final feed = ref.watch(homeFeedProvider);
    final stats = ref.watch(settingsProvider.select((s) => s.showStats));
    final player = ref.watch(playerProvider);
    final liked = ref.watch(likedSongsProvider);
    final song = player.currentSong;
    final actions = ref.read(playerProvider.notifier);

    void toLibrary([LibrarySection? section]) {
      if (section != null) {
        ref.read(librarySectionProvider.notifier).set(section);
      }
      DefaultTabController.maybeOf(context)?.animateTo(1);
    }

    void albums() => toLibrary(LibrarySection.albums);

    final shelfScale = MediaQuery.textScalerOf(context);

    return RefreshIndicator(
      onRefresh: () => ref.read(libraryProvider.notifier).fetchAllSongs(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: WvPageHeading(
              title: greeting(),
              eyebrow: 'WAVVY',
              subtitle: 'Your music. Wherever you are.',
              settings: true,
            ),
          ),
          if (library.isLoading)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (library.error.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(library.error),
              ),
            ),
          if (library.songs.isEmpty && !library.isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        library.permissionDenied
                            ? Icons.lock_outline_rounded
                            : Icons.library_music_outlined,
                        size: 48,
                        color: a.accent,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        library.permissionDenied
                            ? 'Storage Access Needed'
                            : 'No Songs',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: a.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        library.permissionDenied
                            ? library.permissionBlocked
                                  ? 'Turn on music access for Wavvy in Settings.'
                                  : 'Allow music access to see your collection here.'
                            : 'Add music to your device, then refresh your library.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: a.textSecondary, height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (library.permissionDenied)
                            WvButton(
                              width: 140,
                              primary: library.permissionBlocked,
                              onPressed: openAppSettings,
                              child: const Text('Open Settings'),
                            ),
                          if (!library.permissionBlocked)
                            WvButton(
                              primary: true,
                              width: 110,
                              onPressed: () => ref
                                  .read(libraryProvider.notifier)
                                  .fetchAllSongs(),
                              child: Text(
                                library.permissionDenied ? 'Retry' : 'Refresh',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (library.songs.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ---- Now playing / ready
            SliverToBoxAdapter(
              child: AquaWindow(
                title: song == null
                    ? 'Ready when you are'
                    : 'Continue listening',
                subtitle: song == null
                    ? '${library.songs.length} tracks on this device'
                    : null,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      button: true,
                      label: song == null
                          ? 'Your collection'
                          : 'Open the player, ${song.title}',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: song == null
                            ? () => actions.playSong(
                                library.songs.first,
                                contextList: library.songs,
                              )
                            : () => openWavvyPlayer(context, ref),
                        child: Row(
                          children: [
                            WvArtwork(
                              radius: 8,
                              child: wvArtwork(
                                context,
                                id: song?.id ?? library.songs.first.id,
                                type: ArtworkType.AUDIO,
                                size: 64,
                                placeholder: Icons.album_outlined,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                decoration: a.lcdDecoration.copyWith(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song?.title ?? 'Your collection',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: a.text,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      song?.artist ??
                                          '${library.albums.length} albums \u00b7 ${library.artists.length} artists',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: a.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        WvButton(
                          primary: true,
                          width: 96,
                          size: 34,
                          onPressed: song == null
                              ? () => actions.playSong(
                                  library.songs.first,
                                  contextList: library.songs,
                                )
                              : actions.togglePlay,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                player.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(player.isPlaying ? 'Pause' : 'Play'),
                            ],
                          ),
                        ),
                        WvButton(
                          width: 112,
                          size: 34,
                          onPressed: () {
                            final songs = [...library.songs]..shuffle();
                            actions.playSong(songs.first, contextList: songs);
                          },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shuffle_rounded, size: 15),
                              SizedBox(width: 5),
                              Text('Shuffle all'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ---- Library readout
            SliverToBoxAdapter(
              child: AquaWindow(
                title: 'Your library',
                subtitle: 'On this device',
                action: 'Browse',
                onAction: toLibrary,
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AquaLcdCell(
                            value: '${library.songs.length}',
                            label: 'Songs',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AquaLcdCell(
                            value: '${library.albums.length}',
                            label: 'Albums',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AquaLcdCell(
                            value: '${library.artists.length}',
                            label: 'Artists',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AquaLcdCell(
                            value: '${feed.playlists.length}',
                            label: 'Playlists',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${totalTime(library.songs.fold<int>(0, (sum, s) => sum + (s.duration ?? 0)))} of music',
                      style: TextStyle(fontSize: 12, color: a.textSecondary),
                    ),
                  ],
                ),
              ),
            ),

            // ---- Quick access
            if (feed.quickAccess.isNotEmpty)
              SliverToBoxAdapter(
                child: AquaWindow(
                  title: 'Quick access',
                  subtitle: 'Playlists and albums to jump into',
                  child: _QuickAccess(items: feed.quickAccess, feed: feed),
                ),
              ),

            // ---- Recently played
            if (stats && feed.recentSongs.isNotEmpty)
              SliverToBoxAdapter(
                child: AquaWindow(
                  title: 'Jump back in',
                  subtitle: 'Recently played',
                  action: 'Library',
                  onAction: toLibrary,
                  child: _TrackList(songs: feed.recentSongs, count: 4),
                ),
              ),

            // ---- Albums
            if (feed.recentAlbums.isNotEmpty)
              SliverToBoxAdapter(
                child: AquaWindow(
                  title: 'Recently added albums',
                  subtitle: 'New in your collection',
                  action: 'Show all',
                  onAction: albums,
                  child: SizedBox(
                    height: 190 + shelfScale.scale(40),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(12),
                      itemCount: feed.recentAlbums.length.clamp(0, 8),
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final album = feed.recentAlbums[i];
                        return SizedBox(
                          width: 130,
                          child: WvGridTile(
                            title: album.album,
                            subtitle: album.artist,
                            onTap: () =>
                                AppNav.push(AlbumDetailScreen(album: album)),
                            artworkBuilder: (size) => wvArtwork(
                              context,
                              id: album.id,
                              type: ArtworkType.ALBUM,
                              size: size,
                              placeholder: Icons.album_outlined,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

            // ---- Top artists
            if (stats && feed.topArtists.isNotEmpty)
              SliverToBoxAdapter(
                child: AquaWindow(
                  title: 'Top artists',
                  subtitle: 'Based on what you play',
                  child: SizedBox(
                    height: 108 + shelfScale.scale(32),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(12),
                      itemCount: feed.topArtists.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, i) =>
                          _ArtistChip(artist: feed.topArtists[i]),
                    ),
                  ),
                ),
              ),

            // ---- Daily mix
            if (feed.dailyMix.isNotEmpty)
              SliverToBoxAdapter(
                child: AquaWindow(
                  title: 'A mix for today',
                  subtitle: '${feed.dailyMix.length} tracks from your library',
                  action: 'Play',
                  onAction: () => actions.playSong(
                    feed.dailyMix.first,
                    contextList: feed.dailyMix,
                  ),
                  child: _TrackList(songs: feed.dailyMix, count: 3),
                ),
              ),

            // ---- More from the top artist
            if (stats && feed.moreFromArtist != null)
              SliverToBoxAdapter(
                child: AquaWindow(
                  title: 'More from ${feed.moreFromArtist!.artist}',
                  subtitle: 'Songs you have not played lately',
                  action: 'Artist',
                  onAction: () => AppNav.push(
                    ArtistDetailScreen(artist: feed.moreFromArtist!),
                  ),
                  child: _TrackList(songs: feed.moreFrom, count: 4),
                ),
              ),
          ],
          if (library.songs.isNotEmpty && stats && feed.mostPlayed.isNotEmpty)
            SliverToBoxAdapter(
              child: AquaWindow(
                title: 'On repeat',
                subtitle: 'Your most-played tracks',
                child: _TrackList(songs: feed.mostPlayed, count: 4),
              ),
            ),
          if (library.songs.isNotEmpty && feed.recentlyAdded.isNotEmpty)
            SliverToBoxAdapter(
              child: AquaWindow(
                title: 'New songs',
                subtitle: 'Latest additions',
                action: 'Library',
                onAction: toLibrary,
                child: _TrackList(songs: feed.recentlyAdded, count: 5),
              ),
            ),
          if (library.songs.isNotEmpty && liked.isNotEmpty)
            SliverToBoxAdapter(
              child: AquaWindow(
                title: 'Liked songs',
                subtitle: '${liked.length} you hearted',
                action: 'Show all',
                onAction: () => AppNav.push(const LikedSongsScreen()),
                child: _TrackList(songs: liked, count: 4),
              ),
            ),
          if (library.songs.isNotEmpty && feed.playlists.isNotEmpty)
            SliverToBoxAdapter(
              child: AquaWindow(
                title: 'Your playlists',
                action: 'Show all',
                onAction: () => toLibrary(LibrarySection.playlists),
                child: AquaMenuList(
                  rows: [
                    for (final p in feed.playlists.take(4))
                      AquaMenuRow(
                        icon: Icons.queue_music_rounded,
                        label: '${p['name']}',
                        chevron: true,
                        onTap: () => AppNav.push(
                          PlaylistDetailScreen(
                            playlistId: p['id'] as int,
                            playlistName: '${p['name']}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (library.songs.isNotEmpty && feed.discover.isNotEmpty)
            SliverToBoxAdapter(
              child: AquaWindow(
                title: 'Rediscover your library',
                subtitle: 'Something you have not played lately',
                child: _TrackList(songs: feed.discover, count: 4),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }
}

/// The first [count] songs as striped rows that play the whole [songs] list.
class _TrackList extends StatelessWidget {
  const _TrackList({required this.songs, required this.count});
  final List<SongModel> songs;
  final int count;

  @override
  Widget build(BuildContext context) {
    final shown = songs.take(count).toList();
    return Column(
      children: [
        for (var i = 0; i < shown.length; i++)
          _HomeTrack(song: shown[i], index: i, songs: songs),
      ],
    );
  }
}

/// Two-column grid of playlists, albums and songs.
class _QuickAccess extends ConsumerWidget {
  const _QuickAccess({required this.items, required this.feed});
  final List<QuickAccessItem> items;
  final HomeFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);

    void open(QuickAccessItem item) {
      switch (item.kind) {
        case QuickAccessKind.playlist:
          AppNav.push(
            PlaylistDetailScreen(playlistId: item.id, playlistName: item.title),
          );
        case QuickAccessKind.album:
          AppNav.push(AlbumDetailScreen(album: item.album!));
        case QuickAccessKind.song:
          ref
              .read(playerProvider.notifier)
              .playSong(item.song!, contextList: feed.recentlyAdded);
      }
    }

    Widget cell(QuickAccessItem item) {
      final art = item.kind == QuickAccessKind.playlist
          ? Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: a.gelGradient(primary: true),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                Icons.queue_music_rounded,
                size: 20,
                color: a.onAccent,
              ),
            )
          : WvArtwork(
              radius: 7,
              child: SizedBox.square(
                dimension: 36,
                child: wvArtwork(
                  context,
                  id: item.kind == QuickAccessKind.album
                      ? item.album!.id
                      : item.song!.id,
                  type: item.kind == QuickAccessKind.album
                      ? ArtworkType.ALBUM
                      : ArtworkType.AUDIO,
                  size: 36,
                  placeholder: Icons.music_note_rounded,
                ),
              ),
            );
      return Semantics(
        button: true,
        label: item.title,
        child: InkWell(
          onTap: () => open(item),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  art,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: a.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(
        ColoredBox(
          color: (i ~/ 2).isOdd ? a.stripe : a.surface,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cell(items[i])),
                VerticalDivider(width: 1, color: a.separator),
                Expanded(
                  child: i + 1 < items.length
                      ? cell(items[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _ArtistChip extends StatelessWidget {
  const _ArtistChip({required this.artist});
  final ArtistModel artist;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return SizedBox(
      width: 80,
      child: Semantics(
        button: true,
        label: artist.artist,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => AppNav.push(ArtistDetailScreen(artist: artist)),
          child: Column(
            children: [
              WvArtwork(
                circular: true,
                child: SizedBox.square(
                  dimension: 72,
                  child: wvArtwork(
                    context,
                    id: artist.id,
                    type: ArtworkType.ARTIST,
                    size: 72,
                    placeholder: Icons.person_rounded,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                artist.artist,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: a.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTrack extends ConsumerWidget {
  const _HomeTrack({
    required this.song,
    required this.index,
    required this.songs,
  });
  final SongModel song;
  final int index;
  final List<SongModel> songs;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    return WvSongRow(
      song: song,
      index: index,
      isCurrent: player.currentSong?.id == song.id,
      isPlaying: player.isPlaying,
      secondary: song.artist ?? 'Unknown Artist',
      onTap: () =>
          ref.read(playerProvider.notifier).playSong(song, contextList: songs),
      onAction: () => SongMenuHelper.show(context, ref, song),
    );
  }
}
