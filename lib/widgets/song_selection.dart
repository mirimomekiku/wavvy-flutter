import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/selection_provider.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// A [WvSongRow] that takes part in picking songs for a bulk action: a long
/// press starts picking, and while picking a tap picks or drops the song
/// instead of playing it.
///
/// [scope] is the list the row is in, so "Select all" can select all of it.
class SelectableSongRow extends ConsumerWidget {
  const SelectableSongRow({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.secondary,
    required this.onTap,
    required this.onAction,
    this.scope = const [],
    this.actionIcon = Icons.more_horiz_rounded,
    this.actionTooltip = 'More options',
  });
  final SongModel song;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final String secondary;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final List<SongModel> scope;
  final IconData actionIcon;
  final String actionTooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Each row follows only its own picked state, so picking one song does not
    // rebuild the whole list.
    final selecting = ref.watch(selectionProvider.select((s) => s.active));
    final selected = ref.watch(
      selectionProvider.select((s) => s.contains(song.id)),
    );
    final selection = ref.read(selectionProvider.notifier);
    return WvSongRow(
      song: song,
      index: index,
      isCurrent: isCurrent,
      isPlaying: isPlaying,
      secondary: secondary,
      selecting: selecting,
      selected: selected,
      onTap: selecting ? () => selection.toggle(song) : onTap,
      onLongPress: () {
        HapticFeedback.selectionClick();
        if (selecting) {
          selection.toggle(song);
        } else {
          selection.start(song, scope: scope);
        }
      },
      onAction: onAction,
      actionIcon: actionIcon,
      actionTooltip: actionTooltip,
    );
  }
}
