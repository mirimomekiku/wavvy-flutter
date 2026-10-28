import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/disc_numbers.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/widgets/wv_song_list.dart';
import 'package:wavvy/widgets/song_selection.dart';
import 'package:wavvy/widgets/song_menu.dart';
import 'package:wavvy/widgets/album_cover_menu.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/widgets/disc_header.dart';

class AlbumDetailScreen extends ConsumerWidget {
  final AlbumModel album;
  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSongs = ref.watch(libraryProvider.select((s) => s.songs));
    final albumSongs = allSongs.where((s) => s.albumId == album.id).toList();

    // (disc, track) order; Play, Shuffle and taps all use this list.
    final groups = groupByDisc(albumSongs);
    final multiDisc = groups.length > 1;
    final ordered = [for (final g in groups) ...g.songs];
    final entries = <_Entry>[
      for (final g in groups) ...[
        if (multiDisc) _Entry.header(g),
        for (final song in g.songs) _Entry.song(song),
      ],
    ];

    return WvSystemUi(
      child: Scaffold(
        backgroundColor: Wv.of(context).pageColor,
        bottomNavigationBar: BottomMiniPlayer(showTabView: false),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  WvDetailHeader(
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
                    detail: "${ordered.length} Songs",
                    onPlay: ordered.isEmpty
                        ? null
                        : () => ref
                              .read(playerProvider.notifier)
                              .playSong(ordered.first, contextList: ordered),
                    onShuffle: ordered.isEmpty
                        ? null
                        : () {
                            final shuffled = [...ordered]..shuffle();
                            ref
                                .read(playerProvider.notifier)
                                .playSong(
                                  shuffled.first,
                                  contextList: shuffled,
                                );
                          },
                  ),
                  // Find / remove a fetched cover, beside the back button row.
                  Positioned(
                    top: MediaQuery.paddingOf(context).top,
                    right: 8,
                    child: AlbumCoverMenuButton(album: album),
                  ),
                ],
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final entry = entries[index];
                final group = entry.group;
                if (group != null) {
                  return DiscHeaderRow(
                    disc: group.disc,
                    count: group.songs.length,
                  );
                }
                final song = entry.song!;
                final position = ordered.indexOf(song);
                // The track number leads the artist where the album has discs.
                final number = trackNumberOf(song.track);
                final artist = song.artist ?? "Unknown Artist";
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

                    return SelectableSongRow(
                      song: song,
                      index: position,
                      scope: ordered,
                      isCurrent: isCurrent,
                      isPlaying: isPlaying,
                      secondary: multiDisc && number != null
                          ? '$number · $artist'
                          : artist,
                      onTap: () => ref
                          .read(playerProvider.notifier)
                          .playSong(song, contextList: ordered),
                      onAction: () => SongMenuHelper.show(
                        context,
                        ref,
                        song,
                        options: SongMenuOptions(showGoToAlbum: false),
                      ),
                    );
                  },
                );
              }, childCount: entries.length),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

/// One line of the track list: a disc header or a song.
class _Entry {
  const _Entry.header(DiscGroup this.group) : song = null;
  const _Entry.song(SongModel this.song) : group = null;
  final DiscGroup? group;
  final SongModel? song;
}
