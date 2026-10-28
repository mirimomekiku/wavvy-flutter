import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wavvy/player_sheets/layouts/cassette_painter.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_layout_data.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';

/// A compact cassette in a tape deck. The cassette is one painting: its two
/// spools turn while the song plays, and the tape on them follows the song's
/// position (all on the left reel at the start, all on the right at the end).
/// Under it a tape counter, piano keys (rewind, play, fast forward), the seek
/// bar, the extras and the mode dock.
class CassetteLayout extends ConsumerWidget {
  const CassetteLayout({super.key, required this.data});
  final PlayerLayoutData data;

  /// Roughly what sits under the cassette (counter, keys, seek bar, extras and
  /// dock). The cassette gets what is left of the page, down to [_minWidth].
  static const _below = 400.0;
  static const _minWidth = 240.0;
  static const _maxWidth = 420.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = data.song;
    return LayoutBuilder(
      builder: (context, c) {
        final room = math.min(c.maxWidth, 480.0) - 32;
        final fit = (c.maxHeight - _below) / kCassetteAspect;
        final width = math.min(
          room,
          math.max(_minWidth, math.min(_maxWidth, fit)),
        );
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: _Cassette(data: data, width: width),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Flexible(child: _TapeCounter()),
                          const Spacer(),
                          PlayerSongActions(
                            song: song,
                            onLyrics: data.onLyrics,
                            size: 40,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const _DeckKeys(),
                      const SizedBox(height: 12),
                      PlayerSeekRow(song: song),
                      const SizedBox(height: 8),
                      const PlayerExtras(),
                      const SizedBox(height: 12),
                      const PlayerModeDock(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The cassette and the text on its label. Owns the spool animation and the
/// song-progress value the painter listens to.
class _Cassette extends ConsumerStatefulWidget {
  const _Cassette({required this.data, required this.width});
  final PlayerLayoutData data;
  final double width;

  @override
  ConsumerState<_Cassette> createState() => _CassetteState();
}

class _CassetteState extends ConsumerState<_Cassette>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: kCassetteSpinCycle,
  );
  final _progress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _update();
    // Position ticks about every 200 ms; they only move the painter.
    ref.listenManual(positionProvider, (_, _) => _update());
    ref.listenManual(durationProvider, (_, _) => _update());
  }

  void _update() {
    final position = ref.read(positionProvider);
    final duration = ref.read(durationProvider);
    _progress.value = duration <= Duration.zero
        ? 0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _spin.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final still = MediaQuery.disableAnimationsOf(context);
    // A hidden page mutes its ticker (TickerMode), so nothing runs off screen.
    if (playing && !still) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
    }
    final g = CassetteGeometry(widget.width);
    final song = widget.data.song;
    final label = g.label;
    final w = g.w;
    // Plain label when the song has no album, so no art to stick on.
    final sticker = song.albumId != null;
    const ink = Color(0xFF24272D);
    final tilt = Transform.rotate(
      angle: kCassetteLabelTilt,
      child: SizedBox(
        width: label.width,
        height: label.height,
        child: MediaQuery(
          // The cassette is a picture: its writing is sized to it, not to the
          // reader's text size, or it would spill off the label.
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: w * 0.02,
                top: (g.stripe - w * 0.05) / 2,
                width: w * 0.05,
                height: w * 0.05,
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        'A',
                        style: TextStyle(
                          fontSize: w * 0.034,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: w * 0.045,
                right: w * (sticker ? 0.2 : 0.045),
                top: w * 0.083,
                height: w * 0.082,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: w * 0.064,
                      fontWeight: FontWeight.w800,
                      fontStyle: FontStyle.italic,
                      height: 1.1,
                      color: ink,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: w * 0.045,
                right: w * (sticker ? 0.2 : 0.045),
                top: w * 0.172,
                height: w * 0.062,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.data.onArtist,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      song.artist ?? 'Unknown Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: w * 0.044,
                        fontStyle: FontStyle.italic,
                        height: 1.1,
                        color: ink.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ),
              ),
              if (sticker)
                Positioned(
                  right: w * 0.03,
                  top: w * 0.015,
                  child: ExcludeSemantics(
                    child: Transform.rotate(
                      angle: 0.09,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(w * 0.012),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(w * 0.006),
                          child: PlayerCover(
                            song: song,
                            size: w * 0.15,
                            radius: w * 0.008,
                            elevated: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return SizedBox(
      width: g.w,
      height: g.h,
      child: Stack(
        children: [
          // The shadow is outside the repainting part, so it is drawn once.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(g.radius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: a.dark ? 0.55 : 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Semantics(
              label: 'Cassette tape',
              image: true,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: CassettePainter(
                    a: a,
                    spin: _spin,
                    progress: _progress,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: label.left,
            top: label.top,
            width: label.width,
            height: label.height,
            child: tilt,
          ),
        ],
      ),
    );
  }
}

/// The tape counter: the elapsed time in a recessed LCD.
class _TapeCounter extends ConsumerWidget {
  const _TapeCounter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final position = ref.watch(positionProvider);
    final time = PlayerUtils.formatDuration(position);
    return Semantics(
      label: 'Tape counter',
      value: time,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: a.lcdDecoration.copyWith(
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              time,
              maxLines: 1,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                height: 1.1,
                color: a.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rewind, play and fast forward as chunky piano keys. Same rules as
/// [PlayerTransport]: previous needs a song before it, next needs one after
/// it (or repeat all), and play drawn pressed in while the song plays.
class _DeckKeys extends ConsumerWidget {
  const _DeckKeys();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final state = ref.watch(playerProvider);
    final controls = ref.read(playerProvider.notifier);
    final canNext =
        state.currentIndex < state.queue.length - 1 ||
        state.loopMode == LoopMode.all;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: a.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: a.outline.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _DeckKey(
                  caption: 'REW',
                  tooltip: 'Previous',
                  icon: Icons.fast_rewind_rounded,
                  onPressed: state.currentIndex > 0 ? controls.previous : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: _DeckKey(
                  caption: 'PLAY',
                  tooltip: state.isPlaying ? 'Pause' : 'Play',
                  icon: state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  pressed: state.isPlaying,
                  onPressed: controls.togglePlay,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _DeckKey(
                  caption: 'FF',
                  tooltip: 'Next',
                  icon: Icons.fast_forward_rounded,
                  onPressed: canNext ? controls.next : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One key: raised, or pressed in (lower, darker, with an inner shadow and
/// a lit lamp). Semantics and tooltip say what it does.
class _DeckKey extends StatelessWidget {
  const _DeckKey({
    required this.caption,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.pressed = false,
  });
  final String caption;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final enabled = onPressed != null;
    final base = a.gelGradient();
    final colors = pressed
        ? [for (final c in base.colors) Color.lerp(c, Colors.black, 0.2)!]
        : base.colors;
    final fg = enabled ? a.text : a.textSecondary.withValues(alpha: 0.45);
    const lift = 3.0;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: pressed,
        label: tooltip,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Padding(
            // Pressed in: the key sits lower and its edge shadow is gone.
            padding: EdgeInsets.only(
              top: pressed ? lift : 0,
              bottom: pressed ? 0 : lift,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: colors,
                  stops: base.stops,
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: a.outline.withValues(alpha: 0.8)),
                boxShadow: pressed
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: a.dark ? 0.7 : 0.35,
                          ),
                          offset: const Offset(0, lift),
                        ),
                      ],
              ),
              child: Stack(
                children: [
                  if (pressed)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.35),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (pressed)
                    Positioned(
                      top: 5,
                      right: 6,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: a.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 46),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 26, color: fg),
                            Text(
                              caption,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: fg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The thumbnail for the layout picker: a small cassette with two reels and a
/// label, in the theme's colors.
class CassetteLayoutPreview extends StatelessWidget {
  const CassetteLayoutPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Semantics(
        label: 'Cassette deck preview',
        excludeSemantics: true,
        child: Center(
          child: AspectRatio(
            aspectRatio: 1 / kCassetteAspect,
            child: CustomPaint(
              painter: CassettePainter(
                a: a,
                spin: const AlwaysStoppedAnimation<double>(0.07),
                progress: const StillValue(0.4),
                mini: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
