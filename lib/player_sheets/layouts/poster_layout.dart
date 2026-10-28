import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_backdrop.dart';
import 'package:wavvy/player_sheets/layouts/player_layout_data.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/audio_effects/effects.screen.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';

/// How opaque the page color is under the title, seek bar and buttons, on top
/// of the backdrop's own wash. Text must stay readable over any cover.
const double kPosterScrimAlpha = 0.5;

/// Swiping up faster than this (logical pixels per second) opens the queue.
const double _kSwipeVelocity = 300;

/// The cover fills the page as a blurred backdrop; on top, a large sharp cover,
/// big left-aligned type, a thin seek bar and few controls. A handle at the
/// bottom opens the Queue (a tap, or a swipe up anywhere that is not
/// scrolling).
class PosterLayout extends ConsumerWidget {
  const PosterLayout({super.key, required this.data});
  final PlayerLayoutData data;

  /// Opens the queue for a fast enough upward fling.
  void _swipe(DragEndDetails d) {
    if ((d.primaryVelocity ?? 0) < -_kSwipeVelocity) data.onQueue?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final song = data.song;
    return Stack(
      fit: StackFit.expand,
      children: [
        PlayerBackdrop(song: song),
        LayoutBuilder(
          builder: (context, c) {
            final width = math.min(c.maxWidth, 480.0) - 40;
            // Room for what is under the cover: title, seek bar, buttons and
            // the handle.
            final side = math.min(width, math.max(120.0, c.maxHeight - 430));
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              // Only reached when the content does not scroll (a scrolling
              // list takes the drag itself); the handle always works.
              onVerticalDragEnd: data.onQueue == null ? null : _swipe,
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            child: Center(
                              child: PlayerCover(
                                song: song,
                                size: side,
                                radius: 20,
                              ),
                            ),
                          ),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // The scrim under the text: a short fade in
                              // from the cover, then steady.
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          a.background.withValues(alpha: 0),
                                          a.background.withValues(
                                            alpha: kPosterScrimAlpha,
                                          ),
                                        ],
                                        stops: const [0, 0.08],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  0,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    PlayerTitleBlock(
                                      song: song,
                                      onArtist: data.onArtist,
                                      titleSize: 30,
                                      artistSize: 16,
                                    ),
                                    const SizedBox(height: 14),
                                    PlayerSeekRow(song: song),
                                    const SizedBox(height: 10),
                                    const _PosterTransport(),
                                    const SizedBox(height: 12),
                                    _PosterActions(data: data),
                                    _QueueHandle(data: data),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Previous, a large round play or pause, next.
class _PosterTransport extends ConsumerWidget {
  const _PosterTransport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final controls = ref.read(playerProvider.notifier);
    final canNext =
        state.currentIndex < state.queue.length - 1 ||
        state.loopMode == LoopMode.all;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        WvButton(
          circular: true,
          size: 56,
          tooltip: 'Previous',
          onPressed: state.currentIndex > 0 ? controls.previous : null,
          child: const Icon(
            Icons.skip_previous_rounded,
            size: 30,
            semanticLabel: 'Previous',
          ),
        ),
        const SizedBox(width: 24),
        WvButton(
          circular: true,
          primary: true,
          size: 76,
          tooltip: state.isPlaying ? 'Pause' : 'Play',
          onPressed: controls.togglePlay,
          child: Icon(
            state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 40,
            semanticLabel: state.isPlaying ? 'Pause' : 'Play',
          ),
        ),
        const SizedBox(width: 24),
        WvButton(
          circular: true,
          size: 56,
          tooltip: 'Next',
          onPressed: canNext ? controls.next : null,
          child: const Icon(
            Icons.skip_next_rounded,
            size: 30,
            semanticLabel: 'Next',
          ),
        ),
      ],
    );
  }
}

/// The heart, lyrics and queue buttons, then shuffle, repeat and Sound as small
/// icons. Wraps to a second line on narrow screens.
class _PosterActions extends ConsumerWidget {
  const _PosterActions({required this.data});
  final PlayerLayoutData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final controls = ref.read(playerProvider.notifier);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        PlayerSongActions(song: data.song, onLyrics: data.onLyrics),
        if (data.onQueue != null)
          WvButton(
            circular: true,
            squircle: true,
            size: 44,
            tooltip: 'Open queue',
            onPressed: data.onQueue,
            child: const Icon(
              Icons.queue_music_rounded,
              semanticLabel: 'Open queue',
            ),
          ),
        _ModeIcon(
          tooltip: state.isShuffleModeEnabled ? 'Shuffle on' : 'Shuffle',
          selected: state.isShuffleModeEnabled,
          icon: Icons.shuffle_rounded,
          onPressed: controls.toggleShuffle,
        ),
        _ModeIcon(
          tooltip: state.loopMode == LoopMode.off
              ? 'Repeat'
              : 'Repeat ${state.loopMode.name}',
          selected: state.loopMode != LoopMode.off,
          icon: PlayerUtils.getLoopIcon(state.loopMode),
          onPressed: controls.cycleLoopMode,
        ),
        _ModeIcon(
          tooltip: 'Sound',
          selected: false,
          icon: Icons.tune_rounded,
          onPressed: () => AppNav.push(const AudioEffectsScreen()),
        ),
      ],
    );
  }
}

/// A small plain icon button for the playback modes.
class _ModeIcon extends StatelessWidget {
  const _ModeIcon({
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
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        child: InkResponse(
          onTap: onPressed,
          radius: 24,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              icon,
              size: 24,
              color: selected ? a.accent : a.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The small bar at the bottom: a tap or a swipe up opens the Queue.
class _QueueHandle extends StatelessWidget {
  const _QueueHandle({required this.data});
  final PlayerLayoutData data;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final onQueue = data.onQueue;
    return Semantics(
      button: true,
      label: 'Queue',
      excludeSemantics: true,
      onTap: onQueue,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onQueue,
        onVerticalDragEnd: onQueue == null
            ? null
            : (d) {
                if ((d.primaryVelocity ?? 0) < -_kSwipeVelocity) onQueue();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: a.textSecondary.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Queue',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: a.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// The picker thumbnail: a blurred gradient, a rounded square, two text bars
/// and a round button, in theme colors.
class PosterLayoutPreview extends StatelessWidget {
  const PosterLayoutPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    Widget bar(double width, double height, Color color) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  a.accent.withValues(alpha: 0.7),
                  a.surfaceHigh,
                  a.accent.withValues(alpha: 0.35),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: a.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: a.outline.withValues(alpha: 0.6),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.music_note_rounded,
                        color: a.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              bar(60, 7, a.text),
              const SizedBox(height: 4),
              bar(38, 5, a.textSecondary),
              const Spacer(),
              Center(
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: a.accent,
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 14,
                    color: a.onAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
