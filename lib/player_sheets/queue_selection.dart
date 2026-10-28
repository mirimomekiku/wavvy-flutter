import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/queue_selection_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/playlist_dialogs.dart';

/// The Queue page's header while rows are picked: the count, Select all / none
/// and what to do with the picked rows, on an Aqua toolbar.
class QueueSelectionHeader extends ConsumerWidget {
  const QueueSelectionHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final selection = ref.watch(queueSelectionProvider);
    final length = ref.watch(playerProvider.select((s) => s.queue.length));
    final selecting = ref.read(queueSelectionProvider.notifier);
    final player = ref.read(playerProvider.notifier);
    final any = selection.count > 0;
    final all = length > 0 && selection.count == length;

    // The picked rows' songs, in queue order.
    List<SongModel> songs() {
      final queue = ref.read(playerProvider).queue;
      return [
        for (final i in selection.sorted)
          if (i < queue.length) queue[i],
      ];
    }

    void remove() {
      final picked = selection.picked.toSet();
      void go() {
        selecting.clear();
        player.removeQueueIndices(picked);
      }

      if (picked.contains(ref.read(playerProvider).currentIndex)) {
        showConfirmDialog(
          title: 'Remove the playing song?',
          message:
              'The selection includes the song that is playing. Playback '
              'moves on to the next song.',
          confirmText: 'Remove',
          destructive: true,
          onConfirm: go,
        );
      } else {
        go();
      }
    }

    Widget action(
      IconData icon,
      String tooltip,
      VoidCallback onPressed, {
      bool danger = false,
    }) => Expanded(
      child: WvButton(
        size: 40,
        tooltip: tooltip,
        onPressed: any ? onPressed : null,
        child: Icon(icon, size: 21, color: danger && any ? a.error : null),
      ),
    );

    const gap = SizedBox(width: 8);
    // Back leaves selecting first; only then does it close the sheet.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) selecting.clear();
      },
      child: DecoratedBox(
        key: const Key('queue_selection_header'),
        decoration: BoxDecoration(
          gradient: a.chromeGradient,
          image: a.chromeGrain,
          border: Border(bottom: BorderSide(color: a.separator)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Cancel selection',
                    onPressed: selecting.clear,
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '${selection.count} selected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: a.text,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: all ? selecting.selectNone : selecting.selectAll,
                    child: Text(all ? 'Select none' : 'Select all'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  children: [
                    action(
                      Icons.delete_outline_rounded,
                      'Remove',
                      remove,
                      danger: true,
                    ),
                    gap,
                    action(Icons.playlist_play_rounded, 'Play next', () {
                      final picked = selection.picked.toSet();
                      selecting.clear();
                      player.moveQueueIndicesToNext(picked);
                    }),
                    gap,
                    action(
                      Icons.vertical_align_bottom_rounded,
                      'Move to end',
                      () {
                        final picked = selection.picked.toSet();
                        selecting.clear();
                        player.moveQueueIndicesToEnd(picked);
                      },
                    ),
                    gap,
                    action(
                      Icons.playlist_add_rounded,
                      'Add to playlist',
                      () => showAddSongsToPlaylistSheet(
                        context,
                        ref,
                        songs(),
                        onAdded: selecting.clear,
                      ),
                    ),
                    gap,
                    action(
                      Icons.library_add_rounded,
                      'Save as playlist',
                      () => showSaveAsPlaylistDialog(
                        ref,
                        songs(),
                        onSaved: selecting.clear,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
