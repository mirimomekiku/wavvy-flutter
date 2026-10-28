import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/selection_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/open_player.dart';
import 'package:wavvy/widgets/selection_bar.dart';
import 'package:wavvy/widgets/tray.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// Two floating Aqua trays: now playing above Home / Search / Library.
class BottomMiniPlayer extends ConsumerWidget {
  const BottomMiniPlayer({super.key, this.showTabView = true});
  final bool showTabView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While songs are being picked, the actions for them take the place of
    // the player and the tabs.
    if (ref.watch(selectionProvider.select((s) => s.active))) {
      return const SelectionBar();
    }
    final a = Wv.of(context);
    final state = ref.watch(playerProvider);
    final song = state.currentSong;
    final tabs = showTabView ? DefaultTabController.maybeOf(context) : null;
    if (song == null && tabs == null) return const SizedBox.shrink();
    final actions = ref.read(playerProvider.notifier);

    BoxDecoration tray(double radius) => wvTrayDecoration(a, radius);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (song != null)
              DecoratedBox(
                key: const Key('floating_now_playing'),
                decoration: tray(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 8, 5, 8),
                  child: GestureDetector(
                    onHorizontalDragEnd: (event) {
                      final velocity = event.primaryVelocity ?? 0;
                      if (velocity < -250) {
                        actions.next();
                      }
                      if (velocity > 250) {
                        actions.previous();
                      }
                    },
                    onVerticalDragEnd: (event) {
                      if ((event.primaryVelocity ?? 0) < -200) {
                        openWavvyPlayer(context, ref);
                      }
                    },
                    child: Row(
                      children: [
                        WvArtwork(
                          radius: 7,
                          child: wvArtwork(
                            context,
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            size: 36,
                            placeholder: Icons.music_note_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            clipBehavior: Clip.antiAlias,
                            child: Ink(
                              decoration: a.lcdDecoration.copyWith(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: InkWell(
                                key: const Key('mini_player'),
                                onTap: () => openWavvyPlayer(context, ref),
                                onLongPress: () =>
                                    openWavvyPlayer(context, ref, page: 1),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: a.text,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        song.artist ?? 'Unknown Artist',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: a.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Consumer(
                                        builder: (context, ref, _) {
                                          final position = ref
                                              .watch(positionProvider)
                                              .inMilliseconds;
                                          final duration = ref
                                              .watch(durationProvider)
                                              .inMilliseconds;
                                          return ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                            child: LinearProgressIndicator(
                                              value: duration > 0
                                                  ? (position / duration).clamp(
                                                      0.0,
                                                      1.0,
                                                    )
                                                  : 0,
                                              minHeight: 2,
                                              color: a.accent,
                                              backgroundColor: a.separator,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        IconButton(
                          tooltip: 'Previous',
                          visualDensity: VisualDensity.compact,
                          onPressed: state.currentIndex > 0
                              ? actions.previous
                              : null,
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            size: 20,
                          ),
                        ),
                        WvButton(
                          primary: true,
                          circular: true,
                          size: 34,
                          tooltip: state.isPlaying ? 'Pause' : 'Play',
                          onPressed: actions.togglePlay,
                          child: Icon(
                            state.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 22,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next',
                          visualDensity: VisualDensity.compact,
                          onPressed: state.currentIndex < state.queue.length - 1
                              ? actions.next
                              : null,
                          icon: const Icon(Icons.skip_next_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (song != null && tabs != null) const SizedBox(height: 8),
            if (tabs != null)
              DecoratedBox(
                key: const Key('floating_navigation'),
                decoration: tray(19),
                child: AnimatedBuilder(
                  animation: tabs,
                  builder: (context, _) {
                    // Display order follows the reference; controller indices stay stable.
                    const items = [
                      (Icons.home_rounded, 'Home', 0),
                      (Icons.search_rounded, 'Search', 2),
                      (Icons.library_music_outlined, 'Library', 1),
                    ];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      child: Row(
                        children: [
                          for (final item in items)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: tabs.index == item.$3,
                                label: item.$2,
                                child: Tooltip(
                                  message: item.$2,
                                  child: TextButton(
                                    key: ValueKey(
                                      'nav_${item.$2.toLowerCase()}',
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: tabs.index == item.$3
                                          ? a.accent
                                          : a.textSecondary,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      minimumSize: const Size(0, 44),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                    ),
                                    onPressed: () => tabs.animateTo(item.$3),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 25,
                                          alignment: Alignment.center,
                                          decoration: tabs.index == item.$3
                                              ? BoxDecoration(
                                                  gradient: a.gelGradient(
                                                    primary: true,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: a.accent,
                                                  ),
                                                )
                                              : null,
                                          child: Icon(
                                            item.$1,
                                            size: 18,
                                            color: tabs.index == item.$3
                                                ? a.onAccent
                                                : a.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
