import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/wv_song_list.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/widgets/playlist_dialogs.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final int playlistId;
  final String playlistName;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.playlistName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(playlistSongsProvider(playlistId));
    final a = Wv.of(context);

    return WvSystemUi(
      child: Scaffold(
        backgroundColor: a.background,
        bottomNavigationBar: BottomMiniPlayer(showTabView: false),
        body: Builder(
          builder: (context) {
            if (songsAsync.isLoading && !songsAsync.hasValue) {
              return Column(
                children: [
                  WvTopBar(title: playlistName),
                  const Expanded(child: Center(child: AquaSpinner(size: 40))),
                ],
              );
            }

            final playlistSongs = songsAsync.valueOrNull ?? [];

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: WvDetailHeader(
                    artwork: Container(
                      color: a.tertiaryContainer,
                      alignment: Alignment.center,
                      child: WvSymbol(
                        sprite: PixelSprites.vinyl,
                        size: 96,
                        color: a.onTertiaryContainer,
                      ),
                    ),
                    kicker: 'PLAYLIST',
                    title: playlistName,
                    subtitle: "Playlist",
                    detail: "${playlistSongs.length} Songs",
                    onPlay: playlistSongs.isEmpty
                        ? null
                        : () => ref
                              .read(playerProvider.notifier)
                              .playSong(
                                playlistSongs.first,
                                contextList: playlistSongs,
                              ),
                    onShuffle: playlistSongs.isEmpty
                        ? null
                        : () {
                            final shuffled = [...playlistSongs]..shuffle();
                            ref
                                .read(playerProvider.notifier)
                                .playSong(
                                  shuffled.first,
                                  contextList: shuffled,
                                );
                          },
                  ),
                ),
                if (playlistSongs.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: WvEmptyMessage(
                      message: "No songs in this playlist",
                      sprite: PixelSprites.mascotHappy,
                    ),
                  )
                else ...[
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final song = playlistSongs[index];
                      return _buildSongTile(
                        context,
                        ref,
                        song,
                        index,
                        playlistSongs,
                      );
                    }, childCount: playlistSongs.length),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSongTile(
    BuildContext context,
    WidgetRef ref,
    SongModel song,
    int index,
    List<SongModel> list,
  ) {
    return Consumer(
      builder: (context, ref, child) {
        final isCurrent = ref.watch(
          playerProvider.select((s) => s.currentSong?.id == song.id),
        );
        final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

        return WvSongRow(
          song: song,
          index: index,
          isCurrent: isCurrent,
          isPlaying: isPlaying,
          secondary: song.artist ?? "Unknown",
          onTap: () => ref
              .read(playerProvider.notifier)
              .playSong(song, contextList: list),
          actionIcon: Icons.remove_circle_outline_rounded,
          actionTooltip: "Remove from playlist",
          onAction: () =>
              showRemoveFromPlaylistDialog(ref, playlistId, song.id),
        );
      },
    );
  }
}
