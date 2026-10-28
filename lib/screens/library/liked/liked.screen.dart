import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// The color of a favorite heart.
const Color kHeartColor = Color(0xFFD8453B);

/// Favorites: the songs you hearted, newest first.
class LikedSongsScreen extends ConsumerWidget {
  const LikedSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final songs = ref.watch(likedSongsProvider);
    final player = ref.read(playerProvider.notifier);

    return WvSystemUi(
      child: Scaffold(
        backgroundColor: a.pageColor,
        bottomNavigationBar: const BottomMiniPlayer(showTabView: false),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: WvDetailHeader(
                artwork: Container(
                  color: a.tertiaryContainer,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 84,
                    color: kHeartColor,
                  ),
                ),
                kicker: 'FAVORITES',
                title: 'Liked songs',
                subtitle: 'Songs you hearted',
                detail: '${songs.length} Songs',
                onPlay: songs.isEmpty
                    ? null
                    : () => player.playSong(songs.first, contextList: songs),
                onShuffle: songs.isEmpty
                    ? null
                    : () {
                        final shuffled = [...songs]..shuffle();
                        player.playSong(shuffled.first, contextList: shuffled);
                      },
              ),
            ),
            if (songs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: WvEmptyMessage(
                  message: 'Tap the heart on a song to keep it here',
                  sprite: PixelSprites.mascotHappy,
                ),
              )
            else ...[
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final song = songs[index];
                  return Consumer(
                    builder: (context, ref, _) {
                      final current = ref.watch(
                        playerProvider.select((s) => s.currentSong?.id),
                      );
                      return WvSongRow(
                        song: song,
                        index: index,
                        isCurrent: current == song.id,
                        isPlaying: ref.watch(
                          playerProvider.select((s) => s.isPlaying),
                        ),
                        secondary: song.artist ?? 'Unknown',
                        onTap: () => ref
                            .read(playerProvider.notifier)
                            .playSong(song, contextList: songs),
                        actionIcon: Icons.favorite_rounded,
                        actionTooltip: 'Remove from Favorites',
                        onAction: () =>
                            ref.read(favoritesProvider.notifier).toggle(song),
                      );
                    },
                  );
                }, childCount: songs.length),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
    );
  }
}
