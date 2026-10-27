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
import 'package:wavvy/providers/search_source_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/library/albums/view/album.screen.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final library = ref.watch(libraryProvider);
    final feed = ref.watch(homeFeedProvider);
    final stats = ref.watch(settingsProvider.select((s) => s.showStats));
    final downloads = ref.watch(
      settingsProvider.select((s) => s.enableDownloader),
    );
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    void albums() {
      ref.read(librarySectionProvider.notifier).set(LibrarySection.albums);
      DefaultTabController.maybeOf(context)?.animateTo(1);
    }

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
                            ? 'Allow music access to see your collection here.'
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
                              onPressed: openAppSettings,
                              child: const Text('Open Settings'),
                            ),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Material(
                  color: a.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: a.outline.withValues(alpha: 0.5)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: song == null
                        ? () => ref
                              .read(playerProvider.notifier)
                              .playSong(
                                library.songs.first,
                                contextList: library.songs,
                              )
                        : () => openWavvyPlayer(context, ref),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          WvArtwork(
                            radius: 9,
                            child: wvArtwork(
                              context,
                              id: song?.id ?? library.songs.first.id,
                              type: ArtworkType.AUDIO,
                              size: 48,
                              placeholder: Icons.album_outlined,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song == null
                                      ? 'READY WHEN YOU ARE'
                                      : 'CONTINUE LISTENING',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w600,
                                    color: a.accent,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  song?.title ?? 'Your collection',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: a.text,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  song?.artist ??
                                      '${library.songs.length} tracks on this device',
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
                          Icon(
                            Icons.chevron_right_rounded,
                            color: a.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      WvButton(
                        width: 108,
                        size: 30,
                        onPressed: () {
                          final songs = [...library.songs]..shuffle();
                          ref
                              .read(playerProvider.notifier)
                              .playSong(songs.first, contextList: songs);
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
                      const SizedBox(width: 8),
                      WvButton(
                        width: 80,
                        size: 30,
                        onPressed: albums,
                        child: const Text('Albums'),
                      ),
                      if (downloads) ...[
                        const SizedBox(width: 8),
                        WvButton(
                          width: 100,
                          size: 30,
                          onPressed: () {
                            ref.read(searchSourceProvider.notifier).state =
                                SearchSource.downloads;
                            DefaultTabController.maybeOf(context)?.animateTo(2);
                          },
                          child: const Text('Downloads'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (stats && feed.recentSongs.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _Section(
                  title: 'Jump back in',
                  subtitle: 'Recently played',
                  action: 'Library',
                  onTap: () =>
                      DefaultTabController.maybeOf(context)?.animateTo(1),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final s = feed.recentSongs[i];
                  return _HomeTrack(song: s, index: i, songs: feed.recentSongs);
                }, childCount: feed.recentSongs.length.clamp(0, 4)),
              ),
            ],
            if (feed.recentAlbums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _Section(
                  title: 'Recently added albums',
                  subtitle: 'New in your collection',
                  action: 'Show all',
                  onTap: albums,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 176 + MediaQuery.textScalerOf(context).scale(40),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: feed.recentAlbums.length.clamp(0, 8),
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, i) {
                      final album = feed.recentAlbums[i];
                      return SizedBox(
                        width: 142,
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
            ],
            if (feed.dailyMix.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: a.frame(
                      color: a.primaryContainer,
                      raised: false,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          color: a.accent,
                          size: 28,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'A mix for today',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 17,
                                  color: a.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${feed.dailyMix.length} tracks from your library',
                                style: TextStyle(
                                  color: a.onPrimaryContainer,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Play daily mix',
                          onPressed: () => ref
                              .read(playerProvider.notifier)
                              .playSong(
                                feed.dailyMix.first,
                                contextList: feed.dailyMix,
                              ),
                          icon: Icon(
                            Icons.play_circle_fill_rounded,
                            size: 42,
                            color: a.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          if (library.songs.isNotEmpty &&
              stats &&
              feed.mostPlayed.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: _Section(
                title: 'On repeat',
                subtitle: 'Your most-played tracks',
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _HomeTrack(
                  song: feed.mostPlayed[i],
                  index: i,
                  songs: feed.mostPlayed,
                ),
                childCount: feed.mostPlayed.length.clamp(0, 4),
              ),
            ),
          ],
          if (library.songs.isNotEmpty && feed.discover.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: _Section(
                title: 'Rediscover your library',
                subtitle: 'Something you have not played lately',
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _HomeTrack(
                  song: feed.discover[i],
                  index: i,
                  songs: feed.discover,
                ),
                childCount: feed.discover.length.clamp(0, 4),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    this.action,
    this.onTap,
  });
  final String title;
  final String subtitle;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    letterSpacing: -0.4,
                    fontWeight: FontWeight.w600,
                    color: a.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: a.textSecondary),
                ),
              ],
            ),
          ),
          if (action != null)
            TextButton(onPressed: onTap, child: Text(action!)),
        ],
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
