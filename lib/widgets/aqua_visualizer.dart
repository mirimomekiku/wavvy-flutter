import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:wavvy/playback/visualizer_math.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// The spectrum as glossy Aqua gel bars with a soft reflection and small peak
/// caps, in a recessed LCD-style panel. [bands] and [peaks] are the latest
/// levels (0..1); they arrive a few times a second, so the widget eases the
/// drawn bars toward them on its own ticker, and only the single painter
/// repaints. With reduced motion (or no levels) it draws one still, low frame.
class AquaVisualizer extends StatefulWidget {
  const AquaVisualizer({
    super.key,
    required this.bands,
    this.peaks = const [],
    this.barCount = kVisualizerBands,
    this.panel = true,
  });
  final List<double> bands;
  final List<double> peaks;
  final int barCount;

  /// Draw the recessed LCD panel behind the bars.
  final bool panel;

  @override
  State<AquaVisualizer> createState() => _AquaVisualizerState();
}

class _AquaVisualizerState extends State<AquaVisualizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _repaint = ValueNotifier<int>(0);
  late List<double> _shown = List.filled(widget.barCount, 0);
  late List<double> _shownPeaks = List.filled(widget.barCount, 0);
  bool _still = false;

  List<double> _target(List<double> v) => v.isEmpty
      ? List.filled(widget.barCount, 0)
      : [for (var i = 0; i < widget.barCount; i++) i < v.length ? v[i] : 0.0];

  void _tick(Duration _) {
    final bands = _target(widget.bands);
    final peaks = _target(widget.peaks);
    _shown = smoothBands(_shown, bands, attack: 0.5, decay: 0.12);
    _shownPeaks = smoothBands(_shownPeaks, peaks, attack: 0.6, decay: 0.3);
    _repaint.value++;
    if (maxBandGap(_shown, bands) < 0.002 &&
        maxBandGap(_shownPeaks, peaks) < 0.002) {
      _ticker.stop();
    }
  }

  @override
  void didUpdateWidget(AquaVisualizer old) {
    super.didUpdateWidget(old);
    if (old.barCount != widget.barCount) {
      _shown = List.filled(widget.barCount, 0);
      _shownPeaks = List.filled(widget.barCount, 0);
    }
    if (!_still && !_ticker.isActive) _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final still = _still;
    final stillFrame = still ? stillBands(bands: widget.barCount) : null;
    return Semantics(
      label: 'Audio spectrum',
      image: true,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: widget.panel
                ? a.lcdDecoration.copyWith(
                    borderRadius: BorderRadius.circular(14),
                  )
                : const BoxDecoration(),
            child: CustomPaint(
              size: Size.infinite,
              painter: _SpectrumPainter(
                repaint: _repaint,
                bands: () => stillFrame ?? _shown,
                peaks: () => stillFrame ?? _shownPeaks,
                accent: a.accent,
                dark: a.dark,
                still: still,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required Listenable repaint,
    required this.bands,
    required this.peaks,
    required this.accent,
    required this.dark,
    required this.still,
  }) : super(repaint: repaint);

  final List<double> Function() bands;
  final List<double> Function() peaks;
  final Color accent;
  final bool dark;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final levels = bands();
    final caps = peaks();
    final n = levels.length;
    if (n == 0 || size.isEmpty) return;
    const pad = 12.0;
    final w = size.width - pad * 2;
    // The top 72% holds the bars; the rest is their reflection.
    final base = size.height * 0.74;
    final room = base - pad;
    if (w <= 0 || room <= 0) return;
    final slot = w / n;
    final barW = math.max(1.0, slot * 0.72);
    final gel = aquaGel(accent).colors;
    final capColor = Color.lerp(accent, Colors.white, dark ? 0.7 : 0.35)!;
    final fill = Paint();
    for (var i = 0; i < n; i++) {
      final x = pad + slot * i + (slot - barW) / 2;
      final h = math.max(2.0, levels[i].clamp(0.0, 1.0) * room);
      final bar = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, base - h, barW, h),
        topLeft: Radius.circular(barW / 2.5),
        topRight: Radius.circular(barW / 2.5),
      );
      // Gel: the shine runs down the bar, so the shader follows each bar.
      fill.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: gel,
        stops: const [0, 0.45, 0.52, 1],
      ).createShader(bar.outerRect);
      canvas.drawRRect(bar, fill);
      canvas.drawRRect(
        bar,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Color.lerp(
            accent,
            Colors.black,
            0.3,
          )!.withValues(alpha: 0.6),
      );

      // Reflection: a short, fading mirror under the baseline.
      final rh = math.min(h * 0.4, size.height - base - 4);
      if (rh > 1) {
        final mirror = Rect.fromLTWH(x, base + 2, barW, rh);
        fill.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: dark ? 0.32 : 0.28),
            accent.withValues(alpha: 0),
          ],
        ).createShader(mirror);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            mirror,
            bottomLeft: Radius.circular(barW / 3),
            bottomRight: Radius.circular(barW / 3),
          ),
          fill,
        );
      }

      // Peak cap, a little above the bar.
      final capY = base - math.max(h, caps[i].clamp(0.0, 1.0) * room) - 4;
      if (capY > 0 && !still) {
        fill.shader = null;
        fill.color = capColor;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, capY, barW, 2.5),
            const Radius.circular(1.2),
          ),
          fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) =>
      old.accent != accent || old.dark != dark || old.still != still;
}
