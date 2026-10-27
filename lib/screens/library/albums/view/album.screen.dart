import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/context_ext.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/widgets/aqua_song_list.dart';
import 'package:wavvy/widgets/floating_app_bar.dart';
import 'package:wavvy/widgets/song_menu.dart';
import 'package:wavvy/widgets/bottom_bar.dart';

class AlbumDetailScreen extends ConsumerWidget {
  final AlbumModel album;
  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSongs = ref.watch(libraryProvider.select((s) => s.songs));
    final albumSongs = allSongs
        .where((s) => s.albumId == album.id)
        .toList();

    albumSongs.sort((a, b) => (a.track ?? 0).compareTo(b.track ?? 0));

    return Builder(builder: (context) {
      final navBarColor = Aqua.of(context).toolbar[1];

      final Brightness iconBrightness =
          ThemeData.estimateBrightnessForColor(navBarColor) == Brightness.dark
          ? Brightness.light
          : Brightness.dark;

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          systemNavigationBarColor: navBarColor,
          systemNavigationBarIconBrightness: iconBrightness,
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: context.isDarkMode
              ? Brightness.light
              : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          bottomNavigationBar: BottomMiniPlayer(showTabView: false),
          body: Column(
            children: [
              FloatingAppBar(
                title: album.album,
                showSearch: false,
                leading: aquaBackButton(),
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: AquaDetailHeader(
                        artwork: aquaArtwork(
                          context,
                          id: album.id,
                          type: ArtworkType.ALBUM,
                          size: 112,
                          placeholder: Icons.album_rounded,
                        ),
                        title: album.album,
                        subtitle: album.artist ?? "Unknown Artist",
                        detail: "${albumSongs.length} Songs",
                        onPlay: albumSongs.isEmpty
                            ? null
                            : () => ref.read(playerProvider.notifier).playSong(
                                albumSongs.first,
                                contextList: albumSongs,
                              ),
                        onShuffle: albumSongs.isEmpty
                            ? null
                            : () {
                                final shuffled = [...albumSongs]..shuffle();
                                ref.read(playerProvider.notifier).playSong(
                                  shuffled.first,
                                  contextList: shuffled,
                                );
                              },
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: AquaColumnHeaderDelegate(
                        secondaryLabel: "Artist",
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final song = albumSongs[index];
                        return Consumer(builder: (context, ref, child) {
                          final isCurrent = ref.watch(
                            playerProvider.select(
                              (s) => s.currentSong?.id == song.id,
                            ),
                          );
                          final isPlaying = ref.watch(
                            playerProvider.select((s) => s.isPlaying),
                          );

                          return AquaSongRow(
                            song: song,
                            index: index,
                            isCurrent: isCurrent,
                            isPlaying: isPlaying,
                            secondary: song.artist ?? "Unknown Artist",
                            onTap: () => ref.read(playerProvider.notifier).playSong(
                              song,
                              contextList: albumSongs,
                            ),
                            onAction: () => SongMenuHelper.show(
                              context,
                              ref,
                              song,
                              options: SongMenuOptions(showGoToAlbum: false),
                            ),
                          );
                        });
                      }, childCount: albumSongs.length),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
