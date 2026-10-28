import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Height of the cassette as a fraction of its width.
const double kCassetteAspect = 0.68;

/// How far the paper label is turned, in radians (a hand-stuck look).
const double kCassetteLabelTilt = -0.012;

/// One full cycle of the spool animation. The take-up spool turns 4 times in
/// it (one turn per 1.5 s) and the supply spool 5 times (a little faster), so
/// both end on a whole turn and the loop has no jump.
const Duration kCassetteSpinCycle = Duration(seconds: 6);
const double kCassetteTakeUpTurns = 4;
const double kCassetteSupplyTurns = 5;

/// Where the parts of the cassette sit, for a cassette [w] wide. The painter
/// and the label text laid over it both use these.
class CassetteGeometry {
  const CassetteGeometry(this.w);
  final double w;

  double get h => w * kCassetteAspect;
  Rect get body => Rect.fromLTWH(0, 0, w, h);
  double get radius => w * 0.045;

  Rect get label => Rect.fromLTWH(w * 0.07, w * 0.055, w * 0.86, w * 0.275);
  double get stripe => w * 0.07;

  Rect get window => Rect.fromLTWH(w * 0.25, w * 0.365, w * 0.5, w * 0.2);
  Offset get supply => Offset(w * 0.375, w * 0.465);
  Offset get takeUp => Offset(w * 0.625, w * 0.465);
  double get reelMax => w * 0.098;
  double get hub => w * 0.042;
}

/// The tape on the two reels for a song [progress] (0 to 1): all of it on the
/// supply (left) reel at the start and all of it on the take-up (right) reel
/// at the end, the radii changing linearly in between. A reel never gets
/// thinner than a bare hub with a turn of tape.
({double supply, double takeUp}) cassetteReelRadii(
  double progress, {
  required double reelMax,
  required double hub,
}) {
  final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
  final least = hub * 1.15;
  return (
    supply: reelMax + (least - reelMax) * p,
    takeUp: least + (reelMax - least) * p,
  );
}

/// The whole cassette: body, screws, paper label (without its text), window,
/// the two reels with their tape, and the shell's lower edge. It repaints on
/// its own when [spin] ticks or [progress] changes, never the widget tree.
///
/// With [mini] (the picker thumbnail) the label shows bars for text.
class CassettePainter extends CustomPainter {
  CassettePainter({
    required this.a,
    required this.spin,
    required this.progress,
    this.mini = false,
  }) : super(repaint: Listenable.merge([spin, progress]));

  final WvPalette a;
  final Animation<double> spin;
  final ValueListenable<double> progress;
  final bool mini;

  static const _tape = Color(0xFF4B3527);
  static const _paper = Color(0xFFF3EEDC);
  static const _ink = Color(0xFF24272D);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = math.min(size.width, size.height / kCassetteAspect);
    final g = CassetteGeometry(w);
    canvas.save();
    canvas.translate((size.width - w) / 2, (size.height - g.h) / 2);
    _body(canvas, g);
    _label(canvas, g);
    _window(canvas, g);
    _lowerEdge(canvas, g);
    canvas.restore();
  }

  void _body(Canvas canvas, CassetteGeometry g) {
    final shell = RRect.fromRectAndRadius(g.body, Radius.circular(g.radius));
    canvas.drawRRect(
      shell,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: a.dark
              ? const [Color(0xFF59606A), Color(0xFF383D45), Color(0xFF2B3036)]
              : const [Color(0xFFCDD2D9), Color(0xFFA9AEB7), Color(0xFF8F95A0)],
          stops: const [0, 0.55, 1],
        ).createShader(g.body),
    );
    // A bevel: light along the top edge, dark along the bottom.
    canvas.drawRRect(
      shell.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: a.dark ? 0.25 : 0.7),
            Colors.transparent,
            Colors.black.withValues(alpha: a.dark ? 0.45 : 0.22),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(g.body),
    );
    canvas.drawRRect(
      shell,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = a.outline.withValues(alpha: 0.7),
    );
    final inset = g.w * 0.034;
    final r = g.w * 0.016;
    for (final p in [
      Offset(inset, inset),
      Offset(g.w - inset, inset),
      Offset(inset, g.h - inset),
      Offset(g.w - inset, g.h - inset),
    ]) {
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            colors: a.dark
                ? const [Color(0xFF9AA1AB), Color(0xFF454B53)]
                : const [Color(0xFFFFFFFF), Color(0xFF8A9099)],
          ).createShader(Rect.fromCircle(center: p, radius: r)),
      );
      // A slot, turned a different way on each screw.
      final turn = (p.dx * 5 + p.dy * 3) % math.pi;
      final d = Offset(math.cos(turn), math.sin(turn)) * (r * 0.75);
      canvas.drawLine(
        p - d,
        p + d,
        Paint()
          ..strokeWidth = 0.9
          ..color = Colors.black.withValues(alpha: 0.55),
      );
    }
  }

  void _label(Canvas canvas, CassetteGeometry g) {
    final r = g.label;
    canvas.save();
    canvas.translate(r.center.dx, r.center.dy);
    canvas.rotate(kCassetteLabelTilt);
    canvas.translate(-r.center.dx, -r.center.dy);
    final paper = RRect.fromRectAndRadius(r, Radius.circular(g.w * 0.012));
    canvas.drawRRect(
      paper,
      Paint()..color = a.dark ? _paper.withValues(alpha: 0.94) : _paper,
    );
    canvas.save();
    canvas.clipRRect(paper);
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.top, r.width, g.stripe),
      Paint()..color = a.accent,
    );
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.top + g.stripe, r.width, g.w * 0.006),
      Paint()..color = a.accent.withValues(alpha: 0.35),
    );
    final ink = Paint()
      ..strokeWidth = 0.7
      ..color = _ink.withValues(alpha: 0.28);
    if (mini) {
      final bar = Paint()
        ..strokeWidth = g.w * 0.028
        ..strokeCap = StrokeCap.round
        ..color = _ink.withValues(alpha: 0.7);
      final y = r.top + g.w * 0.135;
      canvas.drawLine(
        Offset(r.left + g.w * 0.07, y),
        Offset(r.left + g.w * 0.5, y),
        bar,
      );
      canvas.drawLine(
        Offset(r.left + g.w * 0.07, y + g.w * 0.065),
        Offset(r.left + g.w * 0.34, y + g.w * 0.065),
        bar..color = _ink.withValues(alpha: 0.4),
      );
      canvas.drawCircle(
        Offset(r.left + g.w * 0.045, r.top + g.stripe / 2),
        g.stripe * 0.32,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    } else {
      for (final y in [g.w * 0.165, g.w * 0.235]) {
        canvas.drawLine(
          Offset(r.left + g.w * 0.03, r.top + y),
          Offset(r.right - g.w * 0.03, r.top + y),
          ink,
        );
      }
    }
    canvas.restore();
    canvas.drawRRect(
      paper,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.black.withValues(alpha: 0.25),
    );
    canvas.restore();
  }

  void _window(Canvas canvas, CassetteGeometry g) {
    final win = RRect.fromRectAndRadius(g.window, Radius.circular(g.w * 0.03));
    canvas.drawRRect(win, Paint()..color = const Color(0xFF1B1E22));
    canvas.save();
    canvas.clipRRect(win);
    final radii = cassetteReelRadii(
      progress.value,
      reelMax: g.reelMax,
      hub: g.hub,
    );
    // The tape between the reels, along the bottom.
    canvas.drawLine(
      Offset(g.supply.dx, g.supply.dy + radii.supply),
      Offset(g.takeUp.dx, g.takeUp.dy + radii.takeUp),
      Paint()
        ..strokeWidth = math.max(1, g.w * 0.004)
        ..color = _tape,
    );
    final turn = spin.value * 2 * math.pi;
    _reel(canvas, g, g.supply, radii.supply, turn * kCassetteSupplyTurns);
    _reel(canvas, g, g.takeUp, radii.takeUp, turn * kCassetteTakeUpTurns);
    canvas.restore();
    // A glint across the glass.
    canvas.drawRRect(
      win,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.2),
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.06),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(g.window),
    );
    canvas.drawRRect(
      win,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.6),
    );
  }

  void _reel(
    Canvas canvas,
    CassetteGeometry g,
    Offset c,
    double radius,
    double angle,
  ) {
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [_tape.withValues(alpha: 0.9), _tape],
          stops: const [0.6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: radius)),
    );
    final hub = g.hub;
    // A glint on the tape that goes round, so a full reel visibly turns.
    if (radius > hub * 1.5) {
      final ring = (radius + hub) / 2;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: ring),
        angle,
        0.8,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (radius - hub) * 0.55
          ..color = Colors.white.withValues(alpha: 0.1),
      );
    }
    canvas.drawCircle(c, hub, Paint()..color = const Color(0xFFE9E7E0));
    canvas.drawCircle(c, hub * 0.64, Paint()..color = const Color(0xFF16181B));
    // Six teeth pointing in from the hub's ring.
    final tooth = Paint()
      ..strokeWidth = hub * 0.2
      ..color = const Color(0xFFE9E7E0);
    for (var i = 0; i < 6; i++) {
      final t = angle + i * math.pi / 3;
      final dir = Offset(math.cos(t), math.sin(t));
      canvas.drawLine(c + dir * (hub * 0.66), c + dir * (hub * 0.38), tooth);
    }
  }

  void _lowerEdge(Canvas canvas, CassetteGeometry g) {
    final w = g.w;
    final path = Path()
      ..moveTo(w * 0.21, g.h)
      ..lineTo(w * 0.265, w * 0.6)
      ..lineTo(w * 0.735, w * 0.6)
      ..lineTo(w * 0.79, g.h)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: a.dark ? 0.35 : 0.2),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black.withValues(alpha: 0.3),
    );
    for (final x in [0.33, 0.67]) {
      canvas.drawCircle(
        Offset(w * x, w * 0.645),
        w * 0.014,
        Paint()..color = Colors.black.withValues(alpha: 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(CassettePainter old) =>
      old.a != a ||
      old.spin != spin ||
      old.progress != progress ||
      old.mini != mini;
}

/// A fixed value, for the thumbnail (which never changes or listens).
class StillValue implements ValueListenable<double> {
  const StillValue(this.value);
  @override
  final double value;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
