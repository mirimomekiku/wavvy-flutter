import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// The recessed circular well of the CD player, with the spinning disc in it
/// and a glass lid highlight over both. Only the disc moves.
class CdWell extends StatelessWidget {
  const CdWell({
    super.key,
    required this.song,
    required this.side,
    required this.playing,
  });
  final SongModel song;
  final double side;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final disc = side * 0.9;
    return Semantics(
      label: playing ? 'Disc, spinning' : 'Disc, stopped',
      excludeSemantics: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: side,
          child: CustomPaint(
            painter: _WellPainter(dark: a.dark, outline: a.outline),
            foregroundPainter: _LidPainter(dark: a.dark),
            child: Center(
              child: CdDisc(
                song: song,
                size: disc,
                playing: playing,
                hole: cdHoleColor(a.dark),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What shows through the hole in the middle of the disc.
Color cdHoleColor(bool dark) =>
    dark ? const Color(0xFF0A0E10) : const Color(0xFF7C858B);

/// The disc: the cover as a circle with a CD's look on top. One turn takes
/// [turnTime]; it eases to a stop when [playing] ends and goes on from the
/// same angle, and it stays still with reduced motion or when its page is not
/// showing.
class CdDisc extends StatefulWidget {
  const CdDisc({
    super.key,
    required this.song,
    required this.size,
    required this.playing,
    required this.hole,
  });
  final SongModel song;
  final double size;
  final bool playing;
  final Color hole;

  static const turnTime = Duration(seconds: 3);

  @override
  State<CdDisc> createState() => _CdDiscState();
}

class _CdDiscState extends State<CdDisc> with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: CdDisc.turnTime,
  );

  bool _spinning = false;

  void _syncMotion() {
    final animate =
        widget.playing &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate == _spinning) return;
    _spinning = animate;
    if (animate) {
      if (_rotation.value >= 1) _rotation.value = 0;
      // From wherever it stopped, also while it is still easing to a stop.
      _rotation.repeat();
    } else {
      // Slow down over a moment rather than freezing, never past one turn
      // (the end of the range looks the same as the start).
      final to = math.min(1.0, _rotation.value + 0.08);
      _rotation.animateTo(
        to,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(CdDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _rotation,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipOval(
                child: wvArtwork(
                  context,
                  id: widget.song.id,
                  type: ArtworkType.AUDIO,
                  size: widget.size,
                  placeholder: Icons.music_note_rounded,
                ),
              ),
              CustomPaint(painter: _DiscPainter(hole: widget.hole)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The CD over the cover: an iridescent sheen, the clear ring around the hub,
/// the hub and its hole, and a thin edge.
class _DiscPainter extends CustomPainter {
  const _DiscPainter({required this.hole});
  final Color hole;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    const clear = Color(0x00FFFFFF);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [
            clear,
            Colors.white.withValues(alpha: 0.26),
            const Color(0xFF7FE3FF).withValues(alpha: 0.2),
            const Color(0xFFFF7FD8).withValues(alpha: 0.18),
            clear,
            Colors.white.withValues(alpha: 0.22),
            const Color(0xFFFFE27F).withValues(alpha: 0.16),
            const Color(0xFF9F8CFF).withValues(alpha: 0.14),
            clear,
          ],
          stops: const [0, 0.1, 0.22, 0.34, 0.5, 0.6, 0.72, 0.85, 1],
        ).createShader(rect),
    );
    // The clear plastic ring around the hub, and the lip it sits behind.
    canvas.drawCircle(
      c,
      r * 0.3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.1
        ..color = Colors.white.withValues(alpha: 0.42),
    );
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.black.withValues(alpha: 0.28);
    canvas.drawCircle(c, r * 0.35, thin);
    canvas.drawCircle(c, r * 0.25, thin);
    // The hub, with the hole in its middle.
    final hub = Rect.fromCircle(center: c, radius: r * 0.2);
    canvas.drawCircle(
      c,
      r * 0.2,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.5),
          colors: [Color(0xFFFFFFFF), Color(0xFFC9CED4), Color(0xFF8D949C)],
          stops: [0, 0.6, 1],
        ).createShader(hub),
    );
    canvas.drawCircle(c, r * 0.2, thin);
    canvas.drawCircle(c, r * 0.075, Paint()..color = hole);
    canvas.drawCircle(
      c,
      r * 0.075,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.black.withValues(alpha: 0.4),
    );
    // The edge: a dark line outside, a light one just inside.
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      c,
      r - 1.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.hole != hole;
}

/// The well the disc sits in: a dished circle, shadowed at the top left, with
/// the disc's own soft shadow on its floor.
class _WellPainter extends CustomPainter {
  const _WellPainter({required this.dark, required this.outline});
  final bool dark;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF05080A), Color(0xFF2A333A)]
              : const [Color(0xFF8E979C), Color(0xFFEEF2F3)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = outline.withValues(alpha: 0.7),
    );
    canvas.drawCircle(
      c + Offset(0, r * 0.03),
      r * 0.9,
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? 0.55 : 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.04),
    );
  }

  @override
  bool shouldRepaint(_WellPainter old) =>
      old.dark != dark || old.outline != outline;
}

/// The glass lid: a bright sheen across the top left and a rim of light.
class _LidPainter extends CustomPainter {
  const _LidPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: const Alignment(0.15, 0.15),
          colors: [
            Colors.white.withValues(alpha: dark ? 0.16 : 0.34),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dark ? 0.3 : 0.8),
            Colors.transparent,
            Colors.white.withValues(alpha: dark ? 0.08 : 0.3),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_LidPainter old) => old.dark != dark;
}
