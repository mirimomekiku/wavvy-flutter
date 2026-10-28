import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';

/// Milliseconds one full turn of the jog wheel moves the song.
const int kJogTurnMs = 60000;

/// How far a screen reader's increase / decrease moves the song.
const Duration kJogStep = Duration(seconds: 5);

/// The turn from angle [from] to angle [to] (radians) the short way round,
/// -pi..pi, so crossing the wheel's left edge does not read as a full turn.
double jogDelta(double from, double to) {
  var d = to - from;
  while (d > math.pi) {
    d -= 2 * math.pi;
  }
  while (d < -math.pi) {
    d += 2 * math.pi;
  }
  return d;
}

/// Wins the gesture arena as soon as a finger lands, so a vertical drag on
/// the wheel turns it rather than scrolling the page behind it.
class _JogRecognizer extends OneSequenceGestureRecognizer {
  _JogRecognizer({
    required this.onStart,
    required this.onMove,
    required this.onEnd,
  });
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onStart(event.localPosition);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onMove(event.localPosition);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
      onEnd();
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'jog wheel';
}

/// A rotary jog wheel that scrubs the song. Drag around it to turn it; the
/// player is asked to seek once, when the finger lifts (like the seek bar),
/// not for each touch event. A screen reader sees a slider that moves 5 s.
class HifiJogWheel extends ConsumerStatefulWidget {
  const HifiJogWheel({super.key, required this.size});
  final double size;

  @override
  ConsumerState<HifiJogWheel> createState() => _HifiJogWheelState();
}

class _HifiJogWheelState extends ConsumerState<HifiJogWheel> {
  /// Where the wheel is while it is being turned (milliseconds).
  double? _drag;
  double _prevAngle = 0;
  bool _moved = false;

  double _angleAt(Offset p) {
    final c = widget.size / 2;
    return math.atan2(p.dy - c, p.dx - c);
  }

  void _start(Offset p) {
    final playing = ref.read(positionProvider).inMilliseconds.toDouble();
    _prevAngle = _angleAt(p);
    _moved = false;
    setState(() => _drag = _drag ?? playing);
  }

  void _move(Offset p) {
    final duration = ref.read(durationProvider);
    final angle = _angleAt(p);
    final delta = jogDelta(_prevAngle, angle);
    _prevAngle = angle;
    if (duration <= Duration.zero || delta == 0) return;
    _moved = true;
    setState(
      () => _drag = (_drag! + delta / (2 * math.pi) * kJogTurnMs).clamp(
        0.0,
        duration.inMilliseconds.toDouble(),
      ),
    );
  }

  void _end() {
    final at = _drag;
    if (at == null) return;
    if (!_moved) {
      setState(() => _drag = null);
      return;
    }
    // Keep the wheel where it was let go until the player has moved.
    ref
        .read(playerProvider.notifier)
        .seek(Duration(milliseconds: at.round()))
        .whenComplete(() {
          if (mounted) setState(() => _drag = null);
        });
  }

  void _nudge(Duration by) {
    final duration = ref.read(durationProvider);
    if (duration <= Duration.zero) return;
    final now = ref.read(positionProvider);
    final next = now + by;
    ref
        .read(playerProvider.notifier)
        .seek(
          next < Duration.zero
              ? Duration.zero
              : next > duration
              ? duration
              : next,
        );
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final duration = ref.watch(durationProvider);
    final playing = ref.watch(positionProvider);
    final position = _drag == null
        ? playing
        : Duration(milliseconds: _drag!.round());
    final turn = (position.inMilliseconds % kJogTurnMs) / kJogTurnMs;
    String time(Duration d) => PlayerUtils.formatDuration(d);
    return Semantics(
      slider: true,
      label: 'Jog wheel, seek',
      value: '${time(position)} of ${time(duration)}',
      increasedValue: time(
        position + kJogStep > duration ? duration : position + kJogStep,
      ),
      decreasedValue: time(
        position - kJogStep < Duration.zero
            ? Duration.zero
            : position - kJogStep,
      ),
      onIncrease: () => _nudge(kJogStep),
      onDecrease: () => _nudge(-kJogStep),
      child: ExcludeSemantics(
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _JogRecognizer:
                GestureRecognizerFactoryWithHandlers<_JogRecognizer>(
                  () => _JogRecognizer(
                    onStart: _start,
                    onMove: _move,
                    onEnd: _end,
                  ),
                  (r) {},
                ),
          },
          child: SizedBox.square(
            dimension: widget.size,
            child: RepaintBoundary(
              child: CustomPaint(painter: HifiJogPainter(a, turn)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The wheel: a bevelled bezel, a ring of tick marks (one a second over a
/// minute), and a metal knob with a knurled edge and a pointer. [turn] (0..1)
/// is how far round the knob is.
class HifiJogPainter extends CustomPainter {
  HifiJogPainter(this.a, this.turn);
  final WvPalette a;
  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final c = size.center(Offset.zero);
    final R = size.shortestSide / 2;
    final ink = a.text.withValues(alpha: 0.7);

    // Bezel: a dark recess with a light lip.
    canvas.drawCircle(
      c + Offset(0, R * 0.02),
      R,
      Paint()
        ..color = Colors.white.withValues(alpha: a.dark ? 0.08 : 0.8)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      c,
      R * 0.98,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: a.dark
              ? const [Color(0xFF14181D), Color(0xFF2A3037)]
              : const [Color(0xFF8D949C), Color(0xFFC9CDD2)],
        ).createShader(Rect.fromCircle(center: c, radius: R)),
    );

    // Tick ring.
    for (var i = 0; i < 60; i++) {
      final major = i % 5 == 0;
      final angle = -math.pi / 2 + i / 60 * 2 * math.pi;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        c + dir * (R * (major ? 0.82 : 0.88)),
        c + dir * (R * 0.95),
        Paint()
          ..strokeWidth = major ? 1.8 : 1
          ..strokeCap = StrokeCap.round
          ..color = a.dark
              ? Colors.white.withValues(alpha: major ? 0.8 : 0.4)
              : Colors.black.withValues(alpha: major ? 0.7 : 0.35),
      );
    }

    // The knob.
    final knob = R * 0.74;
    canvas.drawCircle(
      c + Offset(0, R * 0.05),
      knob,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, R * 0.04),
    );
    canvas.drawCircle(
      c,
      knob,
      Paint()
        ..shader = SweepGradient(
          transform: GradientRotation(turn * 2 * math.pi),
          colors: a.dark
              ? const [
                  Color(0xFF59606A),
                  Color(0xFF2B3036),
                  Color(0xFF59606A),
                  Color(0xFF2B3036),
                  Color(0xFF59606A),
                ]
              : const [
                  Color(0xFFF2F3F5),
                  Color(0xFFAEB3BA),
                  Color(0xFFF2F3F5),
                  Color(0xFFAEB3BA),
                  Color(0xFFF2F3F5),
                ],
        ).createShader(Rect.fromCircle(center: c, radius: knob)),
    );
    // Knurled edge: short grooves that turn with the knob.
    const grooves = 72;
    final groove = Paint()
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: a.dark ? 0.55 : 0.32);
    for (var i = 0; i < grooves; i++) {
      final angle = turn * 2 * math.pi + i / grooves * 2 * math.pi;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(c + dir * (knob * 0.9), c + dir * (knob * 0.99), groove);
    }
    canvas.drawCircle(
      c,
      knob * 0.99,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.45),
    );
    // The dished top, and the pointer on it.
    final top = knob * 0.7;
    canvas.drawCircle(
      c,
      top,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: a.dark
              ? const [Color(0xFF454B54), Color(0xFF22272D)]
              : const [Color(0xFFFFFFFF), Color(0xFFC4C8CE)],
        ).createShader(Rect.fromCircle(center: c, radius: top)),
    );
    final angle = -math.pi / 2 + turn * 2 * math.pi;
    final dir = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      c + dir * (top * 0.35),
      c + dir * (top * 0.92),
      Paint()
        ..strokeWidth = math.max(2.5, R * 0.05)
        ..strokeCap = StrokeCap.round
        ..color = a.accent,
    );
    canvas.drawCircle(c, R * 0.05, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(HifiJogPainter old) => old.turn != turn || old.a != a;
}
