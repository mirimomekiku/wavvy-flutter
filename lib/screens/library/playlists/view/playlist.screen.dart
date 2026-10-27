import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/context_ext.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/aqua_song_list.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/widgets/floating_app_bar.dart';
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
    final a = Aqua.of(context);

    final navBarColor =
        context.theme.navigationBarTheme.backgroundColor ??
        context.theme.scaffoldBackgroundColor;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: navBarColor,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: context.isDarkMode
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: context.theme.scaffoldBackgroundColor,
        bottomNavigationBar: BottomMiniPlayer(showTabView: false),
        body: Column(
          children: [
            FloatingAppBar(
              title: playlistName,
              showSearch: false,
              leading: aquaBackButton(),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (songsAsync.isLoading && !songsAsync.hasValue) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final playlistSongs = songsAsync.valueOrNull ?? [];

                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: AquaDetailHeader(
                          artwork: Container(
                            decoration: BoxDecoration(
                              gradient: Aqua.gel(a.gelBlue),
                            ),
                            child: const Icon(
                              Icons.queue_music_rounded,
                              size: 52,
                              color: Colors.white,
                            ),
                          ),
                          title: playlistName,
                          subtitle: "Playlist",
                          detail: "${playlistSongs.length} Songs",
                          onPlay: playlistSongs.isEmpty
                              ? null
                              : () => ref.read(playerProvider.notifier).playSong(
                                  playlistSongs.first,
                                  contextList: playlistSongs,
                                ),
                          onShuffle: playlistSongs.isEmpty
                              ? null
                              : () {
                                  final shuffled = [...playlistSongs]
                                    ..shuffle();
                                  ref.read(playerProvider.notifier).playSong(
                                    shuffled.first,
                                    contextList: shuffled,
                                  );
                                },
                        ),
                      ),
                      if (playlistSongs.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: AquaEmptyMessage(
                            message: "No songs in this playlist",
                          ),
                        )
                      else ...[
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: AquaColumnHeaderDelegate(
                            secondaryLabel: "Artist",
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
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
          ],
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
    return Consumer(builder: (context, ref, child) {
      final isCurrent = ref.watch(
        playerProvider.select((s) => s.currentSong?.id == song.id),
      );
      final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

      return AquaSongRow(
        song: song,
        index: index,
        isCurrent: isCurrent,
        isPlaying: isPlaying,
        secondary: song.artist ?? "Unknown",
        onTap: () =>
            ref.read(playerProvider.notifier).playSong(song, contextList: list),
        actionIcon: Icons.remove_circle_outline_rounded,
        actionTooltip: "Remove from playlist",
        onAction: () => showRemoveFromPlaylistDialog(ref, playlistId, song.id),
      );
    });
  }
}
