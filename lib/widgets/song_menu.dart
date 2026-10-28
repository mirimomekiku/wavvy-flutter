import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/audio_effects/effects.screen.dart';
import 'package:wavvy/screens/library/albums/view/album.screen.dart';
import 'package:wavvy/screens/library/artists/view/artist.screen.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/utils/snackbar.utils.dart';
import 'package:wavvy/widgets/album_art_fallback.dart';
import 'package:wavvy/widgets/audio_dialogs.dart';
import 'package:wavvy/player_sheets/player_dialogs.dart';
import 'package:wavvy/widgets/playlist_dialogs.dart';

class SongMenuOptions {
  final bool showPlayNext;
  final bool showFavorite;
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
    this.showFavorite = true,
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
    showAquaSheet<void>(
      context: context,
      title: 'Song',
      builder: (sheetContext) {
        // Closes the sheet, then runs [then].
        VoidCallback close(VoidCallback then) => () {
          Navigator.pop(sheetContext);
          then();
        };

        final liked = ref.read(favoritesProvider).containsKey(song.id);
        final queue = <AquaMenuRow>[
          if (options.showPlayNext)
            AquaMenuRow(
              icon: Icons.playlist_play_rounded,
              label: 'Play Next',
              onTap: close(
                () => ref.read(playerProvider.notifier).playNext(song),
              ),
            ),
          if (options.showAddToQueue)
            AquaMenuRow(
              icon: Icons.queue_music_rounded,
              label: 'Add to Queue',
              onTap: close(
                () => ref.read(playerProvider.notifier).addToQueue(song),
              ),
            ),
          if (options.showFavorite)
            AquaMenuRow(
              icon: liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: liked ? 'Remove from Favorites' : 'Add to Favorites',
              onTap: close(
                () => ref.read(favoritesProvider.notifier).toggle(song),
              ),
            ),
          if (options.showAddToPlaylist)
            AquaMenuRow(
              icon: Icons.playlist_add_rounded,
              label: 'Add to Playlist',
              chevron: true,
              onTap: close(() => showAddToPlaylistSheet(context, ref, song)),
            ),
        ];

        final sound = <AquaMenuRow>[
          if (options.showPlaybackSpeed)
            AquaMenuRow(
              icon: Icons.speed_rounded,
              label: 'Speed & pitch',
              onTap: close(() => showSpeedDialog(ref)),
            ),
          if (options.showSleepTimer)
            AquaMenuRow(
              icon: Icons.timer_rounded,
              label: 'Sleep timer',
              onTap: close(() => openSleepTimerDialog(ref)),
            ),
          if (options.showCustomEqualizer)
            AquaMenuRow(
              icon: Icons.equalizer_rounded,
              label: 'Custom equalizer',
              chevron: true,
              onTap: close(() => AppNav.push(const AudioEffectsScreen())),
            ),
          if (options.showSystemEqualizer)
            AquaMenuRow(
              icon: Icons.surround_sound_rounded,
              label: 'System equalizer',
              onTap: () => PlayerUtils.openEqualizer(
                ref.read(audioPlayerProvider).androidAudioSessionId,
              ),
            ),
        ];

        final about = <AquaMenuRow>[
          if (options.showGoToArtist)
            AquaMenuRow(
              icon: Icons.person_rounded,
              label: 'Go to Artist',
              chevron: true,
              onTap: () => _handleGoToArtist(sheetContext, ref, song),
            ),
          if (options.showGoToAlbum)
            AquaMenuRow(
              icon: Icons.album_rounded,
              label: 'Go to Album',
              chevron: true,
              onTap: () => _handleGoToAlbum(sheetContext, ref, song),
            ),
          if (options.showShare)
            AquaMenuRow(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              onTap: close(() => PlayerUtils.shareSong(song)),
            ),
          if (options.showEditTags)
            AquaMenuRow(
              icon: Icons.edit_rounded,
              label: 'Edit tags',
              onTap: close(() => editSongTags(ref, song)),
            ),
          if (options.showSongInfo)
            AquaMenuRow(
              icon: Icons.info_outline_rounded,
              label: 'Song Info',
              onTap: close(() => showSongDetailsDialog(song)),
            ),
        ];

        final danger = <AquaMenuRow>[
          if (options.showDelete)
            AquaMenuRow(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              destructive: true,
              onTap: close(() => confirmDeleteSong(ref, song)),
            ),
        ];

        return ListView(
          shrinkWrap: true,
          padding: EdgeInsets.only(
            top: 12,
            bottom: 12 + MediaQuery.paddingOf(sheetContext).bottom,
          ),
          children: [
            _buildHeader(sheetContext, song),
            for (final group in [queue, sound, about, danger])
              if (group.isNotEmpty) AquaMenuGroup(rows: group),
          ],
        );
      },
    );
  }

  /// The song as a recessed LCD readout at the top of the sheet.
  static Widget _buildHeader(BuildContext context, SongModel song) {
    final a = Wv.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.all(10),
      decoration: a.lcdDecoration.copyWith(
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          WvArtwork(
            radius: 7,
            child: SizedBox.square(
              dimension: 52,
              child: QueryArtworkWidget(
                id: song.id,
                type: ArtworkType.AUDIO,
                artworkBorder: BorderRadius.zero,
                artworkFit: BoxFit.cover,
                artworkWidth: 52,
                artworkHeight: 52,
                nullArtworkWidget: AlbumArtFallback(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  size: 52,
                  seed: song.id,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
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
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist ?? "Unknown Artist",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: a.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
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
}
