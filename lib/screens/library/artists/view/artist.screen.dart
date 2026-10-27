import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/widgets/wv_song_list.dart';
import 'package:wavvy/widgets/song_menu.dart';
import 'package:wavvy/widgets/bottom_bar.dart';

class ArtistDetailScreen extends ConsumerWidget {
  final ArtistModel artist;
  const ArtistDetailScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSongs = ref.watch(libraryProvider.select((s) => s.songs));
    final artistSongs = allSongs.where((s) => s.artistId == artist.id).toList();

    artistSongs.sort((a, b) => a.title.compareTo(b.title));

    return WvSystemUi(
      child: Scaffold(
        backgroundColor: Wv.of(context).background,
        bottomNavigationBar: BottomMiniPlayer(showTabView: false),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: WvDetailHeader(
                circular: true,
                artwork: wvArtwork(
                  context,
                  id: artist.id,
                  type: ArtworkType.ARTIST,
                  size: 240,
                  placeholder: Icons.person_rounded,
                ),
                kicker: 'ARTIST',
                title: artist.artist,
                subtitle: "${artist.numberOfAlbums} Albums",
                detail: "${artistSongs.length} Songs",
                onPlay: artistSongs.isEmpty
                    ? null
                    : () => ref
                          .read(playerProvider.notifier)
                          .playSong(
                            artistSongs.first,
                            contextList: artistSongs,
                          ),
                onShuffle: artistSongs.isEmpty
                    ? null
                    : () {
                        final shuffled = [...artistSongs]..shuffle();
                        ref
                            .read(playerProvider.notifier)
                            .playSong(shuffled.first, contextList: shuffled);
                      },
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final song = artistSongs[index];
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
                      secondary: song.album ?? "Unknown Album",
                      onTap: () => ref
                          .read(playerProvider.notifier)
                          .playSong(song, contextList: artistSongs),
                      onAction: () => SongMenuHelper.show(
                        context,
                        ref,
                        song,
                        options: SongMenuOptions(showGoToArtist: false),
                      ),
                    );
                  },
                );
              }, childCount: artistSongs.length),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
