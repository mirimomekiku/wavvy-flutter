import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/audio_effects/effects.screen.dart';
import 'package:wavvy/screens/library/albums/view/album.screen.dart';
import 'package:wavvy/screens/library/artists/view/artist.screen.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/utils/snackbar.utils.dart';
import 'package:wavvy/widgets/audio_dialogs.dart';
import 'package:wavvy/player_sheets/player_dialogs.dart';
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
  final bool showPlaybackSpeed;

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
    this.showPlaybackSpeed = false,
  });
}

class SongMenuHelper {
  static void show(
    BuildContext context,
    WidgetRef ref,
    SongModel song, {
    SongMenuOptions options = const SongMenuOptions(),
  }) {
    final a = Wv.of(context);
    final textColor = a.text;

    showModalBottomSheet(
      context: context,
      backgroundColor: a.background,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: a.separator),
        borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusXL)),
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
                  a: a,
                  index: rows.length,
                  icon: icon,
                  label: label,
                  color: color,
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

            if (options.showPlaybackSpeed) {
              add(
                icon: Icons.speed_rounded,
                label: 'Playback speed',
                onTap: () {
                  Navigator.pop(context);
                  showSpeedDialog(ref);
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
                color: a.error,
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
                  showInfoDialog(context, ref, song, a.background, textColor);
                },
              );
            }

            return Column(
              children: [
                // Grabber
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: a.frame(color: a.textTertiary, radius: 2),
                  ),
                ),

                // --- HEADER ---
                _buildHeader(song, a),
                const SizedBox(height: 4),

                // --- SCROLLABLE OPTIONS ---
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 24 + MediaQuery.of(context).padding.bottom,
                    ),
                    children: rows,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Widget _buildHeader(SongModel song, WvPalette a) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: WvArtwork(
              radius: 22,
              child: QueryArtworkWidget(
                id: song.id,
                type: ArtworkType.AUDIO,
                artworkBorder: BorderRadius.zero,
                artworkFit: BoxFit.cover,
                artworkWidth: 64,
                artworkHeight: 64,
                nullArtworkWidget: WvMediaPlaceholder(seed: song.id, size: 64),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: a.text,
                    fontSize: 20,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist ?? "Unknown Artist",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: a.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildOption({
    required WvPalette a,
    required int index,
    required IconData icon,
    required String label,
    required Color? color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: a.surface,
      child: ListTile(
        leading: Icon(icon, color: color ?? a.textSecondary, size: 22),
        title: Text(
          label,
          style: TextStyle(
            color: color ?? a.text,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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
    final info = ref.read(playerProvider.notifier).getSongInfo(song);

    showAppDialog(
      builder: (_) => WvDialog(
        title: "Song Details",
        content: SingleChildScrollView(
          child: Builder(
            builder: (context) {
              final a = Wv.of(context);
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: a.frame(color: a.surfaceHighest, radius: 24),
                child: Text(
                  info,
                  style: TextStyle(color: a.text, fontSize: 14, height: 1.5),
                ),
              );
            },
          ),
        ),
        actions: [wvDialogButton("Close", () => AppNav.pop(), primary: true)],
      ),
    );
  }
}
