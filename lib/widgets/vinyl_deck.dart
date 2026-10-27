import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// A procedural turntable. Only the record animates; labels and transport do
/// not rebuild on each frame. Pausing, reduced motion and hidden routes stop it.
class VinylDeck extends StatefulWidget {
  const VinylDeck({super.key, required this.label, required this.playing});

  final Widget label;
  final bool playing;

  @override
  State<VinylDeck> createState() => _VinylDeckState();
}

class _VinylDeckState extends State<VinylDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  void _syncMotion() {
    final animate =
        widget.playing &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_rotation.isAnimating) {
      _rotation.repeat();
    } else if (!animate) {
      _rotation.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(VinylDeck oldWidget) {
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
    final a = Wv.of(context);
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          return Container(
            padding: EdgeInsets.all(side * 0.055),
            decoration: BoxDecoration(
              gradient: a.chromeGradient,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: a.outline.withValues(alpha: 0.7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.13),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(side * 0.025),
                    child: RotationTransition(
                      turns: _rotation,
                      child: CustomPaint(
                        painter: const _RecordPainter(),
                        child: Center(
                          child: SizedBox.square(
                            dimension: side * 0.31,
                            child: ClipOval(child: widget.label),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: side * 0.038,
                  height: side * 0.038,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F0DE),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF4D4456)),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _TonearmPainter(a.outline)),
                  ),
                ),
                for (final alignment in [
                  Alignment.topLeft,
                  Alignment.bottomLeft,
                  Alignment.topRight,
                  Alignment.bottomRight,
                ])
                  Align(
                    alignment: alignment,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: a.outline.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RecordPainter extends CustomPainter {
  const _RecordPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center + const Offset(0, 3),
      radius,
      Paint()
        ..color = const Color(0x5531293F)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xFF18171F),
            Color(0xFF373540),
            Color(0xFF15151B),
            Color(0xFF302D38),
            Color(0xFF18171F),
          ],
          stops: [0, 0.22, 0.49, 0.76, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65;
    for (double r = radius * 0.4; r < radius * 0.98; r += 2.8) {
      groove.color = const Color(0xFFAAA3B9).withValues(alpha: 0.13);
      canvas.drawCircle(center, r, groove);
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.83),
      math.pi * 1.12,
      0.36,
      false,
      Paint()
        ..color = const Color(0xFFDED6EC).withValues(alpha: 0.08)
        ..strokeWidth = radius * 0.16
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_RecordPainter oldDelegate) => false;
}

class _TonearmPainter extends CustomPainter {
  const _TonearmPainter(this.outline);
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width * 0.91, size.height * 0.08);
    final end = Offset(size.width * 0.77, size.height * 0.66);
    canvas.drawLine(
      start + const Offset(2, 3),
      end + const Offset(2, 3),
      Paint()
        ..color = const Color(0x4430273D)
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = outline
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xFFE8EDF3)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(start, 7, Paint()..color = outline);
    canvas.drawCircle(start, 3, Paint()..color = const Color(0xFFE8EDF3));
    canvas.drawLine(
      end - const Offset(0, 7),
      end + const Offset(-2, 9),
      Paint()
        ..color = outline
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TonearmPainter oldDelegate) =>
      outline != oldDelegate.outline;
}
