import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/player_sheets/queue_selection.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/queue_selection_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// The Queue page of the player sheet (also embedded by the two-pane layout).
class PlayerQueuePage extends ConsumerWidget {
  const PlayerQueuePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final state = ref.watch(playerProvider);
    final queue = state.queue;
    final occurrences = <int, int>{};
    final rowKeys = [
      for (final s in queue)
        ValueKey(
          'queue-${s.id}-${occurrences.update(s.id, (n) => n + 1, ifAbsent: () => 0)}',
        ),
    ];
    final controls = ref.read(playerProvider.notifier);
    final totalMs = queue.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final hasUpcoming = state.currentIndex < queue.length - 1;
    final selection = ref.watch(queueSelectionProvider);
    final selecting = selection.active;
    return Column(
      children: [
        if (selecting)
          const QueueSelectionHeader()
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Up next',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: a.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${queue.length} ${queue.length == 1 ? 'track' : 'tracks'}'
                        ' \u00b7 ${PlayerUtils.formatDuration(Duration(milliseconds: totalMs))}',
                        style: TextStyle(fontSize: 12, color: a.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                WvButton(
                  size: 38,
                  width: 112,
                  tooltip: 'Clear upcoming',
                  onPressed: hasUpcoming ? controls.clearUpcoming : null,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.playlist_remove_rounded),
                      SizedBox(width: 6),
                      Text('Clear'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          // A row keeps its key when others are moved or removed, so it is
          // not rebuilt (and its artwork not reloaded); the same song twice
          // is told apart by which occurrence it is.
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            buildDefaultDragHandles: false,
            itemCount: queue.length,
            onReorderItem: controls.moveQueueItem,
            itemExtent: math.max(
              76.0,
              MediaQuery.textScalerOf(context).scale(40) + 36,
            ),
            itemBuilder: (context, index) {
              final song = queue[index];
              final current = state.currentIndex == index;
              final picked = selection.contains(index);
              return Padding(
                key: rowKeys[index],
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Material(
                  color: current
                      ? a.primaryContainer
                      : picked
                      ? Color.alphaBlend(
                          a.accent.withValues(alpha: 0.14),
                          a.surface,
                        )
                      : a.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: current || picked
                          ? a.accent.withValues(alpha: 0.55)
                          : a.separator,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    // A long press starts picking rows; then a tap picks or
                    // drops a row instead of jumping to it.
                    onLongPress: selecting
                        ? null
                        : () => ref
                              .read(queueSelectionProvider.notifier)
                              .start(index),
                    onTap: selecting
                        ? () => ref
                              .read(queueSelectionProvider.notifier)
                              .toggle(index)
                        : () {
                            if (!current) {
                              ref
                                  .read(audioPlayerProvider)
                                  .seek(Duration.zero, index: index);
                              ref.read(audioPlayerProvider).play();
                            }
                          },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                      child: Row(
                        children: [
                          WvArtwork(
                            radius: 8,
                            child: wvArtwork(
                              context,
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              size: 44,
                              placeholder: Icons.music_note_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: current
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: current
                                        ? a.onPrimaryContainer
                                        : a.text,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  song.artist ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: current
                                        ? a.onPrimaryContainer.withValues(
                                            alpha: 0.75,
                                          )
                                        : a.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (current)
                            Icon(
                              Icons.graphic_eq_rounded,
                              size: 20,
                              color: a.accent,
                            ),
                          if (selecting)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: AquaCheckbox(value: picked, size: 22),
                            )
                          else ...[
                            IconButton(
                              tooltip: 'Remove from queue',
                              onPressed: () => controls.removeFromQueue(index),
                              icon: Icon(
                                Icons.close_rounded,
                                color: a.textSecondary,
                                size: 18,
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: Semantics(
                                label: 'Reorder ${song.title}',
                                child: SizedBox(
                                  width: 32,
                                  height: 48,
                                  child: Icon(
                                    Icons.drag_indicator_rounded,
                                    size: 22,
                                    color: a.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
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
