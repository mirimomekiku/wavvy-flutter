import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/palette_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/audio_effects/effects.screen.dart';
import 'package:wavvy/screens/library/albums/view/album.screen.dart';
import 'package:wavvy/screens/library/artists/view/artist.screen.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/utils/snackbar.utils.dart';
import 'package:wavvy/widgets/audio_dialogs.dart';
import 'package:wavvy/widgets/playlist_dialogs.dart';

class SongMenuOptions {
  final bool showPlayNext;
  final bool showAddToQueue;
  final bool showAddToPlaylist;
  final bool showGoToArtist;
  final bool showGoToAlbum;
  final bool showSleepTimer;
  final bool showEditTags;
  final bool showDelete;
  final bool showShare;
  final bool showCustomEqualizer;
  final bool showSystemEqualizer;
  final bool showSongInfo;

  const SongMenuOptions({
    this.showPlayNext = true,
    this.showAddToQueue = true,
    this.showAddToPlaylist = true,
    this.showGoToArtist = true,
    this.showGoToAlbum = true,
    this.showSleepTimer = true,
    this.showEditTags = true,
    this.showDelete = false,
    this.showShare = true,
    this.showCustomEqualizer = false,
    this.showSystemEqualizer = false,
    this.showSongInfo = false,
  });
}

class SongMenuHelper {
  static void show(
    BuildContext context,
    WidgetRef ref,
    SongModel song, {
    SongMenuOptions options = const SongMenuOptions(),
  }) {
    final palette = ref.read(paletteProvider);
    final theme = Theme.of(context);
    final bgColor = palette.playerColor ?? theme.scaffoldBackgroundColor;
    final textColor = palette.playerColor != null
        ? palette.playerTextColor
        : (theme.textTheme.bodyLarge?.color ?? Colors.black);
    final subTextColor = textColor.withValues(alpha: 0.7);

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusL)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) {
            final rows = <Widget>[];
            void add({
              required IconData icon,
              required String label,
              Color? color,
              required VoidCallback onTap,
            }) {
              rows.add(
                _buildOption(
                  icon: icon,
                  label: label,
                  color: color ?? textColor,
                  striped: rows.length.isOdd,
                  stripeColor: textColor.withValues(alpha: 0.07),
                  onTap: onTap,
                ),
              );
            }

            if (options.showPlayNext) {
              add(
                icon: Icons.playlist_play_rounded,
                label: "Play Next",
                onTap: () {
                  Navigator.pop(context);
                  ref.read(playerProvider.notifier).playNext(song);
                },
              );
            }

            if (options.showAddToQueue) {
              add(
                icon: Icons.queue_music_rounded,
                label: "Add to Queue",
                onTap: () {
                  Navigator.pop(context);
                  ref.read(playerProvider.notifier).addToQueue(song);
                },
              );
            }

            if (options.showAddToPlaylist) {
              add(
                icon: Icons.playlist_add_rounded,
                label: "Add to Playlist",
                onTap: () {
                  Navigator.pop(context);
                  showAddToPlaylistSheet(context, ref, song);
                },
              );
            }

            if (options.showCustomEqualizer) {
              add(
                icon: Icons.equalizer_rounded,
                label: "Custom equalizer",
                onTap: () {
                  Navigator.pop(context);
                  AppNav.push(const AudioEffectsScreen());
                },
              );
            }

            if (options.showSystemEqualizer) {
              add(
                icon: Icons.surround_sound_rounded,
                label: "System equalizer",
                onTap: () {
                  PlayerUtils.openEqualizer(
                    ref.read(audioPlayerProvider).androidAudioSessionId,
                  );
                },
              );
            }

            if (options.showGoToArtist) {
              add(
                icon: Icons.person_rounded,
                label: "Go to Artist",
                onTap: () => _handleGoToArtist(context, ref, song),
              );
            }

            if (options.showGoToAlbum) {
              add(
                icon: Icons.album_rounded,
                label: "Go to Album",
                onTap: () => _handleGoToAlbum(context, ref, song),
              );
            }

            if (options.showShare) {
              add(
                icon: Icons.ios_share_rounded,
                label: "Share",
                onTap: () {
                  Navigator.pop(context);
                  PlayerUtils.shareSong(song);
                },
              );
            }

            if (options.showSleepTimer) {
              add(
                icon: Icons.timer_rounded,
                label: "Sleep timer",
                onTap: () {
                  Navigator.pop(context);
                  openSleepTimerDialog(ref);
                },
              );
            }

            if (options.showEditTags) {
              add(
                icon: Icons.edit_rounded,
                label: "Edit tags",
                onTap: () {
                  Navigator.pop(context);
                  editSongTags(ref, song);
                },
              );
            }

            if (options.showDelete) {
              add(
                icon: Icons.delete_outline_rounded,
                label: "Delete",
                color: Colors.redAccent,
                onTap: () {
                  Navigator.pop(context);
                  confirmDeleteSong(ref, song);
                },
              );
            }

            if (options.showSongInfo) {
              add(
                icon: Icons.info_outline_rounded,
                label: "Song Info",
                onTap: () {
                  Navigator.pop(context);
                  showInfoDialog(
                    context,
                    ref,
                    song,
                    theme.scaffoldBackgroundColor,
                    textColor,
                  );
                },
              );
            }

            final edge = textColor.withValues(alpha: 0.25);

            return Column(
              children: [
                // Grabber
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // --- HEADER ---
                _buildHeader(song, textColor, subTextColor),
                Container(height: 1, color: edge),

                // --- SCROLLABLE OPTIONS ---
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: EdgeInsets.only(
                      bottom: 24 + MediaQuery.of(context).padding.bottom,
                    ),
                    children: [...rows, Container(height: 1, color: edge)],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Widget _buildHeader(SongModel song, Color textColor, Color subColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          AquaPhotoFrame(
            child: QueryArtworkWidget(
              id: song.id,
              type: ArtworkType.AUDIO,
              artworkBorder: BorderRadius.zero,
              artworkFit: BoxFit.cover,
              artworkWidth: 56,
              artworkHeight: 56,
              nullArtworkWidget: Container(
                width: 56,
                height: 56,
                color: textColor.withValues(alpha: 0.08),
                child: Icon(
                  Icons.music_note_rounded,
                  color: textColor,
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  song.artist ?? "Unknown Artist",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: subColor, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildOption({
    required IconData icon,
    required String label,
    required Color color,
    required bool striped,
    required Color stripeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: striped ? stripeColor : null,
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _handleGoToArtist(
    BuildContext context,
    WidgetRef ref,
    SongModel song,
  ) {
    Navigator.pop(context);
    final artistModel = ref
        .read(libraryProvider)
        .artists
        .where((a) => a.id == song.artistId)
        .firstOrNull;

    if (artistModel != null) {
      AppNav.push(ArtistDetailScreen(artist: artistModel));
    } else {
      AppSnackbar.showErrorSnackBar("Error", "Artist info not found");
    }
  }

  static void _handleGoToAlbum(
    BuildContext context,
    WidgetRef ref,
    SongModel song,
  ) {
    Navigator.pop(context);
    final albumModel = ref
        .read(libraryProvider)
        .albums
        .where((a) => a.id == song.albumId)
        .firstOrNull;

    if (albumModel != null) {
      AppNav.push(AlbumDetailScreen(album: albumModel));
    } else {
      AppSnackbar.showErrorSnackBar("Error", "Album info not found");
    }
  }

  static void showInfoDialog(
    BuildContext context,
    WidgetRef ref,
    SongModel song,
    Color bgColor,
    Color textColor,
  ) {
    final a = Aqua.of(context);

    final info = ref.read(playerProvider.notifier).getSongInfo(song);

    showAppDialog(
      builder: (_) => Dialog(
        backgroundColor: a.background,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ds.radiusM),
          side: BorderSide(color: a.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AquaSectionBar(title: "Song Details"),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Text(
                  info,
                  style: TextStyle(color: a.text, fontSize: 13.5, height: 1.5),
                ),
              ),
            ),
            Container(height: 1, color: a.separator),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: GelButton(
                  primary: true,
                  width: 80,
                  size: 30,
                  tooltip: "Close",
                  onPressed: () => AppNav.pop(),
                  child: const Text("Close"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
