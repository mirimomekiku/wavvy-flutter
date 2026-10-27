import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// "Recently Played" / "Most Played" shelves: an Aqua section bar followed
/// by photo-framed album art.
class SongsHeaderAppBar extends ConsumerWidget {
  const SongsHeaderAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Consumer(
          builder: (context, ref, child) {
            final recent = ref.watch(playlistsProvider.select((s) => s.recent));
            if (recent.isEmpty) return const SizedBox.shrink();
            return _buildSection(context, ref, "Recently Played", recent);
          },
        ),
        Consumer(
          builder: (context, ref, child) {
            final mostPlayed = ref.watch(
              playlistsProvider.select((s) => s.mostPlayed),
            );
            if (mostPlayed.isEmpty) return const SizedBox.shrink();
            return _buildSection(context, ref, "Most Played", mostPlayed);
          },
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<SongModel> songList,
  ) {
    final a = Aqua.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AquaSectionBar(title: title),
        Container(
          color: a.background,
          height: 168,
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            scrollDirection: Axis.horizontal,
            itemCount: songList.length,
            itemBuilder: (context, index) {
              final song = songList[index];
              return Semantics(
                button: true,
                label: "Play ${song.title}",
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => ref
                      .read(playerProvider.notifier)
                      .playSong(song, contextList: songList),
                  child: Container(
                    width: 112,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      children: [
                        AquaPhotoFrame(
                          child: QueryArtworkWidget(
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            keepOldArtwork: true,
                            artworkFit: BoxFit.cover,
                            artworkBorder: BorderRadius.zero,
                            artworkWidth: 100,
                            artworkHeight: 100,
                            nullArtworkWidget: Container(
                              width: 100,
                              height: 100,
                              color: a.stripe,
                              child: Icon(
                                Icons.music_note_rounded,
                                size: 40,
                                color: a.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: a.text,
                          ),
                        ),
                        Text(
                          song.artist ?? "Unknown",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: a.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
