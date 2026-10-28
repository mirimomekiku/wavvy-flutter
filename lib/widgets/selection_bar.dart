import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/selection_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/playlist_dialogs.dart';
import 'package:wavvy/widgets/tray.dart';

/// What to do with the picked songs: play, queue, add to a playlist, like,
/// share or delete. Replaces the mini-player tray while songs are picked.
class SelectionBar extends ConsumerWidget {
  const SelectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final selection = ref.watch(selectionProvider);
    final songs = selection.selected;
    final selecting = ref.read(selectionProvider.notifier);
    final player = ref.read(playerProvider.notifier);
    final favorites = ref.watch(favoritesProvider);
    final allLiked =
        songs.isNotEmpty && songs.every((s) => favorites.containsKey(s.id));

    Widget button(IconData icon, String tooltip, VoidCallback onPressed) =>
        IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          icon: Icon(icon, size: 22, color: a.text),
        );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: DecoratedBox(
          key: const Key('selection_bar'),
          decoration: wvTrayDecoration(a, 16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
            child: Row(
              children: [
                button(
                  Icons.close_rounded,
                  'Cancel selection',
                  selecting.clear,
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '${songs.length} selected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: a.text,
                      ),
                    ),
                  ),
                ),
                button(Icons.play_arrow_rounded, 'Play', () {
                  final picked = [...songs];
                  selecting.clear();
                  player.playSong(picked.first, contextList: picked);
                }),
                button(Icons.playlist_play_rounded, 'Play next', () {
                  final picked = [...songs];
                  selecting.clear();
                  player.playNextAll(picked);
                }),
                button(Icons.queue_music_rounded, 'Add to queue', () {
                  final picked = [...songs];
                  selecting.clear();
                  player.addAllToQueue(picked);
                }),
                button(
                  Icons.playlist_add_rounded,
                  'Add to playlist',
                  () => showAddSongsToPlaylistSheet(context, ref, [
                    ...songs,
                  ], onAdded: selecting.clear),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  padding: EdgeInsets.zero,
                  color: a.surface,
                  elevation: 6,
                  shape: aquaMenuShape(a),
                  icon: Icon(Icons.more_vert_rounded, size: 22, color: a.text),
                  onSelected: (choice) {
                    final picked = [...songs];
                    switch (choice) {
                      case 'all':
                        selecting.selectAll();
                      case 'like':
                        selecting.clear();
                        ref
                            .read(favoritesProvider.notifier)
                            .setAll(picked, liked: !allLiked);
                      case 'share':
                        selecting.clear();
                        PlayerUtils.shareSongs(picked);
                      case 'delete':
                        showConfirmDialog(
                          title: picked.length == 1
                              ? 'Delete this song?'
                              : 'Delete ${picked.length} songs?',
                          message:
                              'The files will be removed from your device.',
                          confirmText: 'Delete',
                          destructive: true,
                          onConfirm: () {
                            selecting.clear();
                            return player.deleteSongs(picked);
                          },
                        );
                    }
                  },
                  itemBuilder: (_) => [
                    if (!selection.allSelected && selection.scope.isNotEmpty)
                      const PopupMenuItem(
                        value: 'all',
                        child: Text('Select all'),
                      ),
                    PopupMenuItem(
                      value: 'like',
                      child: Text(
                        allLiked ? 'Remove from favorites' : 'Add to favorites',
                      ),
                    ),
                    const PopupMenuItem(value: 'share', child: Text('Share')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
