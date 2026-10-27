import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/widgets/wv_song_list.dart';
import 'package:wavvy/widgets/song_menu.dart';
import 'package:wavvy/widgets/bottom_bar.dart';

class AlbumDetailScreen extends ConsumerWidget {
  final AlbumModel album;
  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSongs = ref.watch(libraryProvider.select((s) => s.songs));
    final albumSongs = allSongs.where((s) => s.albumId == album.id).toList();

    albumSongs.sort((a, b) => (a.track ?? 0).compareTo(b.track ?? 0));

    return WvSystemUi(
      child: Scaffold(
        backgroundColor: Wv.of(context).background,
        bottomNavigationBar: BottomMiniPlayer(showTabView: false),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: WvDetailHeader(
                artwork: wvArtwork(
                  context,
                  id: album.id,
                  type: ArtworkType.ALBUM,
                  size: 240,
                  placeholder: Icons.album_rounded,
                ),
                kicker: 'ALBUM',
                title: album.album,
                subtitle: album.artist ?? "Unknown Artist",
                detail: "${albumSongs.length} Songs",
                onPlay: albumSongs.isEmpty
                    ? null
                    : () => ref
                          .read(playerProvider.notifier)
                          .playSong(albumSongs.first, contextList: albumSongs),
                onShuffle: albumSongs.isEmpty
                    ? null
                    : () {
                        final shuffled = [...albumSongs]..shuffle();
                        ref
                            .read(playerProvider.notifier)
                            .playSong(shuffled.first, contextList: shuffled);
                      },
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final song = albumSongs[index];
                return Consumer(
                  builder: (context, ref, child) {
                    final isCurrent = ref.watch(
                      playerProvider.select(
                        (s) => s.currentSong?.id == song.id,
                      ),
                    );
                    final isPlaying = ref.watch(
                      playerProvider.select((s) => s.isPlaying),
                    );

                    return WvSongRow(
                      song: song,
                      index: index,
                      isCurrent: isCurrent,
                      isPlaying: isPlaying,
                      secondary: song.artist ?? "Unknown Artist",
                      onTap: () => ref
                          .read(playerProvider.notifier)
                          .playSong(song, contextList: albumSongs),
                      onAction: () => SongMenuHelper.show(
                        context,
                        ref,
                        song,
                        options: SongMenuOptions(showGoToAlbum: false),
                      ),
                    );
                  },
                );
              }, childCount: albumSongs.length),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
