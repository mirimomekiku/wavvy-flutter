import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wavvy/player_sheets/layouts/cd_disc.dart';
import 'package:wavvy/player_sheets/layouts/cd_marquee.dart';
import 'package:wavvy/player_sheets/layouts/cd_segment_display.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_layout_data.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';

/// A portable CD player: a chrome body with a segment display (track out of
/// the queue, elapsed time, play / pause / repeat / shuffle lamps) over a
/// spinning disc in its well, then the title as a marquee, the seek bar, big
/// rounded buttons and the mode dock. The page scrolls when it does not fit;
/// the disc shrinks first.
class CdLayout extends ConsumerWidget {
  const CdLayout({super.key, required this.data});
  final PlayerLayoutData data;

  /// The disc stops shrinking here; below this the page scrolls.
  static const _minWell = 112.0;

  /// Roughly the height of everything that is not the disc.
  static const _reserved = 480.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final song = data.song;
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    return LayoutBuilder(
      builder: (context, c) {
        final width = math.min(c.maxWidth, 480.0) - 32;
        final well = math.min(
          width - 24,
          math.max(_minWell, c.maxHeight - _reserved),
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
                      _Chrome(
                        radius: 20,
                        padding: const EdgeInsets.all(12),
                        shadow: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _CdLcd(),
                            const SizedBox(height: 10),
                            Center(
                              child: CdWell(
                                song: song,
                                side: well,
                                playing: playing,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CdMarquee(
                                  text: song.title,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: a.text,
                                    height: 1.15,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                CdMarquee(
                                  text: song.artist ?? 'Unknown Artist',
                                  onTap: data.onArtist,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: a.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          PlayerSongActions(
                            song: song,
                            onLyrics: data.onLyrics,
                            size: 40,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      PlayerSeekRow(song: song),
                      const SizedBox(height: 6),
                      const PlayerExtras(),
                      const SizedBox(height: 10),
                      const _Chrome(
                        radius: 22,
                        padding: EdgeInsets.all(8),
                        child: PlayerTransport(
                          sideHeight: 58,
                          playHeight: 66,
                          playWidth: 96,
                          sideIcon: 32,
                          playIcon: 36,
                          gap: 10,
                        ),
                      ),
                      const SizedBox(height: 14),
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

/// The player's brushed-chrome plastic.
class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.radius,
    required this.padding,
    required this.child,
    this.shadow = false,
  });
  final double radius;
  final EdgeInsets padding;
  final Widget child;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: a.chromeGradient,
        image: a.chromeGrain,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: a.outline.withValues(alpha: 0.7)),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: a.dark ? 0.5 : 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The display: track number out of the queue, the elapsed time and four
/// lamps. Scaled down as a whole when it is too wide, never clipped.
class _CdLcd extends ConsumerWidget {
  const _CdLcd();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final state = ref.watch(playerProvider);
    final lit = cdLitColor(a);
    final dim = cdDimColor(lit);
    final trackText = cdTrackText(state.currentIndex, state.queue.length);
    final trackLabel = state.currentIndex < 0 || state.queue.isEmpty
        ? 'No track'
        : 'Track ${state.currentIndex + 1} of ${state.queue.length}';

    Widget caption(String text) => Text(
      text,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: 8.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: lit.withValues(alpha: 0.7),
      ),
    );
    Widget lamp(IconData icon, bool on, String onLabel, String offLabel) =>
        Semantics(
          label: on ? onLabel : offLabel,
          excludeSemantics: true,
          child: Icon(icon, size: 17, color: on ? lit : dim),
        );

    final repeat = state.loopMode != LoopMode.off;
    return DecoratedBox(
      decoration: a.lcdDecoration.copyWith(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                label: trackLabel,
                excludeSemantics: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    caption('TRACK'),
                    const SizedBox(height: 3),
                    CdSegmentText(
                      text: trackText,
                      height: 18,
                      lit: lit,
                      dim: dim,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  caption('TIME'),
                  const SizedBox(height: 3),
                  _CdElapsed(lit: lit, dim: dim),
                ],
              ),
              const SizedBox(width: 16),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      lamp(
                        Icons.play_arrow_rounded,
                        state.isPlaying,
                        'Playing',
                        'Not playing',
                      ),
                      const SizedBox(width: 6),
                      lamp(
                        Icons.pause_rounded,
                        !state.isPlaying,
                        'Paused',
                        'Not paused',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      lamp(
                        state.loopMode == LoopMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        repeat,
                        state.loopMode == LoopMode.one
                            ? 'Repeat one on'
                            : 'Repeat on',
                        'Repeat off',
                      ),
                      const SizedBox(width: 6),
                      lamp(
                        Icons.shuffle_rounded,
                        state.isShuffleModeEnabled,
                        'Shuffle on',
                        'Shuffle off',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The elapsed time, on its own so only it follows the position.
class _CdElapsed extends ConsumerWidget {
  const _CdElapsed({required this.lit, required this.dim});
  final Color lit;
  final Color dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider);
    return Semantics(
      label: 'Elapsed ${PlayerUtils.formatDuration(position)}',
      excludeSemantics: true,
      child: CdSegmentText(
        text: cdTimeText(position),
        height: 30,
        lit: lit,
        dim: dim,
      ),
    );
  }
}

/// The thumbnail for the layout picker: a disc with a hub in its well under a
/// small segment strip, in the theme's colors.
class CdLayoutPreview extends StatelessWidget {
  const CdLayoutPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Semantics(
        label: 'CD player preview',
        excludeSemantics: true,
        child: CustomPaint(
          painter: _PreviewPainter(a),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.a);
  final WvPalette a;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final lit = cdLitColor(a);
    // The segment strip.
    final strip = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.16, h * 0.02, w * 0.68, h * 0.2),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      strip,
      Paint()
        ..color = a.dark ? const Color(0xFF1E2A30) : const Color(0xFFE9EEEC),
    );
    canvas.drawRRect(
      strip,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = a.outline,
    );
    const text = '03:21';
    final digits = h * 0.12;
    final tw = cdSegmentWidth(text, digits);
    paintCdSegments(
      canvas,
      text,
      Offset((w - tw) / 2, strip.top + (strip.height - digits) / 2),
      digits,
      lit: lit,
      dim: cdDimColor(lit),
    );
    // The well and the disc.
    final center = Offset(w * 0.5, h * 0.56);
    final r = math.min(w * 0.32, h * 0.28);
    canvas.drawCircle(
      center,
      r * 1.12,
      Paint()..color = a.outline.withValues(alpha: a.dark ? 0.55 : 0.35),
    );
    final box = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [
            a.accent.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0.7),
            a.accent.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.6),
            a.accent.withValues(alpha: 0.85),
          ],
        ).createShader(box),
    );
    canvas.drawCircle(
      center,
      r * 0.34,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.1
        ..color = Colors.white.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      center,
      r * 0.22,
      Paint()..color = const Color(0xFFD5D9DE),
    );
    canvas.drawCircle(center, r * 0.08, Paint()..color = cdHoleColor(a.dark));
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black.withValues(alpha: 0.3),
    );
    // Three buttons.
    final key = Paint()..color = a.textSecondary.withValues(alpha: 0.6);
    for (final f in const [0.34, 0.5, 0.66]) {
      canvas.drawCircle(Offset(w * f, h * 0.95), h * 0.03, key);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.a != a;
}
