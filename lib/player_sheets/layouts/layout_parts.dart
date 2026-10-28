import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/playback/ab_loop.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/aqua_quality_badge.dart';
import 'package:wavvy/widgets/wv_song_list.dart';
import 'package:wavvy/screens/audio_effects/effects.screen.dart';

// The pieces every Now Playing layout is built from. A layout decides how the
// artwork and the song's name are shown and how big the controls are; the seek
// bar, the transport and the mode buttons behave the same in all of them, so a
// fix to one applies everywhere.

/// The song's title and, below it, its artist (a tap opens the About page).
class PlayerTitleBlock extends StatelessWidget {
  const PlayerTitleBlock({
    super.key,
    required this.song,
    this.onArtist,
    this.alignment = CrossAxisAlignment.start,
    this.titleSize = 22,
    this.artistSize = 14,
    this.titleLines = 2,
    this.titleColor,
    this.artistColor,
    this.shadows,
  });
  final SongModel song;
  final VoidCallback? onArtist;
  final CrossAxisAlignment alignment;
  final double titleSize;
  final double artistSize;
  final int titleLines;
  final Color? titleColor;
  final Color? artistColor;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final textAlign = switch (alignment) {
      CrossAxisAlignment.center => TextAlign.center,
      CrossAxisAlignment.end => TextAlign.end,
      _ => TextAlign.start,
    };
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          song.title,
          maxLines: titleLines,
          textAlign: textAlign,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            color: titleColor ?? a.text,
            height: 1.15,
            letterSpacing: -0.5,
            shadows: shadows,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onArtist,
          child: Text(
            song.artist ?? 'Unknown Artist',
            maxLines: 1,
            textAlign: textAlign,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: artistSize,
              color: artistColor ?? a.textSecondary,
              shadows: shadows,
            ),
          ),
        ),
      ],
    );
  }
}

/// The heart and, when lyrics are on, the button that opens them.
class PlayerSongActions extends StatelessWidget {
  const PlayerSongActions({
    super.key,
    required this.song,
    this.onLyrics,
    this.size = 44,
  });
  final SongModel song;
  final VoidCallback? onLyrics;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerFavoriteButton(song: song, size: size),
        if (onLyrics != null) ...[
          const SizedBox(width: 10),
          WvButton(
            circular: true,
            squircle: true,
            size: size,
            tooltip: 'View lyrics',
            onPressed: onLyrics,
            child: const Icon(Icons.lyrics_outlined),
          ),
        ],
      ],
    );
  }
}

/// Previous, play or pause, next. [sideHeight], [playHeight] and [playWidth]
/// size the gel buttons; with [expandSides] the side buttons share the width.
class PlayerTransport extends ConsumerWidget {
  const PlayerTransport({
    super.key,
    this.sideHeight = 60,
    this.playHeight = 68,
    this.playWidth = 88,
    this.sideIcon = 30,
    this.playIcon = 34,
    this.gap = 12,
    this.expandSides = true,
  });
  final double sideHeight;
  final double playHeight;
  final double playWidth;
  final double sideIcon;
  final double playIcon;
  final double gap;
  final bool expandSides;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final controls = ref.read(playerProvider.notifier);
    final canNext =
        state.currentIndex < state.queue.length - 1 ||
        state.loopMode == LoopMode.all;
    Widget side({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
    }) {
      final button = WvButton(
        size: sideHeight,
        width: expandSides ? null : sideHeight * 1.4,
        tooltip: tooltip,
        onPressed: onPressed,
        child: Icon(icon, size: sideIcon),
      );
      return expandSides ? Expanded(child: button) : button;
    }

    return Row(
      mainAxisSize: expandSides ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        side(
          tooltip: 'Previous',
          icon: Icons.skip_previous_rounded,
          onPressed: state.currentIndex > 0 ? controls.previous : null,
        ),
        SizedBox(width: gap),
        WvButton(
          primary: true,
          width: playWidth,
          size: playHeight,
          tooltip: state.isPlaying ? 'Pause' : 'Play',
          onPressed: controls.togglePlay,
          child: Icon(
            state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: playIcon,
          ),
        ),
        SizedBox(width: gap),
        side(
          tooltip: 'Next',
          icon: Icons.skip_next_rounded,
          onPressed: canNext ? controls.next : null,
        ),
      ],
    );
  }
}

/// Shuffle, repeat and Sound in one recessed strip.
class PlayerModeDock extends ConsumerWidget {
  const PlayerModeDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final state = ref.watch(playerProvider);
    final controls = ref.read(playerProvider.notifier);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: a.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: a.outline.withValues(alpha: 0.65)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            PlayerModeCell(
              tooltip: state.isShuffleModeEnabled ? 'Shuffle on' : 'Shuffle',
              selected: state.isShuffleModeEnabled,
              icon: Icons.shuffle_rounded,
              onPressed: controls.toggleShuffle,
            ),
            VerticalDivider(width: 1, color: a.separator),
            PlayerModeCell(
              tooltip: state.loopMode == LoopMode.off
                  ? 'Repeat'
                  : 'Repeat ${state.loopMode.name}',
              selected: state.loopMode != LoopMode.off,
              icon: PlayerUtils.getLoopIcon(state.loopMode),
              onPressed: controls.cycleLoopMode,
            ),
            VerticalDivider(width: 1, color: a.separator),
            PlayerModeCell(
              tooltip: 'Sound',
              selected: false,
              icon: Icons.tune_rounded,
              onPressed: () => AppNav.push(const AudioEffectsScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The cover as a plain rounded square (the vinyl layout has its own deck).
/// Falls back to a fetched cover or the placeholder like every other list.
class PlayerCover extends StatelessWidget {
  const PlayerCover({
    super.key,
    required this.song,
    required this.size,
    this.radius = 14,
    this.elevated = true,
  });
  final SongModel song;
  final double size;
  final double radius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: WvArtwork(
        radius: radius,
        elevated: elevated,
        child: wvArtwork(
          context,
          id: song.id,
          type: ArtworkType.AUDIO,
          size: size,
          placeholder: Icons.music_note_rounded,
        ),
      ),
    );
  }
}

class PlayerModeCell extends StatelessWidget {
  const PlayerModeCell({
    super.key,
    required this.tooltip,
    required this.selected,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final bool selected;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: selected,
          label: tooltip,
          excludeSemantics: true,
          child: InkWell(
            onTap: onPressed,
            child: Container(
              height: 48,
              color: selected ? a.primaryContainer : Colors.transparent,
              child: Icon(
                icon,
                size: 22,
                color: selected ? a.onPrimaryContainer : a.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The heart: adds the playing song to Favorites, or takes it out.
class PlayerFavoriteButton extends ConsumerWidget {
  const PlayerFavoriteButton({super.key, required this.song, this.size = 44});
  final SongModel song;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(
      favoritesProvider.select((f) => f.containsKey(song.id)),
    );
    return WvButton(
      circular: true,
      squircle: true,
      size: size,
      tooltip: liked ? 'Remove from Favorites' : 'Add to Favorites',
      onPressed: () => ref.read(favoritesProvider.notifier).toggle(song),
      child: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: liked ? const Color(0xFFD8453B) : null,
      ),
    );
  }
}

/// Skip back or forward 15 seconds, and mark a section to repeat (A-B).
class PlayerExtras extends ConsumerWidget {
  const PlayerExtras({super.key});

  static const _skip = Duration(seconds: 15);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(abLoopProvider);
    final controls = ref.read(playerProvider.notifier);
    final label = loop.isActive
        ? 'A\u2013B on'
        : loop.start != null
        ? 'Set B'
        : 'A\u2013B';
    final tooltip = loop.isActive
        ? 'Clear the repeated section'
        : loop.start != null
        ? 'Mark the end of the section to repeat'
        : 'Mark the start of a section to repeat';
    return Row(
      children: [
        Expanded(
          child: WvButton(
            size: 34,
            tooltip: 'Back 15 seconds',
            onPressed: () => controls.seek(-_skip, relative: true),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.replay_rounded, size: 16),
                SizedBox(width: 4),
                Text('15'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: WvButton(
            key: const Key('ab_loop'),
            size: 34,
            primary: loop.start != null,
            tooltip: tooltip,
            onPressed: () => ref
                .read(abLoopProvider.notifier)
                .press(ref.read(positionProvider)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.repeat_one_rounded, size: 16),
                const SizedBox(width: 4),
                Text(label),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: WvButton(
            size: 34,
            tooltip: 'Forward 15 seconds',
            onPressed: () => controls.seek(_skip, relative: true),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('15'),
                SizedBox(width: 4),
                Icon(Icons.refresh_rounded, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Aqua seek bar with elapsed/total time and a bitrate/format readout.
class PlayerSeekRow extends ConsumerStatefulWidget {
  const PlayerSeekRow({super.key, required this.song});
  final SongModel song;

  @override
  ConsumerState<PlayerSeekRow> createState() => _PlayerSeekRowState();
}

class _PlayerSeekRowState extends ConsumerState<PlayerSeekRow> {
  /// Where the thumb is while it is being dragged (milliseconds). The player
  /// is only asked to seek when the finger lifts, so scrubbing does not queue
  /// a native seek per touch event.
  double? _drag;

  SongModel get song => widget.song;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final duration = ref.watch(durationProvider);
    final playing = ref.watch(positionProvider);
    final controls = ref.read(playerProvider.notifier);
    final position = _drag == null
        ? playing
        : Duration(milliseconds: _drag!.round());
    final max = math.max(1.0, duration.inMilliseconds.toDouble());
    final loop = ref.watch(abLoopProvider);
    // Elapsed and total time sit in recessed LCD readouts, as on a Mac.
    Widget lcd(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: a.lcdDecoration.copyWith(
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: a.text,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    return Column(
      children: [
        AquaSeekBar(
          value: position.inMilliseconds.toDouble().clamp(0.0, max),
          max: max,
          step: 5000,
          loopStart: loop.start?.inMilliseconds.toDouble(),
          loopEnd: loop.end?.inMilliseconds.toDouble(),
          onChanged: (v) {
            if (duration > Duration.zero) setState(() => _drag = v);
          },
          onChangeEnd: (v) {
            if (duration <= Duration.zero) {
              setState(() => _drag = null);
              return;
            }
            // Keep the thumb where it was dropped until the player has moved,
            // so it does not jump back to the old position for a frame.
            controls.seek(Duration(milliseconds: v.toInt())).whenComplete(() {
              if (mounted) setState(() => _drag = null);
            });
          },
        ),
        Row(
          children: [
            lcd(PlayerUtils.formatDuration(position)),
            Expanded(
              child: Center(
                // Codec, rate and depth once probed; the extension and
                // average bitrate until then.
                child: SongQualityBadge(song: song, compact: true),
              ),
            ),
            lcd(PlayerUtils.formatDuration(duration)),
          ],
        ),
      ],
    );
  }
}
